# frozen_string_literal: true

# Replays UnicodeMath corpus rows through the public parser.
#
# Usage:
#   bundle exec ruby scripts/replay_corpus.rb --staging DIR [--boundary raw,model] [--write]
#   bundle exec ruby scripts/replay_corpus.rb --inventory FILE --rows DIR
#
# --staging DIR: every DIR/**/*.yml payload (schema unicodemath-model-corpus/1,
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

require "json"
require "optparse"
require "yaml"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "unicodemath"
require_relative "oracle/canonical"
require_relative "unwrap"
require_relative "model_tree"

SCHEMA = "unicodemath-model-corpus/1"
ENGINE = (ENV["UNICODEMATH_ENGINE"] || "ruby").to_sym
LOCALE_DECIMALS = { nil => ".", "en" => ".", "fr" => ",", "de" => ",", "ar" => "٫", "fa" => "٫" }.freeze

options = { boundaries: %w[raw model] }
OptionParser.new do |o|
  o.on("--staging DIR") { |v| options[:staging] = v }
  o.on("--boundary LIST") { |v| options[:boundaries] = v.split(",") }
  o.on("--write") { options[:write] = true }
  o.on("--inventory FILE") { |v| options[:inventory] = v }
  o.on("--rows DIR") { |v| options[:rows] = v }
  o.on("--report FILE") { |v| options[:report] = v }
end.parse!
unknown = options[:boundaries] - %w[raw model]
abort "unknown boundary #{unknown.join(', ')}" unless unknown.empty?
abort "use --staging DIR or --inventory FILE --rows DIR" unless options[:staging] || (options[:inventory] && options[:rows])

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
  { "model" => Unicodemath.parse(input, decimal: decimal, engine: ENGINE).to_hash }
rescue Unicodemath::ParseError => e
  { "refusal" => { "error" => e.class.name.split("::").last, "char_offset" => e.char_offset, "byte_offset" => e.byte_offset } }
end

# One parse: the raw result and the document built from it, as
# Unicodemath.parse builds it.
def parse_both(input, decimal)
  raw = Unicodemath::RawParser.parse(input, decimal: decimal, engine: ENGINE)
  document = Unicodemath.parse(input, decimal: decimal, engine: ENGINE)
  [raw, document]
end

# The raw check: nil when the model holds exactly the bound tree.
def model_problem(raw, document)
  return document.expression.nil? ? nil : "formula-less input built an expression" if raw.text.nil?

  survey({ "(root)" => raw.model_data })
  UnicodemathModelTree.lossless?(document.expression, raw.model_data) ? nil : "model does not hold the bound tree"
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
        rescue Unicodemath::ParseError
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
    File.write(file, header + YAML.dump(doc).delete_prefix("---\n"))
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
        Unicodemath.parse(input, decimal: decimal, engine: ENGINE)
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
        elsif UnicodemathOracle::Canonical.dump(UnicodemathUnwrap.call(raw.tree)) == legacy
          COUNTS["raw parity ok"] += 1
        else
          fail_row(id, "unwrapped raw tree differs from the legacy tree")
        end
        problem = model_problem(raw, document)
        problem ? fail_row(id, "model: #{problem}") : COUNTS["model ok"] += 1
      rescue Unicodemath::Error, ArgumentError => e
        fail_row(id, "legacy accepted, gem raised #{e.class}: #{e.message[0, 200]}")
      end
    when "refused"
      begin
        Unicodemath.parse(input, decimal: decimal, engine: ENGINE)
        fail_row(id, "legacy refused, gem accepted")
      rescue Unicodemath::ParseError
        COUNTS["refused ok"] += 1
      end
    else
      # Errored rows. Legacy NoMethodError in preprocessing is input without
      # a formula part: the gem returns an empty document. Anything else
      # (a stack overflow) must be refused, never returned as a model.
      error = captured.dig("result", "boundaries", "preprocess", "error", "class")
      begin
        document = Unicodemath.parse(input, decimal: decimal, engine: ENGINE)
        if error == "NoMethodError" && document.expression.nil?
          COUNTS["empty document ok"] += 1
        else
          fail_row(id, "legacy #{captured['outcome']} (#{error}), gem returned #{document.to_hash.inspect[0, 120]}")
        end
      rescue Unicodemath::ParseError, ArgumentError
        error == "NoMethodError" ? fail_row(id, "formula-less input refused") : COUNTS["errored refused"] += 1
      end
    end
  end
end

if options[:staging]
  replay_staging(options[:staging], options[:boundaries], options[:write])
else
  replay_oracle(options[:inventory], options[:rows])
end
if options[:report]
  File.write(options[:report], JSON.pretty_generate("counts" => COUNTS, "failures" => FAILURES,
                                                    "capture_kinds" => KINDS.sort.to_h))
end
puts "#{COUNTS.map { |k, v| "#{k}=#{v}" }.join(' ')} failures=#{FAILURES.size} engine=#{ENGINE}"
exit(FAILURES.empty? ? 0 : 1)
