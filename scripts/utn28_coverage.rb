# frozen_string_literal: true

# States which UTN 28 v3.2 constructs the corpus shows umath reading.
#
# Usage:
#   bundle exec ruby scripts/utn28_coverage.rb [--check] [--testsuite PATH] [--pin FILE]
#
# The mapping docs/utn28-coverage.yml ties each construct of UTN 28 to row
# ids of two corpora:
#
# * corpora/model/representative.yml, whose rows must give the expected
#   outcome of Umath.parse in the form scripts/replay_corpus.rb --staging
#   compares (Document#to_hash, or a ParseError with its offsets);
# * the model-* payloads of the plurimath-testsuite generation pinned in
#   spec/fixtures/testsuite-pin.yml, checked out at PATH (default
#   tmp/testsuite). The pin is verified first, as scripts/replay_corpus.rb
#   --testsuite verifies it. Each row must give its expected typed model or
#   refusal in the form scripts/stage_cases.rb writes. The rows were written
#   before the gem was renamed, so their class names start with
#   Unicodemath::Model:: where the gem now has Umath::Model::.
#
# Every listed row is parsed on the Ruby engine. A construct is covered when
# its rows parse to their expected models, refused when its rows are refused
# as expected and it has no other rows, and untested when no row is listed.
# A row whose outcome differs from its expectation, a mapped id that names no
# row, or a corpus row that is neither mapped nor listed as unmapped is an
# error (exit 2).
#
# Without --check the script rewrites the regions between
# "// BEGIN GENERATED <name>" and "// END GENERATED <name>" in
# docs/unicodemath.adoc. With --check it writes nothing and exits 1 when the
# file differs from what it would write. The output depends only on the
# mapping and the corpora, never on time or local paths.

require "optparse"
require "yaml"
require_relative "replay_corpus"

# The mapping, the row checks and the generated regions.
module Utn28Coverage
  class Error < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  MAPPING = File.join(ROOT, "docs", "utn28-coverage.yml")
  DOC = File.join(ROOT, "docs", "unicodemath.adoc")
  CORPUS = File.join(ROOT, "corpora", "model", "representative.yml")
  DEFAULT_TESTSUITE = File.join(ROOT, "tmp", "testsuite")
  SCHEMA = "umath-utn28-coverage/1"
  CONSTRUCT_KEYS = %w[name section rows refused malformed].freeze
  LISTS = %w[rows refused malformed].freeze
  STATUSES = %w[covered refused untested].freeze
  ENGINE = :ruby
  LEGACY_MODEL = "Unicodemath::Model::"
  MODEL = "Umath::Model::"

  # One corpus row: where it comes from, its input and decimal marker, and
  # its expected outcome in the form its corpus writes.
  Row = Struct.new(:id, :source, :input, :decimal, :expected, keyword_init: true) do
    def refusal?
      expected.key?("refusal")
    end
  end

  module_function

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end

  # The mapping, with its shape checked.
  def load_mapping(path = MAPPING)
    doc = YAML.safe_load_file(path, aliases: false)
    raise Error, "#{relative(path)}: schema is not #{SCHEMA}" unless doc.is_a?(Hash) && doc["schema"] == SCHEMA

    constructs = doc.fetch("constructs")
    names = constructs.map { |c| c["name"] }
    dup = names.select { |n| names.count(n) > 1 }.uniq
    raise Error, "#{relative(path)}: constructs listed twice: #{dup.join(', ')}" unless dup.empty?

    constructs.each do |c|
      unknown = c.keys - CONSTRUCT_KEYS
      raise Error, "#{c['name']}: unknown keys #{unknown.join(', ')}" unless unknown.empty?
      unless c["name"].is_a?(String) && c["section"].is_a?(String)
        raise Error, "#{c.inspect}: needs a name and a section"
      end

      LISTS.each do |list|
        ids = c.fetch(list, [])
        raise Error, "#{c['name']}: #{list} is not a list of row ids" unless ids.is_a?(Array) && ids.all?(String)
      end
      if !c.fetch("rows", []).empty? && !c.fetch("refused", []).empty?
        raise Error, "#{c['name']}: has both rows and refused rows; split the construct"
      end
    end
    doc
  rescue KeyError, Psych::Exception => e
    raise Error, "#{relative(path)}: #{e.message}"
  end

  # The rows of corpora/model/representative.yml.
  def corpus_rows(path = CORPUS)
    doc = YAML.safe_load_file(path, aliases: false)
    doc.fetch("rows").map do |row|
      Row.new(id: row.fetch("id"), source: "corpus", input: row.fetch("input"),
              decimal: row.fetch("decimal", "."), expected: row.fetch("expected"))
    end
  end

  # The typed-model rows of the pinned testsuite generation, after the pin
  # checks of scripts/replay_corpus.rb, and the pin.
  def testsuite_rows(testsuite, pin_path)
    pin = UmathReplayCorpus.load_pin(pin_path)
    _dir, payloads = UmathReplayCorpus.verify(File.expand_path(testsuite), pin)
    rows = payloads.sort.flat_map do |rel, bytes|
      doc = YAML.safe_load(bytes, aliases: false)
      next [] unless doc["boundary"] == "typed-model"

      doc.fetch("cases").map do |row|
        where = "#{rel} #{row['id']}"
        UmathReplayCorpus.check_options(row, where)
        Row.new(id: row.fetch("id"), source: "testsuite",
                input: UmathReplayCorpus.decode(row.fetch("input"), where),
                decimal: StageCases::DECIMAL, expected: renamed(row.fetch("expected")))
      end
    end
    raise Error, "generation #{pin.generation} has no typed-model rows" if rows.empty?

    [rows, pin]
  rescue UmathReplayCorpus::Error => e
    raise Error, e.message
  end

  # +value+ with the pre-rename model class names replaced.
  def renamed(value)
    case value
    when Hash
      value.to_h do |k, v|
        legacy = k == "node" && v.is_a?(String) && v.start_with?(LEGACY_MODEL)
        [k, legacy ? MODEL + v.delete_prefix(LEGACY_MODEL) : renamed(v)]
      end
    when Array then value.map { |v| renamed(v) }
    else value
    end
  end

  # The row's outcome on the Ruby engine, in its corpus's form.
  def outcome(row)
    return StageCases::Outcome.model_of(row.input, ENGINE) if row.source == "testsuite"

    begin
      { "model" => Umath.parse(row.input, decimal: row.decimal, engine: ENGINE).to_hash }
    rescue Umath::ParseError => e
      { "refusal" => { "error" => e.class.name.split("::").last, "char_offset" => e.char_offset,
                       "byte_offset" => e.byte_offset } }
    end
  rescue StageCases::Failure => e
    raise Error, "#{row.id}: #{e.message}"
  end

  # "accepted" or "refused": what the row expects, once its outcome is
  # checked against that expectation.
  def evaluate(row)
    actual = outcome(row)
    unless actual == row.expected
      raise Error, "#{row.id}: the outcome differs from the row's expectation " \
                   "(expected #{JSON.generate(row.expected)[0, 200]}, got #{JSON.generate(actual)[0, 200]})"
    end
    row.refusal? ? "refused" : "accepted"
  end

  # The construct's status from the evaluated rows +results+ (id =>
  # "accepted" or "refused").
  def classify(construct, results)
    { "rows" => "accepted", "refused" => "refused", "malformed" => "refused" }.each do |list, want|
      construct.fetch(list, []).each do |id|
        got = results.fetch(id) { raise Error, "#{construct['name']}: no row #{id}" }
        raise Error, "#{construct['name']}: #{id} is listed under #{list} but is #{got}" unless got == want
      end
    end
    return "covered" unless construct.fetch("rows", []).empty?
    return "refused" unless construct.fetch("refused", []).empty?

    "untested"
  end

  # Every mapped id names a row, every row is mapped or unmapped, and no row
  # is both.
  def check_complete(mapping, rows)
    ids = rows.map(&:id)
    dup = ids.select { |id| ids.count(id) > 1 }.uniq
    raise Error, "row ids in both corpora: #{dup.join(', ')}" unless dup.empty?

    mapped = mapping.fetch("constructs").flat_map { |c| LISTS.flat_map { |l| c.fetch(l, []) } }.uniq
    unmapped = mapping.fetch("unmapped", []).map { |u| u.fetch("id") }
    missing = (mapped + unmapped) - ids
    raise Error, "mapped ids that name no row: #{missing.join(', ')}" unless missing.empty?

    both = mapped & unmapped
    raise Error, "ids both mapped and unmapped: #{both.join(', ')}" unless both.empty?

    loose = ids - mapped - unmapped
    raise Error, "rows neither mapped nor unmapped: #{loose.join(', ')}" unless loose.empty?

    mapped
  end

  # The full result: each construct with its status, and the counts.
  def compute(testsuite: DEFAULT_TESTSUITE, pin: UmathReplayCorpus::DEFAULT_PIN, mapping: load_mapping)
    suite, pinned = testsuite_rows(testsuite, pin)
    corpus = corpus_rows
    rows = corpus + suite
    mapped = check_complete(mapping, rows)
    by_id = rows.to_h { |r| [r.id, r] }
    results = mapped.to_h { |id| [id, evaluate(by_id.fetch(id))] }
    constructs = mapping.fetch("constructs").map { |c| c.merge("status" => classify(c, results)) }
    { "mapping" => mapping, "constructs" => constructs, "generation" => pinned.generation,
      "corpus_rows" => corpus.size, "testsuite_rows" => suite.size,
      "malformed_rows" => constructs.flat_map { |c| c.fetch("malformed", []) }.uniq.size }
  end

  def cell(text)
    text.gsub("|", "\\|")
  end

  def ids(list)
    list.map { |id| "`#{id}`" }.join(", ")
  end

  def are(count)
    count == 1 ? "#{count} is" : "#{count} are"
  end

  def sentence_list(items)
    items.size < 2 ? items.join : "#{items[0..-2].join(', ')} and #{items[-1]}"
  end

  # +text+ filled to +width+ columns.
  def wrap(text, width = 76)
    text.split.each_with_object([+""]) do |word, lines|
      lines << +"" if !lines.last.empty? && lines.last.size + 1 + word.size > width
      lines.last << " " unless lines.last.empty?
      lines.last << word
    end.join("\n")
  end

  def summary_region(result)
    constructs = result["constructs"]
    count = STATUSES.to_h { |s| [s, constructs.count { |c| c["status"] == s }] }
    refused = constructs.select { |c| c["status"] == "refused" }
    unmapped = result["mapping"].fetch("unmapped", [])
    out_of_scope = result["mapping"].fetch("out_of_scope", []).map { |s| s.fetch("section") }
    first = "The table lists #{constructs.size} constructs of UTN 28 version " \
            "#{result['mapping'].dig('source', 'version')} with the rows that exercise them, out of the " \
            "#{result['corpus_rows']} rows of `corpora/model/representative.yml` and the " \
            "#{result['testsuite_rows']} typed-model rows of plurimath-testsuite generation " \
            "#{result['generation']}. Of the #{constructs.size} constructs, #{are(count['covered'])} covered, " \
            "#{are(count['refused'])} refused and #{are(count['untested'])} untested."
    second = +"Covered means that every row listed for the construct parses to the model the row " \
              "expects. Refused means that the rows give input UTN 28 defines and that umath refuses " \
              "it on purpose"
    unless refused.empty?
      names = refused.map { |c| "the #{c['name'].sub(/\A[[:upper:]]/, &:downcase)} (#{c['section']})" }
      second << "; this is the case for #{sentence_list(names)}"
    end
    second << ". Untested means that no row exercises the construct, so the corpus does not show " \
              "whether umath reads it."
    third = +"Of the rows, #{result['malformed_rows']} give incomplete input, such as a trailing `/` " \
             "or an unclosed bracket, and umath refuses them. They are listed with their construct " \
             "and do not change its status."
    unless unmapped.empty?
      third << " The rows #{sentence_list(unmapped.map { |u| "`#{u.fetch('id')}`" })} belong to no " \
               "UTN 28 construct."
    end
    third << " Sections #{sentence_list(out_of_scope)} define no notation and are left out." unless out_of_scope.empty?
    "#{[first, second, third].map { |p| wrap(p) }.join("\n\n")}\n"
  end

  def table_region(result)
    out = +"[cols=\"2,7,2,9\",options=\"header\"]\n|===\n|Section |Construct |Status |Rows\n"
    result["constructs"].each do |c|
      evidence = ids(c.fetch("rows", []) + c.fetch("refused", []))
      malformed = c.fetch("malformed", [])
      unless malformed.empty?
        evidence = [evidence, "incomplete input refused: #{ids(malformed)}"].reject(&:empty?).join(" +\n")
      end
      out << "\n|#{c['section']}\n|#{cell(c['name'])}\n|#{c['status']}\n|#{evidence}\n"
    end
    out << "|===\n"
  end

  def regions(result)
    { "utn28-summary" => summary_region(result), "utn28-coverage" => table_region(result) }
  end

  # +text+ with each generated region replaced.
  def render(text, regions)
    regions.reduce(text) do |doc, (name, body)|
      pattern = %r{^// BEGIN GENERATED #{Regexp.escape(name)}\n.*?^// END GENERATED #{Regexp.escape(name)}\n}m
      raise Error, "#{relative(DOC)} has no region #{name}" unless doc.match?(pattern)

      doc.sub(pattern) { "// BEGIN GENERATED #{name}\n#{body}// END GENERATED #{name}\n" }
    end
  end

  def run(argv, out: $stdout)
    options = { testsuite: DEFAULT_TESTSUITE, pin: UmathReplayCorpus::DEFAULT_PIN }
    OptionParser.new do |o|
      o.banner = "usage: scripts/utn28_coverage.rb [--check] [--testsuite PATH] [--pin FILE]"
      o.on("--check") { options[:check] = true }
      o.on("--testsuite PATH") { |v| options[:testsuite] = v }
      o.on("--pin FILE") { |v| options[:pin] = v }
    end.parse!(argv)
    raise Error, "unknown arguments: #{argv.join(' ')}" unless argv.empty?

    result = compute(testsuite: options[:testsuite], pin: options[:pin])
    counts = STATUSES.map { |s| "#{s}=#{result['constructs'].count { |c| c['status'] == s }}" }.join(" ")
    out.puts "#{result['constructs'].size} constructs: #{counts}"
    current = File.binread(DOC).force_encoding(Encoding::UTF_8)
    updated = render(current, regions(result))
    if options[:check]
      return 0 if current == updated

      warn "#{relative(DOC)} is out of date; run scripts/utn28_coverage.rb"
      return 1
    end
    File.binwrite(DOC, updated) unless current == updated
    0
  rescue OptionParser::ParseError => e
    raise Error, e.message
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit Utn28Coverage.run(ARGV.dup)
  rescue Utn28Coverage::Error => e
    warn e.message
    exit 2
  end
end
