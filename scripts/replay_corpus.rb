# frozen_string_literal: true

# Replays UnicodeMath corpus rows through the public parser.
#
# Usage:
#   bundle exec ruby scripts/replay_corpus.rb --testsuite PATH [--pin FILE] \
#     [--language unicode] [--generation N] [--report FILE]
#   bundle exec ruby scripts/replay_corpus.rb --staging DIR [--boundary raw,model] [--write]
#   bundle exec ruby scripts/replay_corpus.rb --inventory FILE --rows DIR
#
# --testsuite PATH: the plurimath-testsuite stage generation pinned in
#   spec/fixtures/testsuite-pin.yml (or --pin FILE). Before any row runs it
#   checks the pin: its schema and fields, that the checkout is at the pinned
#   commit, that the ledger has the pinned generation with the pinned
#   snapshot digest, that the digest recomputed from the generation's files
#   is the same and that every payload has its recorded checksum.
#   --language and --generation, when given, must equal the pin's. Then every
#   row of every raw-tree payload is parsed with Umath::RawParser.parse
#   on the Ruby and the native engine, as scripts/stage_cases.rb writes it,
#   and each outcome must equal the row's expected value. Rows whose source
#   id is listed in spec/parser/fixtures/oracle/native-divergences.yml must
#   instead still differ on the native engine. Any pin failure, any
#   difference or a generation with no raw-tree rows exits 1. Runs both
#   engines whatever UNICODEMATH_ENGINE says.
#
# --staging DIR: every DIR/**/*.yml payload (schema umath-model-corpus/1,
#   rows of id, input, optional decimal, and expected outcome). Per row and
#   boundary:
#     raw    the typed model holds exactly the grammar's bound tree
#            (scripts/model_tree.rb): construction lost nothing and every
#            attribute holds its declared type;
#     model  the parse outcome equals the row's expectation: the document's
#            hash form (Document#to_hash), or a ParseError with its offsets
#            into the input.
#   --write rewrites the expectations from the current gem (producer
#   stage-gem) instead of comparing.
# --inventory FILE --rows DIR: oracle rows captured by scripts/oracle/capture.rb.
#   A row the legacy grammar accepted must give, after removing the
#   normalization's wrappers (scripts/unwrap.rb), the legacy raw tree in
#   canonical form (raw parity), and a document that passes the raw check
#   above (model); a row it refused must raise ParseError; input without a
#   formula part (legacy NoMethodError) must give an empty document.
#   --report FILE also writes the counts and, per capture, the kinds of
#   value (hash, array, string, nil) the accepted rows' bound trees held.
#
# Runs on the Ruby engine (UNICODEMATH_ENGINE=native to change). Prints one
# line per failure and a count summary; exits 1 on any failure, missing or
# duplicate row id.

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "yaml"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "umath"
require_relative "oracle/canonical"
require_relative "unwrap"
require_relative "model_tree"
require_relative "stage_cases"

SCHEMA = "umath-model-corpus/1"
ENGINE = (ENV["UNICODEMATH_ENGINE"] || "ruby").to_sym
# Rows where the Parsanol native engine gives another tree than legacy, on
# this grammar and on the grammar before the shape normalization; they must
# still differ (see the file).
NATIVE_DIVERGENCES = YAML.safe_load_file(File.expand_path("../spec/parser/fixtures/oracle/native-divergences.yml", __dir__))
                         .fetch("ids").freeze
LOCALE_DECIMALS = { nil => ".", "en" => ".", "fr" => ",", "de" => ",", "ar" => "٫", "fa" => "٫" }.freeze

# The --testsuite mode: replays the plurimath-testsuite stage generation
# pinned in spec/fixtures/testsuite-pin.yml.
module UmathReplayCorpus
  class Error < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  DEFAULT_PIN = File.join(ROOT, "spec", "fixtures", "testsuite-pin.yml")
  PIN_SCHEMA = "plurimath-stage/pin/1"
  PIN_KEYS = %w[schema repository commit language generation snapshot_digest].freeze
  REPOSITORY = StageCases::TESTSUITE_REPOSITORY
  LANGUAGE = StageCases::LANGUAGE
  ENGINES = %i[ruby native].freeze
  OPTION_KEYS = %w[decimal].freeze

  Pin = Struct.new(:commit, :language, :generation, :digest, keyword_init: true)

  module_function

  # The pin at +path+, its fields checked against plurimath-stage/pin/1.
  def load_pin(path)
    doc = YAML.safe_load_file(path, aliases: false)
    raise Error, "#{path}: not a mapping" unless doc.is_a?(Hash)

    missing = PIN_KEYS - doc.keys
    extra = doc.keys - PIN_KEYS
    raise Error, "#{path}: missing #{missing.join(', ')}" unless missing.empty?
    raise Error, "#{path}: unknown keys #{extra.join(', ')}" unless extra.empty?
    raise Error, "#{path}: schema is not #{PIN_SCHEMA}" unless doc["schema"] == PIN_SCHEMA
    raise Error, "#{path}: repository is not #{REPOSITORY}" unless doc["repository"] == REPOSITORY
    raise Error, "#{path}: commit is not a 40-hex commit" unless doc["commit"].is_a?(String) && doc["commit"].match?(/\A\h{40}\z/)
    raise Error, "#{path}: language #{doc['language'].inspect} is not #{LANGUAGE}" unless doc["language"] == LANGUAGE
    raise Error, "#{path}: generation is not a positive integer" unless doc["generation"].is_a?(Integer) && doc["generation"] >= 1
    unless doc["snapshot_digest"].is_a?(String) && doc["snapshot_digest"].match?(/\Asha256:\h{64}\z/)
      raise Error, "#{path}: snapshot_digest is not sha256:<64 hex>"
    end

    Pin.new(commit: doc["commit"], language: doc["language"], generation: doc["generation"],
            digest: doc["snapshot_digest"])
  rescue Psych::Exception, Errno::ENOENT => e
    raise Error, "#{path}: #{e.message}"
  end

  def git(dir, *args)
    out, err, status = Open3.capture3("git", "-C", dir, *args)
    raise Error, "git #{args.join(' ')} in #{dir}: #{err.strip}" unless status.success?

    out.strip
  end

  # [generation dir, { relative path => bytes }] once the checkout matches
  # +pin+: HEAD is the pinned commit, the ledger entry and the digest
  # recomputed from the generation's files are the pinned digest, and every
  # payload has the checksum its provenance records.
  def verify(testsuite, pin)
    head = git(testsuite, "rev-parse", "HEAD")
    raise Error, "pin commit #{pin.commit} is not the checkout's HEAD #{head}" unless head == pin.commit

    dirty = git(testsuite, "status", "--porcelain", "--", "stages", "generations")
    raise Error, "testsuite checkout has uncommitted stage files:\n#{dirty}" unless dirty.empty?

    ledger_path = File.join(testsuite, "generations", "#{pin.language}.yaml")
    raise Error, "#{ledger_path} does not exist" unless File.file?(ledger_path)

    ledger = StageCases.committed_file(testsuite, "generations/#{pin.language}.yaml", error: Error)
    entry = YAML.safe_load(ledger, aliases: false).fetch("entries").find { |e| e["generation"] == pin.generation }
    raise Error, "generations/#{pin.language}.yaml has no generation #{pin.generation}" unless entry
    if entry["snapshot_digest"] != pin.digest
      raise Error, "ledger digest #{entry['snapshot_digest']} of generation #{pin.generation} " \
                   "is not the expected #{pin.digest}"
    end

    # The committed bytes: a core.autocrlf checkout has CRLF working files.
    files = StageCases.committed_files(testsuite, entry.fetch("path"), error: Error)
    digest = StageCases.snapshot_digest(files)
    raise Error, "#{entry['path']}: digest #{digest} does not match the ledger's #{pin.digest}" unless digest == pin.digest

    provenance = YAML.safe_load(files.fetch("provenance.yaml") { raise Error, "#{entry['path']} has no provenance.yaml" })
    listed = provenance.fetch("payloads")
    if listed.map { |p| p["path"] }.sort != (files.keys - ["provenance.yaml"]).sort
      raise Error, "#{entry['path']}: provenance does not list exactly the payload files"
    end
    listed.each do |p|
      actual = Digest::SHA256.hexdigest(files.fetch(p["path"]))
      raise Error, "#{entry['path']}/#{p['path']}: sha256 #{actual} is not #{p['sha256']}" unless actual == p["sha256"]
    end
    [entry["path"], listed.to_h { |p| [p["path"], files.fetch(p["path"])] }]
  rescue KeyError, Psych::Exception => e
    raise Error, e.message
  end

  # A canonical {str:} value as a Ruby string (the unicode rows carry no
  # encoding labels).
  def decode(value, where)
    raise Error, "#{where}: input is not a canonical string" unless value.is_a?(Hash) && value.keys == ["str"] && value["str"].is_a?(String)

    value["str"]
  end

  def check_options(row, where)
    opts = row.fetch("options", {})
    unknown = opts.keys - OPTION_KEYS
    raise Error, "#{where}: unsupported options #{unknown.join(', ')}" unless unknown.empty?
    if opts.fetch("decimal", StageCases::DECIMAL) != StageCases::DECIMAL
      raise Error, "#{where}: decimal #{opts['decimal'].inspect} is not supported by the replay"
    end
  end

  # Every raw-tree row of the generation, with its payload path.
  def raw_rows(payloads)
    payloads.flat_map do |rel, bytes|
      doc = YAML.safe_load(bytes, aliases: false)
      next [] unless doc["boundary"] == "raw-tree"

      doc.fetch("cases").map { |row| [rel, row] }
    end
  end

  def outcome(input, engine)
    StageCases::Outcome.of(input, engine)
  rescue StageCases::Failure => e
    raise Error, e.message
  end

  # The source id of a raw-tree row (the row id without its .raw suffix),
  # which spec/parser/fixtures/oracle/native-divergences.yml names.
  def source_id(id)
    id.delete_suffix(StageCases::ROW_SUFFIXES.fetch("raw-tree"))
  end

  # [failures, rows replayed on native as listed divergences]
  def replay(rows, divergences)
    diverged = 0
    failures = rows.filter_map do |rel, row|
      where = "#{rel} #{row['id']}"
      input = decode(row.fetch("input"), where)
      check_options(row, where)
      expected = row.fetch("expected")
      wrong = ENGINES.filter_map do |engine|
        actual = outcome(input, engine)
        if engine == :native && divergences.include?(source_id(row["id"]))
          next { "engine" => "native", "actual" => actual, "note" => "listed native divergence now matches" } if actual == expected

          diverged += 1
          next
        end
        { "engine" => engine.to_s, "actual" => actual } unless actual == expected
      end
      { "id" => row["id"], "payload" => rel, "expected" => expected, "mismatches" => wrong } unless wrong.empty?
    end
    [failures, diverged]
  end

  def run(testsuite:, pin: DEFAULT_PIN, language: nil, generation: nil, report: nil, divergences: NATIVE_DIVERGENCES,
          log: $stderr)
    pinned = load_pin(pin)
    raise Error, "--language #{language} is not the pinned #{pinned.language}" if language && language != pinned.language
    if generation && generation != pinned.generation
      raise Error, "--generation #{generation} is not the pinned #{pinned.generation}"
    end
    raise Error, "the native engine is not available" unless Umath::Engine.native_available?

    _dir, payloads = verify(File.expand_path(testsuite), pinned)
    rows = raw_rows(payloads)
    raise Error, "#{pinned.language} generation #{pinned.generation} has no raw-tree rows" if rows.empty?

    log.puts "pin ok: #{pinned.language} generation #{pinned.generation} at #{pinned.commit}, #{pinned.digest}"
    failures, diverged = replay(rows, divergences)
    summary = { "commit" => pinned.commit, "language" => pinned.language, "generation" => pinned.generation,
                "snapshot_digest" => pinned.digest, "engines" => ENGINES.map(&:to_s),
                "raw_tree_payloads" => rows.map(&:first).uniq.size, "raw_tree_rows" => rows.size,
                "native_divergences_listed" => divergences.size, "native_divergences_replayed" => diverged,
                "mismatched_rows" => failures.size, "failures" => failures }
    if report
      FileUtils.mkdir_p(File.dirname(report))
      File.binwrite(report, "#{JSON.pretty_generate(summary, max_nesting: false)}\n")
    end
    log.puts "#{rows.size} raw-tree rows from #{summary['raw_tree_payloads']} payloads on " \
             "#{ENGINES.join(' and ')} (#{diverged} listed native divergences): #{failures.size} differ"
    raise Error, "#{failures.size} rows differ: #{failures.map { |f| f['id'] }.join(', ')}" unless failures.empty?

    summary
  end

  def main(argv)
    options = {}
    OptionParser.new do |o|
      o.banner = "usage: scripts/replay_corpus.rb --testsuite PATH [--pin FILE] [--language NAME] " \
                 "[--generation N] [--report FILE]"
      o.on("--testsuite PATH") { |v| options[:testsuite] = v }
      o.on("--pin FILE") { |v| options[:pin] = v }
      o.on("--language NAME") { |v| options[:language] = v }
      o.on("--generation N", Integer) { |v| options[:generation] = v }
      o.on("--report FILE") { |v| options[:report] = v }
    end.parse!(argv)
    raise OptionParser::MissingArgument, "--testsuite" unless options[:testsuite]
    raise OptionParser::InvalidOption, argv.join(" ") unless argv.empty?

    run(**options)
    0
  rescue OptionParser::ParseError => e
    warn e.message
    2
  rescue Error => e
    warn "replay_corpus: #{e.message}"
    1
  end
end

FAILURES = []
COUNTS = Hash.new(0)
KINDS = Hash.new { |h, k| h[k] = Hash.new(0) }

# Tallies the value kind of every capture in +tree+ (bound plain data).
def survey(tree)
  stack = [tree]
  until stack.empty?
    node = stack.pop
    case node
    when Hash
      node.each do |key, value|
        kind = case value
               when Hash then "hash"
               when Array then "array"
               when nil then "nil"
               else "string"
               end
        KINDS[key][kind] += 1
        stack << value
      end
    when Array then stack.concat(node)
    end
  end
end

def fail_row(id, message)
  FAILURES << id
  puts "FAIL #{id}: #{message}"
end

def outcome(input, decimal)
  { "model" => Umath.parse(input, decimal: decimal, engine: ENGINE).to_hash }
rescue Umath::ParseError => e
  { "refusal" => { "error" => e.class.name.split("::").last, "char_offset" => e.char_offset, "byte_offset" => e.byte_offset } }
end

# One parse: the raw result and the document built from it, as
# Umath.parse builds it.
def parse_both(input, decimal)
  raw = Umath::RawParser.parse(input, decimal: decimal, engine: ENGINE)
  document = Umath.parse(input, decimal: decimal, engine: ENGINE)
  [raw, document]
end

# The raw check: nil when the model holds exactly the bound tree.
def model_problem(raw, document)
  return document.expression.nil? ? nil : "formula-less input built an expression" if raw.text.nil?

  survey({ "(root)" => raw.model_data })
  UmathModelTree.lossless?(document.expression, raw.model_data) ? nil : "model does not hold the bound tree"
rescue TypeError => e
  e.message
end

def replay_staging(dir, boundaries, write)
  files = Dir[File.join(dir, "**", "*.yml")].sort
  abort "no payloads under #{dir}" if files.empty?
  seen = {}
  files.each do |file|
    doc = YAML.safe_load_file(file)
    abort "#{file}: schema #{doc['schema'].inspect}, not #{SCHEMA}" unless doc["schema"] == SCHEMA
    rows = doc.fetch("rows")
    abort "#{file}: no rows" if rows.empty?
    rows.each do |row|
      id = row.fetch("id")
      fail_row(id, "duplicate id (also in #{seen[id]})") if seen.key?(id)
      seen[id] = file
      decimal = row.fetch("decimal", ".")
      COUNTS["rows"] += 1
      if write
        row["expected"] = outcome(row.fetch("input"), decimal)
        next
      end
      if boundaries.include?("raw")
        problem = begin
          model_problem(*parse_both(row.fetch("input"), decimal))
        rescue Umath::ParseError
          nil
        end
        problem ? fail_row(id, "raw: #{problem}") : COUNTS["raw ok"] += 1
      end
      next unless boundaries.include?("model")

      actual = outcome(row.fetch("input"), decimal)
      if actual == row.fetch("expected")
        COUNTS["model ok"] += 1
      else
        fail_row(id, "model: expected #{JSON.generate(row['expected'])[0, 300]}, got #{JSON.generate(actual)[0, 300]}")
      end
    end
    next unless write

    header = File.readlines(file).take_while { |l| l.start_with?("#") }.join
    File.binwrite(file, header + YAML.dump(doc).delete_prefix("---\n"))
  end
end

def replay_oracle(inventory, rows_dir)
  doc = YAML.safe_load_file(inventory)
  ids = doc.fetch("rows").map { |r| r.fetch("id") }
  abort "duplicate ids in #{inventory}" unless ids.uniq.size == ids.size
  abort "empty inventory #{inventory}" if ids.empty?
  doc.fetch("rows").each do |row|
    id = row.fetch("id")
    COUNTS["rows"] += 1
    path = File.join(rows_dir, "#{id}.json")
    next fail_row(id, "no oracle row #{path}") unless File.file?(path)

    captured = JSON.parse(File.read(path), max_nesting: false)
    input = row["input_base64"] ? row["input_base64"].unpack1("m0").force_encoding(Encoding::UTF_8) : row.fetch("input")
    decimal = LOCALE_DECIMALS.fetch(row.dig("options", "locale"))
    unless input.valid_encoding?
      # The stage profile: invalid UTF-8 is an ArgumentError, whatever the
      # legacy facade did with it.
      begin
        Umath.parse(input, decimal: decimal, engine: ENGINE)
        fail_row(id, "invalid UTF-8 accepted")
      rescue ArgumentError
        COUNTS["invalid input rejected"] += 1
      end
      next
    end
    case captured.fetch("outcome")
    when "succeeded"
      begin
        raw, document = parse_both(input, decimal)
        legacy = captured.dig("result", "boundaries", "raw", "tree")
        if legacy.nil?
          fail_row(id, "oracle row has no raw tree")
        else
          same = UmathOracle::Canonical.dump(UmathUnwrap.call(raw.tree)) == legacy
          if ENGINE == :native && NATIVE_DIVERGENCES.include?(id)
            same ? fail_row(id, "listed native divergence now matches; remove it from the list") : COUNTS["known native divergence"] += 1
          elsif same
            COUNTS["raw parity ok"] += 1
          else
            fail_row(id, "unwrapped raw tree differs from the legacy tree")
          end
        end
        problem = model_problem(raw, document)
        problem ? fail_row(id, "model: #{problem}") : COUNTS["model ok"] += 1
      rescue Umath::Error, ArgumentError => e
        fail_row(id, "legacy accepted, gem raised #{e.class}: #{e.message[0, 200]}")
      end
    when "refused"
      begin
        Umath.parse(input, decimal: decimal, engine: ENGINE)
        fail_row(id, "legacy refused, gem accepted")
      rescue Umath::ParseError
        COUNTS["refused ok"] += 1
      end
    else
      # Errored rows. Legacy NoMethodError in preprocessing is input without
      # a formula part: the gem returns an empty document. Anything else
      # (a stack overflow) must be refused, never returned as a model.
      error = captured.dig("result", "boundaries", "preprocess", "error", "class")
      begin
        document = Umath.parse(input, decimal: decimal, engine: ENGINE)
        if error == "NoMethodError" && document.expression.nil?
          COUNTS["empty document ok"] += 1
        else
          fail_row(id, "legacy #{captured['outcome']} (#{error}), gem returned #{document.to_hash.inspect[0, 120]}")
        end
      rescue Umath::ParseError, ArgumentError
        error == "NoMethodError" ? fail_row(id, "formula-less input refused") : COUNTS["errored refused"] += 1
      end
    end
  end
end

def legacy_main(argv)
  options = { boundaries: %w[raw model] }
  OptionParser.new do |o|
    o.on("--staging DIR") { |v| options[:staging] = v }
    o.on("--boundary LIST") { |v| options[:boundaries] = v.split(",") }
    o.on("--write") { options[:write] = true }
    o.on("--inventory FILE") { |v| options[:inventory] = v }
    o.on("--rows DIR") { |v| options[:rows] = v }
    o.on("--report FILE") { |v| options[:report] = v }
  end.parse!(argv)
  unknown = options[:boundaries] - %w[raw model]
  abort "unknown boundary #{unknown.join(', ')}" unless unknown.empty?
  abort "use --staging DIR or --inventory FILE --rows DIR" unless options[:staging] || (options[:inventory] && options[:rows])

  if options[:staging]
    replay_staging(options[:staging], options[:boundaries], options[:write])
  else
    replay_oracle(options[:inventory], options[:rows])
  end
  if options[:report]
    File.binwrite(options[:report], JSON.pretty_generate("counts" => COUNTS, "failures" => FAILURES,
                                                      "capture_kinds" => KINDS.sort.to_h))
  end
  puts "#{COUNTS.map { |k, v| "#{k}=#{v}" }.join(' ')} failures=#{FAILURES.size} engine=#{ENGINE}"
  FAILURES.empty?
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--testsuite") || ARGV.any? { |a| a.start_with?("--testsuite=") }
    exit UmathReplayCorpus.main(ARGV)
  else
    exit(legacy_main(ARGV) ? 0 : 1)
  end
end
