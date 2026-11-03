# frozen_string_literal: true

require "digest"
require "open3"
require "tmpdir"
require "yaml"
require_relative "../../scripts/stage_cases"

# scripts/stage_cases.rb writes the raw-tree rows of a plurimath-testsuite
# unicode stage generation. These examples run it against a small testsuite
# checkout built in a temporary git repository.
RSpec.describe StageCases do
  def git(dir, *args)
    out, err, status = Open3.capture3("git", "-C", dir, *args)
    raise "git #{args.join(' ')}: #{err}" unless status.success?

    out
  end

  def legacy_payload(group, cases)
    "# legacy bytes, kept exactly\n" + YAML.dump(
      "schema" => "plurimath-corpus/unicode/1", "group" => group, "description" => "d",
      "input_format" => "unicode", "targets" => ["latex"],
      "cases" => cases.map { |id, input| { "id" => id, "input" => input, "expected" => { "latex" => "x" } } },
    )
  end

  # A git checkout holding generations/unicode.yaml and generation 1 with
  # the given payloads ({ "payloads/x.yaml" => bytes }).
  def testsuite(dir, payloads)
    gen = File.join(dir, "stages", "unicode", "generations", "000001")
    FileUtils.mkdir_p(File.join(gen, "payloads"))
    payloads.each { |path, bytes| File.binwrite(File.join(gen, path), bytes) }
    provenance = "---\n" + YAML.dump(
      "schema" => "plurimath-stage/provenance/1", "language" => "unicode", "generation" => 1,
      "producers" => { "legacy-oracle" => { "kind" => "legacy-oracle" } },
      "payloads" => payloads.sort_by { |p, _| p.b }.map do |path, bytes|
        { "path" => path, "bytes" => bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(bytes),
          "producer" => "legacy-oracle", "source" => { "relation" => "copy", "file" => nil },
          "rows" => YAML.safe_load(bytes)["cases"].map { |c| c["id"] } }
      end,
    ).delete_prefix("---\n")
    File.binwrite(File.join(gen, "provenance.yaml"), provenance)
    files = payloads.merge("provenance.yaml" => provenance)
    FileUtils.mkdir_p(File.join(dir, "generations"))
    File.write(File.join(dir, "generations", "unicode.yaml"), <<~YAML)
      # ledger
      ---
      schema: plurimath-stage/ledger/1
      language: unicode
      layout: 1
      entries:
      - generation: 1
        path: stages/unicode/generations/000001
        snapshot_digest: #{StageCases.snapshot_digest(files)}
        payloads: #{payloads.size}
        rows: 1
        producer_kinds:
        - legacy-oracle
        change: initial
        rationale: seed
    YAML
    git(dir, "init", "-q")
    git(dir, "add", ".")
    git(dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "seed")
    dir
  end

  let(:producer) { { "kind" => "stage-gem", "commit" => "0" * 40 } }

  describe StageCases::Canonical do
    it "tags every value kind the raw tree can hold" do
      expect(described_class.dump(nil)).to eq("nil" => true)
      expect(described_class.dump(false)).to eq("bool" => false)
      expect(described_class.dump(12)).to eq("int" => "12")
      expect(described_class.dump("x")).to eq("str" => "x")
      expect(described_class.dump(:x)).to eq("sym" => "x")
      expect(described_class.dump([])).to eq("array" => [])
      expect(described_class.dump("")).to eq("str" => "")
      expect(described_class.dump({ b: [1], a: nil })).to eq(
        "hash" => [[{ "sym" => "b" }, { "array" => [{ "int" => "1" }] }], [{ "sym" => "a" }, { "nil" => true }]],
      )
    end

    it "keeps slice text with byte and character offsets" do
      tree = Unicodemath::RawParser.parse("a/b", engine: :ruby).tree
      slices = []
      walk = lambda do |node|
        case node
        when Hash then node.each_value { |v| walk.(v) }
        when Array then node.each { |v| walk.(v) }
        else slices << node
        end
      end
      walk.(tree)
      expect(slices).not_to be_empty
      slices.each do |s|
        expect(described_class.dump(s)).to eq("slice" => s.to_s, "byte_offset" => s.bytepos,
                                              "char_offset" => s.charpos)
      end
    end

    it "refuses strings that are not valid UTF-8 and unknown objects" do
      expect { described_class.dump("\xFF".b) }.to raise_error(StageCases::Failure, /UTF-8/)
      expect { described_class.dump(Object.new) }.to raise_error(StageCases::Failure, /Object/)
    end
  end

  describe StageCases::Outcome do
    it "records the preprocessing and the tree of a parse on both engines" do
      outcome = described_class.agreed("t", "a/b")
      expect(outcome.keys).to eq(%w[preprocessed tree])
      expect(outcome["preprocessed"]).to eq("str" => "a/b")
      expect(outcome["tree"]).to eq(StageCases::Canonical.dump(Unicodemath::RawParser.parse("a/b", engine: :ruby).tree))
    end

    it "records a refusal with its category and byte offset" do
      expect(described_class.agreed("t", "(a")).to eq("refusal" => { "category" => "parse_error", "byte_offset" => 2 })
      expect(described_class.agreed("t", "α)")).to eq("refusal" => { "category" => "parse_error", "byte_offset" => 7 })
    end

    it "fails when the engines disagree" do
      allow(described_class).to receive(:of).and_call_original
      allow(described_class).to receive(:of).with("a/b", :native).and_return("refusal" => { "category" => "parse_error", "byte_offset" => 0 })
      expect { described_class.agreed("t", "a/b") }.to raise_error(StageCases::Failure, /engines disagree/)
    end

    it "does not record a nesting limit as a refusal" do
      allow(Unicodemath::RawParser).to receive(:parse)
        .and_raise(Unicodemath::NestingTooDeep.new("deep", input: "x", byte_offset: nil, char_offset: nil))
      expect { described_class.of("x", :ruby) }.to raise_error(StageCases::Failure, /nesting/)
    end
  end

  describe StageCases::Source do
    it "fails when a file no longer matches the ledger digest" do
      Dir.mktmpdir do |dir|
        testsuite(dir, "payloads/fences.yaml" => legacy_payload("fences", [["f-1", "(a)"]]))
        path = File.join(dir, "stages/unicode/generations/000001/payloads/fences.yaml")
        File.write(path, File.read(path).sub("(a)", "[a]"))
        git(dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qam", "tamper")
        expect { described_class.new(dir) }.to raise_error(StageCases::Failure, /snapshot digest/)
      end
    end

    it "fails on uncommitted stage files" do
      Dir.mktmpdir do |dir|
        testsuite(dir, "payloads/fences.yaml" => legacy_payload("fences", [["f-1", "(a)"]]))
        File.write(File.join(dir, "stages/unicode/generations/000001/payloads/extra.yaml"), "x")
        expect { described_class.new(dir) }.to raise_error(StageCases::Failure, /uncommitted/)
      end
    end
  end

  describe StageCases::Generator do
    it "copies the source generation and adds one raw-tree payload per payload" do
      Dir.mktmpdir do |dir|
        fences = legacy_payload("fences", [["f-1", "(a)"], ["f-2", "a)"]])
        testsuite(dir, "payloads/fences.yaml" => fences)
        source = StageCases::Source.new(dir)
        generator = described_class.new(source, producer)
        files = generator.files
        gen = "stages/unicode/generations/000002"

        expect(files.keys.sort).to eq(["#{gen}/payloads/fences.yaml", "#{gen}/payloads/raw-fences.yaml",
                                       "#{gen}/provenance.yaml", "generations/unicode.yaml"].sort)
        expect(files["#{gen}/payloads/fences.yaml"]).to eq(fences)

        raw = YAML.safe_load(files["#{gen}/payloads/raw-fences.yaml"])
        expect(raw.slice("schema", "group", "boundary")).to eq(
          "schema" => "plurimath-stage/unicode/cases/1", "group" => "raw-fences", "boundary" => "raw-tree",
        )
        expect(raw["cases"].map { |c| c["id"] }).to eq(%w[f-1.raw f-2.raw])
        expect(raw["cases"].map { |c| c["input"] }).to eq([{ "str" => "(a)" }, { "str" => "a)" }])
        expect(raw["cases"][1]["expected"]).to eq("refusal" => { "category" => "parse_error", "byte_offset" => 1 })

        provenance = YAML.safe_load(files["#{gen}/provenance.yaml"])
        expect(provenance["generation"]).to eq(2)
        expect(provenance["producers"].keys).to eq(%w[legacy-oracle unicodemath-raw])
        expect(provenance["payloads"].map { |p| p["path"] }).to eq(%w[payloads/fences.yaml payloads/raw-fences.yaml])
        copy = provenance["payloads"][0]["source"]
        expect(copy["relation"]).to eq("copy")
        expect(copy["file"]).to include("commit" => git(dir, "rev-parse", "HEAD").strip,
                                        "path" => "stages/unicode/generations/000001/payloads/fences.yaml",
                                        "sha256" => Digest::SHA256.hexdigest(fences))
        expect(provenance["payloads"][1]["sha256"]).to eq(Digest::SHA256.hexdigest(files["#{gen}/payloads/raw-fences.yaml"]))

        ledger = files["generations/unicode.yaml"]
        expect(ledger).to start_with(File.read(File.join(dir, "generations/unicode.yaml")))
        entry = YAML.safe_load(ledger)["entries"].last
        generation = files.select { |p, _| p.start_with?("#{gen}/") }.transform_keys { |p| p.delete_prefix("#{gen}/") }
        expect(entry).to include("generation" => 2, "path" => gen, "payloads" => 2, "rows" => 4,
                                 "producer_kinds" => %w[legacy-oracle stage-gem], "change" => "extend",
                                 "snapshot_digest" => StageCases.snapshot_digest(generation))
      end
    end

    it "is deterministic" do
      Dir.mktmpdir do |dir|
        testsuite(dir, "payloads/fences.yaml" => legacy_payload("fences", [["f-1", "(a)"]]))
        source = StageCases::Source.new(dir)
        expect(described_class.new(source, producer).files).to eq(described_class.new(source, producer).files)
      end
    end
  end
end
