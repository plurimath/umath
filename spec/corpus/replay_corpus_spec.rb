# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../scripts/replay_corpus"

# scripts/replay_corpus.rb --testsuite: the pin checks and the raw-tree and
# typed-model replay, against a small testsuite checkout built in a temporary git
# repository.
RSpec.describe UmathReplayCorpus do
  PIN_FILE = File.expand_path("../fixtures/testsuite-pin.yml", __dir__)

  before do
    next if Umath::Engine.native_available?
    raise "the native engine is required" if ENV["UMATH_REQUIRE_NATIVE"] == "1"

    skip "the native engine is not available"
  end

  # The expected value of a raw-tree row for the input "a".
  let(:letter) do
    {
      "preprocessed" => { "str" => "a" },
      "tree" => { "hash" => [[{ "sym" => "factor" }, { "hash" => [
        [{ "sym" => "atom" }, { "hash" => [
          [{ "sym" => "alphanumeric" }, { "slice" => "a", "byte_offset" => 0, "char_offset" => 0 }],
        ] }],
      ] }]] },
    }
  end

  let(:refusal) { { "refusal" => { "category" => "parse_error", "byte_offset" => 0 } } }

  let(:raw_rows) do
    [
      { "id" => "letter.raw", "input" => { "str" => "a" }, "options" => { "decimal" => "." }, "expected" => letter },
      { "id" => "refused.raw", "input" => { "str" => ")" }, "options" => { "decimal" => "." }, "expected" => refusal },
    ]
  end

  # Typed-model rows for "a" and ")". The expected values come from
  # scripts/stage_cases.rb, the producer of the testsuite's typed-model rows;
  # these examples check that the replay runs and compares such rows.
  let(:model_rows) do
    [["letter.model", "a"], ["refused.model", ")"]].map do |id, input|
      { "id" => id, "input" => { "str" => input }, "options" => { "decimal" => "." },
        "expected" => StageCases::Outcome.model_of(input, :ruby) }
    end
  end

  # A testsuite checkout with one unicode generation: a legacy payload,
  # which the replay skips, a raw-tree payload of +rows+ and, given
  # +model_rows+, a typed-model payload of them. Returns
  # [commit, snapshot digest].
  def build_testsuite(dir, rows, model_rows: nil)
    gen = File.join(dir, "stages/unicode/generations/000001")
    FileUtils.mkdir_p(File.join(gen, "payloads"))
    payloads = {
      "payloads/sample.yaml" => YAML.dump("schema" => "plurimath-corpus/unicode/1", "group" => "sample",
                                          "cases" => [{ "id" => "letter", "input" => "a" }]),
      "payloads/raw-sample.yaml" => YAML.dump("schema" => "plurimath-stage/unicode/cases/1", "group" => "raw-sample",
                                              "boundary" => "raw-tree", "cases" => rows),
    }
    if model_rows
      payloads["payloads/model-sample.yaml"] =
        YAML.dump("schema" => "plurimath-stage/unicode/cases/1", "group" => "model-sample",
                  "boundary" => "typed-model", "cases" => model_rows)
    end
    payloads.each { |path, bytes| File.binwrite(File.join(gen, path), bytes) }
    provenance = YAML.dump(
      "schema" => "plurimath-stage/provenance/1", "language" => "unicode", "generation" => 1,
      "payloads" => payloads.sort.map { |path, bytes| { "path" => path, "sha256" => Digest::SHA256.hexdigest(bytes) } },
    )
    File.binwrite(File.join(gen, "provenance.yaml"), provenance)
    digest = StageCases.snapshot_digest(payloads.merge("provenance.yaml" => provenance))
    FileUtils.mkdir_p(File.join(dir, "generations"))
    ledger = { "schema" => "plurimath-stage/ledger/1", "language" => "unicode", "layout" => 1,
               "entries" => [{ "generation" => 1, "path" => "stages/unicode/generations/000001",
                               "snapshot_digest" => digest }] }
    File.binwrite(File.join(dir, "generations/unicode.yaml"), YAML.dump(ledger))
    git = ["git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com"]
    system("git", "init", "-q", dir, exception: true)
    system(*git, "add", ".", exception: true)
    system(*git, "commit", "-qm", "t", exception: true)
    [described_class.git(dir, "rev-parse", "HEAD"), digest]
  end

  def write_pin(path, **fields)
    pin = { "schema" => "plurimath-stage/pin/1", "repository" => "https://github.com/plurimath/plurimath-testsuite",
            "commit" => nil, "language" => "unicode", "generation" => 1, "snapshot_digest" => nil }
    File.binwrite(path, YAML.dump(pin.merge(fields.transform_keys(&:to_s)).compact))
    path
  end

  def run_replay(testsuite, pin, **options)
    described_class.run(testsuite: testsuite, pin: pin, log: StringIO.new, **options)
  end

  describe "the committed pin" do
    it "names unicode generation 5 at an exact testsuite commit" do
      pin = described_class.load_pin(PIN_FILE)
      expect(pin.language).to eq("unicode")
      expect(pin.generation).to eq(5)
      expect(pin.commit).to match(/\A\h{40}\z/)
      expect(pin.digest).to match(/\Asha256:\h{64}\z/)
    end
  end

  describe ".load_pin" do
    it "refuses a pin with a missing, unknown or malformed field" do
      Dir.mktmpdir do |dir|
        good = { commit: "a" * 40, snapshot_digest: "sha256:#{'0' * 64}" }
        expect(described_class.load_pin(write_pin(File.join(dir, "ok.yml"), **good)).generation).to eq(1)
        {
          "schema" => { schema: "plurimath-stage/pin/2" },
          "repository" => { repository: "https://github.com/plurimath/plurimath" },
          "commit" => { commit: "2a18ff4" },
          "language" => { language: "latex" },
          "generation" => { generation: 0 },
          "snapshot_digest" => { snapshot_digest: "0a6f19b9" },
          "missing" => { snapshot_digest: nil },
        }.each do |name, change|
          path = write_pin(File.join(dir, "#{name}.yml"), **good, **change)
          expect { described_class.load_pin(path) }.to raise_error(described_class::Error), name
        end
        File.binwrite(File.join(dir, "extra.yml"), YAML.dump(YAML.load_file(File.join(dir, "ok.yml")).merge("x" => 1)))
        expect { described_class.load_pin(File.join(dir, "extra.yml")) }
          .to raise_error(described_class::Error, /unknown keys x/)
      end
    end
  end

  describe ".run" do
    it "replays every raw-tree row on both engines when the pin matches" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, digest = build_testsuite(testsuite, raw_rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        summary = run_replay(testsuite, pin, language: "unicode", generation: 1)
        expect(summary.values_at("raw_tree_payloads", "raw_tree_rows", "mismatched_rows")).to eq([1, 2, 0])
        expect(summary["engines"]).to eq(%w[ruby native])
      end
    end

    it "fails when the pinned commit is not the checkout's HEAD" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        _commit, digest = build_testsuite(testsuite, raw_rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: "0" * 40, snapshot_digest: digest)
        expect { run_replay(testsuite, pin) }.to raise_error(described_class::Error, /is not the checkout's HEAD/)
      end
    end

    it "fails when the pinned digest is not the generation's" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, = build_testsuite(testsuite, raw_rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: "sha256:#{'0' * 64}")
        expect { run_replay(testsuite, pin) }.to raise_error(described_class::Error, /is not the expected sha256:0{64}/)
      end
    end

    it "fails when a committed generation file no longer matches the ledger digest" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, digest = build_testsuite(testsuite, raw_rows)
        File.open(File.join(testsuite, "stages/unicode/generations/000001/payloads/sample.yaml"), "ab") { |io| io.write("x\n") }
        system("git", "-C", testsuite, "-c", "user.name=t", "-c", "user.email=t@example.com",
               "commit", "-qam", "tamper", exception: true)
        pin = write_pin(File.join(dir, "pin.yml"), commit: described_class.git(testsuite, "rev-parse", "HEAD"),
                                                   snapshot_digest: digest)
        expect(commit).not_to eq(described_class.git(testsuite, "rev-parse", "HEAD"))
        expect { run_replay(testsuite, pin) }.to raise_error(described_class::Error, /does not match the ledger's/)
      end
    end

    it "fails when the checkout has uncommitted stage files" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, digest = build_testsuite(testsuite, raw_rows)
        File.open(File.join(testsuite, "stages/unicode/generations/000001/payloads/sample.yaml"), "ab") { |io| io.write("x\n") }
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        expect { run_replay(testsuite, pin) }.to raise_error(described_class::Error, /uncommitted stage files/)
      end
    end

    it "fails when the pinned generation is not in the ledger" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, digest = build_testsuite(testsuite, raw_rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, generation: 2, snapshot_digest: digest)
        expect { run_replay(testsuite, pin) }.to raise_error(described_class::Error, /has no generation 2/)
      end
    end

    it "fails when the caller expects another generation or language than the pin's" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, digest = build_testsuite(testsuite, raw_rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        expect { run_replay(testsuite, pin, generation: 2) }
          .to raise_error(described_class::Error, /--generation 2 is not the pinned 1/)
        expect { run_replay(testsuite, pin, language: "latex") }
          .to raise_error(described_class::Error, /--language latex is not the pinned unicode/)
      end
    end

    it "fails and reports the row when a parse differs from the expected value" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        rows = raw_rows.dup
        rows[1] = rows[1].merge("expected" => { "refusal" => { "category" => "parse_error", "byte_offset" => 1 } })
        commit, digest = build_testsuite(testsuite, rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        report = File.join(dir, "report.json")
        expect { run_replay(testsuite, pin, report: report) }
          .to raise_error(described_class::Error, /1 rows differ: refused\.raw/)
        failures = JSON.parse(File.read(report)).fetch("failures")
        expect(failures.map { |f| [f["id"], f["mismatches"].map { |m| m["engine"] }] })
          .to eq([["refused.raw", %w[ruby native]]])
      end
    end

    it "replays the typed-model rows beside the raw-tree rows and reports both" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, digest = build_testsuite(testsuite, raw_rows, model_rows: model_rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        ids = File.join(dir, "executed-ids.txt")
        summary = run_replay(testsuite, pin, executed_ids: ids)
        expect(summary.values_at("raw_tree_rows", "executed_rows", "mismatched_rows")).to eq([2, 4, 0])
        expect(File.read(ids)).to eq("letter.model\nletter.raw\nrefused.model\nrefused.raw\n")
        expect(summary["boundaries"].transform_values { |c| c.values_at("payloads", "rows") })
          .to eq("raw-tree" => [1, 2], "typed-model" => [1, 2])
        expect(summary["boundaries"]["typed-model"]["ids_sha256"])
          .to eq(Digest::SHA256.hexdigest("letter.model\nrefused.model"))
      end
    end

    it "reads the pre-rename Unicodemath::Model:: node tags of a typed-model row as Umath::Model::" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        legacy = model_rows.map do |r|
          r.merge("expected" => JSON.parse(JSON.generate(r["expected"]).gsub('"Umath::Model::', '"Unicodemath::Model::')))
        end
        expect(legacy[0]["expected"]).not_to eq(model_rows[0]["expected"])
        commit, digest = build_testsuite(testsuite, raw_rows, model_rows: legacy)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        summary = run_replay(testsuite, pin)
        expect(summary.values_at("mismatched_rows", "renamed_typed_model_rows")).to eq([0, 1])
      end
    end

    it "fails and names the boundary when a typed model differs from the expected value" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        rows = model_rows.dup
        rows[0] = rows[0].merge("expected" => Marshal.load(Marshal.dump(model_rows[1]["expected"])))
        commit, digest = build_testsuite(testsuite, raw_rows, model_rows: rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        report = File.join(dir, "report.json")
        expect { run_replay(testsuite, pin, report: report) }
          .to raise_error(described_class::Error, /1 rows differ: letter\.model/)
        failures = JSON.parse(File.read(report)).fetch("failures")
        expect(failures.map { |f| [f["id"], f["boundary"]] }).to eq([["letter.model", "typed-model"]])
      end
    end

    it "fails when a row id is repeated across the replayed payloads" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        rows = model_rows.map { |r| r.merge("id" => r["id"].sub(".model", ".raw")) }
        commit, digest = build_testsuite(testsuite, raw_rows, model_rows: rows)
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        expect { run_replay(testsuite, pin) }
          .to raise_error(described_class::Error, /row ids repeated across replayed payloads: letter\.raw, refused\.raw/)
      end
    end

    it "fails when the generation has no raw-tree rows" do
      Dir.mktmpdir do |dir|
        testsuite = File.join(dir, "testsuite")
        commit, digest = build_testsuite(testsuite, [])
        pin = write_pin(File.join(dir, "pin.yml"), commit: commit, snapshot_digest: digest)
        expect { run_replay(testsuite, pin) }.to raise_error(described_class::Error, /has no raw-tree rows/)
      end
    end
  end
end
