# frozen_string_literal: true

# Builds grammars/unicodemath.parg from the committed grammar export in
# data/unicodemath-grammar.json.
#
# Usage:
#   ruby scripts/generate_grammar.rb            write grammars/unicodemath.parg
#   ruby scripts/generate_grammar.rb --check    exit 1 if it is stale
#
#   BUNDLE_GEMFILE=scripts/oracle/Gemfile BUNDLE_PATH=vendor/oracle-bundle \
#     bundle exec ruby scripts/generate_grammar.rb --export ORACLE_CHECKOUT
#                                               rewrite data/unicodemath-grammar.json
#
# Generation (the first two forms) is pure Ruby stdlib and a pure function of
# the export: it needs neither Plurimath nor Parsanol and writes no
# timestamps.
#
# --export is the one-time provenance step. It loads the legacy grammar from a
# clean Plurimath checkout at ORACLE_COMMIT (inside the oracle bundle of
# scripts/oracle/), walks the Parsanol atom graph of
# Plurimath::UnicodeMath::Parse rule by rule and writes it, with every input
# the grammar reads from Plurimath when it loads (the symbol catalog behind
# Constants.wrapper_symbols, the decimal markers behind
# Plurimath.configuration.decimal), to the export file. The build and the
# gem never load Plurimath; they read only that file.

require "digest"
require "json"
require "set"
require_relative "normalize_shapes"

ROOT = File.expand_path("..", __dir__)
EXPORT = File.join(ROOT, "data/unicodemath-grammar.json")
OUT = File.join(ROOT, "grammars/unicodemath.parg")
# The wrappers the shape normalization added (scripts/normalize_shapes.rb),
# read by the test-only unwrap and by the model generator.
WRAPPERS_OUT = File.join(ROOT, "grammars/unicodemath.wrappers.json")
NORMALIZED_OUT = File.join(ROOT, "grammars/unicodemath.normalized-rules.json")
FORMAT = "unicodemath-grammar-export/1"

# The symbol captures (normalization rule N8, scripts/normalize_shapes.rb):
# the captures whose legacy transform rules build a symbol through the
# symbol catalog (Utility.symbols_class in Plurimath's unicode_math
# transform). Their text is captured as +spelling+, and the model gives each
# its catalog value and kind (Unicodemath::Symbols).
SYMBOL_CAPTURES = %w[
  accent_symbols alphanumeric binary_negated_operator binary_symbols combined_symbols comma
  diacritic_belows diacritic_overlays exclamation_symbol infty ldots mid_symbol nary_class
  negated_operator negative operator ordinary_negated_operator ordinary_symbols
  paren_close_prefix paren_open_prefix positive prefixed_prime relational_symbols root_symbol
  spaces unary_symbols unicode_symbols
].freeze
# Symbol captures that hold a node; text in them is captured as +spelling+.
SYMBOL_NODE_CAPTURES = %w[close_paren open_paren prime_accent_symbols symbol].freeze

ORACLE_REPOSITORY = "https://github.com/plurimath/plurimath"
ORACLE_COMMIT = "e7ab4a5186c9be96f62d670574bc2c72f9365ad4"

# Decimal marker => artifact entry name. The same names as amath.
MARKER_ENTRIES = { "." => "dot", "," => "comma", "\u066B" => "arabic" }.freeze

# Words that PARG reserves; a rule or capture with one of these names is
# renamed (rules) or refused (captures).
KEYWORDS = %w[grammar as alt from_table column bindings render derive preprocess
              entry table_lookup custom state set switch skip until atomic
              capture use test example].freeze

# A literal alternation with more branches than this is regrouped into
# nested alternations of at most this many branches (see Generator#alt).
NEST = 16

# Walks the legacy atom graph. Runs only under --export.
class Exporter
  SENTINEL = "\u{E000}DECIMAL_MARKER\u{E000}"

  SOURCE_FILES = %w[
    lib/plurimath/unicode_math/parse.rb
    lib/plurimath/unicode_math/parsing_rules/absence_rules.rb
    lib/plurimath/unicode_math/parsing_rules/common_rules.rb
    lib/plurimath/unicode_math/parsing_rules/constants_rules.rb
    lib/plurimath/unicode_math/parsing_rules/helper.rb
    lib/plurimath/unicode_math/parsing_rules/masked.rb
    lib/plurimath/unicode_math/parsing_rules/sub_sup.rb
    lib/plurimath/unicode_math/constants.rb
    lib/plurimath/unicode_math/parser.rb
    lib/plurimath/base_number_prefix.rb
    lib/plurimath/configuration.rb
    lib/plurimath/formatter/supported_locales.rb
    lib/plurimath/utility.rb
  ].freeze

  def initialize(checkout)
    @checkout = File.expand_path(checkout)
  end

  def run
    verify_checkout
    $LOAD_PATH.unshift(File.join(@checkout, "lib"))
    require "plurimath"
    require "plurimath/version"
    loaded = $LOADED_FEATURES.grep(%r{/lib/plurimath\.rb\z}).first
    abort "plurimath was loaded from #{loaded}, not #{@checkout}" unless loaded&.start_with?(@checkout)

    markers = decimal_markers
    install_sentinel
    doc = {
      "format" => FORMAT,
      "oracle" => oracle,
      "inputs" => {
        "wrapper_symbols" => {
          "source" => "Plurimath::UnicodeMath::Constants.wrapper_symbols " \
                      "(Utility.symbols_hash(:unicodemath) keys matching /\"P\\{[^\\}]+\\}/)",
          "values" => Plurimath::UnicodeMath::Constants.wrapper_symbols.map(&:to_s),
        },
        "decimal_markers" => {
          "source" => "Plurimath.configuration.decimal over DEFAULT_DECIMAL and every " \
                      "Formatter::SupportedLocales decimal; the grammar matches " \
                      "Utility.string_to_html_entity(marker)",
          "values" => markers,
        },
      },
    }
    doc.merge!(walk)
    File.write(EXPORT, "#{JSON.pretty_generate(doc)}\n")
    puts "rules #{doc['rules'].size} classes #{doc['classes'].size}"
    puts "wrote #{EXPORT} sha256:#{Digest::SHA256.file(EXPORT).hexdigest}"
  end

  private

  def verify_checkout
    head = IO.popen(["git", "-C", @checkout, "rev-parse", "HEAD"], &:read).strip
    abort "#{@checkout} is at #{head}, expected #{ORACLE_COMMIT}" unless head == ORACLE_COMMIT
    dirty = IO.popen(["git", "-C", @checkout, "status", "--porcelain", "--untracked-files=no"], &:read)
    abort "#{@checkout} has local changes" unless dirty.strip.empty?
  end

  def oracle
    {
      "repository" => ORACLE_REPOSITORY,
      "commit" => ORACLE_COMMIT,
      "plurimath" => Plurimath::VERSION,
      "ruby" => RUBY_VERSION,
      "parsanol" => Parsanol::VERSION,
      "htmlentities" => Gem.loaded_specs["htmlentities"]&.version&.to_s,
      "files" => SOURCE_FILES.to_h do |f|
        [f, "sha256:#{Digest::SHA256.file(File.join(@checkout, f)).hexdigest}"]
      end,
    }
  end

  # Every decimal marker Plurimath.configuration.decimal can return, with the
  # literal the grammar matches for it.
  def decimal_markers
    values = [Plurimath::Configuration::DEFAULT_DECIMAL]
    values.concat(Plurimath::Formatter::SupportedLocales::LOCALES.values.map { |v| v[:decimal] })
    values.uniq.sort.map do |marker|
      abort "decimal marker #{marker.inspect} has no entry name" unless MARKER_ENTRIES.key?(marker)
      literal = Plurimath::Utility.string_to_html_entity(marker.dup).to_s
      { "marker" => marker, "entry" => MARKER_ENTRIES.fetch(marker), "grammar_literal" => literal }
    end
  end

  # decimal_marker is a method, not a rule, and its literal depends on
  # Plurimath.configuration; it is exported as a marker node.
  def install_sentinel
    sentinel = SENTINEL
    Plurimath::UnicodeMath::Parse.prepend(Module.new do
      define_method(:decimal_marker) { str(sentinel) }
    end)
  end

  def walk
    root = Plurimath::UnicodeMath::Parse.new.root
    atoms = Parsanol::Atoms
    abort "root is not a rule" unless root.is_a?(atoms::Entity)

    rules = {}
    classes = {}
    queue = [root]
    node = lambda do |atom|
      case atom
      when atoms::Entity
        queue << atom
        { "ref" => atom.rule_name.to_s }
      when atoms::Sequence then { "seq" => atom.parslets.map(&node) }
      when atoms::Alternative then { "alt" => atom.alternatives.map(&node) }
      when atoms::Repetition
        { "rep" => node.call(atom.parslet), "min" => atom.min, "max" => atom.max,
          "tag" => atom.result_tag.to_s }
      when atoms::Lookahead then { "look" => node.call(atom.bound_parslet), "positive" => atom.positive }
      when atoms::Named then { "as" => atom.name.to_s, "of" => node.call(atom.parslet) }
      when atoms::Str
        atom.str == SENTINEL ? { "decimal_marker" => true } : { "str" => atom.str }
      when atoms::Re
        classes[atom.match] ||= char_class(atom.re)
        { "re" => atom.match }
      else
        abort "unsupported atom #{atom.class}: #{atom.inspect[0, 200]}"
      end
    end
    until queue.empty?
      entity = queue.shift
      name = entity.rule_name.to_s
      next if rules.key?(name)

      rules[name] = nil
      rules[name] = node.call(entity.parslet)
    end
    { "root" => root.rule_name.to_s, "classes" => classes.sort.to_h, "rules" => rules }
  end

  # A Parsanol Re atom matches one character: the code points whose
  # one-character string the atom's own (multiline) regexp matches, as
  # inclusive ranges.
  def char_class(regexp)
    anchored = Regexp.new("\\A(?:#{regexp.source})\\z", regexp.options)
    ranges = []
    [(0..0xD7FF), (0xE000..0x10FFFF)].each do |span|
      span.each do |cp|
        next unless anchored.match?([cp].pack("U"))

        if ranges.any? && ranges.last[1] == cp - 1
          ranges.last[1] = cp
        else
          ranges << [cp, cp]
        end
      end
    end
    abort "character class #{regexp.source.inspect} matches nothing" if ranges.empty?
    ranges
  end
end

# Turns the export into PARG source.
class Generator
  # The capture (and wrapper rule) that carries the whole tree.
  TREE = "unicodemath_tree"
  MODEL = "model"

  attr_reader :normalizer

  def initialize(bytes)
    @bytes = bytes
    @doc = JSON.parse(bytes)
    abort "unsupported export format #{@doc['format'].inspect}" unless @doc["format"] == FORMAT
    @normalizer = ShapeNormalizer.new(@doc.fetch("rules"), symbols: SYMBOL_CAPTURES,
                                                           symbol_nodes: SYMBOL_NODE_CAPTURES).run
    clash = @normalizer.collisions
    abort "normalization leaves wrapper collisions: #{clash.join('; ')}" unless clash.empty?
    @rules = @normalizer.rules
    abort "the export already uses the name #{TREE}" if bytes.include?("\"#{TREE}")
    @classes = @doc.fetch("classes")
    @markers = @doc.dig("inputs", "decimal_markers", "values")
    @markers.each do |m|
      unless MARKER_ENTRIES[m["marker"]] == m["entry"]
        abort "decimal marker #{m['marker'].inspect} has no entry #{m['entry'].inspect}"
      end
    end
    @names = {}
    @rules.each_key do |n|
      id = n.sub(/\?\z/, "_opt")
      abort "bad rule name #{n.inspect}" unless id.match?(/\A[A-Za-z_]\w*\z/)
      id = "#{id}_rule" if KEYWORDS.include?(id)
      abort "rule name collision #{id}" if @names.value?(id)
      @names[n] = id
    end
    @hoisted = {}
  end

  def root = @doc.fetch("root")

  def generate
    dependent = decimal_dependent
    root = @doc.fetch("root")
    abort "the root rule must depend on the decimal marker" unless dependent.include?(root)

    lines = []
    @rules.each do |name, node|
      if dependent.include?(name)
        @markers.each do |m|
          lines << "  #{@names[name]}__#{m['entry']} = #{emit(node, m['entry'], dependent)}"
        end
      else
        lines << "  #{@names[name]} = #{emit(node, nil, dependent)}"
      end
    end
    @hoisted.each { |text, name| lines << "  #{name} = #{text}" }
    @markers.each do |m|
      lines << "  decimal_marker__#{m['entry']} = #{literal(m['grammar_literal'])}"
    end
    # Each entry starts at a one-capture wrapper around the legacy root, so
    # the declared bindings below can carry the whole tree.
    @markers.each do |m|
      lines << "  #{TREE}__#{m['entry']} = (#{@names.fetch(root)}__#{m['entry']}) as #{TREE}"
    end
    entries = @markers.map { |m| "entry #{m['entry']}: #{TREE}__#{m['entry']}" }
    text = "#{header.join("\n")}\n\ngrammar Unicodemath version \"0.1.0\" {\n" \
           "#{lines.join("\n")}\n}\n\n#{entries.join("\n")}\n\n#{bindings.join("\n")}"
    bad = text.each_line.with_index(1).reject { |l, _| l.ascii_only? }.map(&:last)
    abort "generated grammar is not pure ASCII (lines #{bad.first(5).join(', ')})" unless bad.empty?
    text
  end

  private

  # Two bindings of the one root capture: the legacy raw tree, unchanged
  # (slices with offsets, for parity and positions), and the same tree as
  # plain data under #{MODEL}, from which the typed model's declared
  # attribute types construct it (Unicodemath::Model). They declare AST
  # construction only; the model fields are the model's declarations.
  def bindings
    @markers.map do |m|
      "bindings #{TREE}__#{m['entry']} {\n  #{TREE} -> #{TREE} (raw)\n  #{TREE} -> #{MODEL} (any)\n}\n"
    end
  end

  def header
    o = @doc.fetch("oracle")
    lines = ["# GENERATED by scripts/generate_grammar.rb -- do not edit.",
             "# Plurimath UnicodeMath grammar (#{o['repository']} @ #{o['commit']}),",
             "# exported from Plurimath #{o['plurimath']} with Ruby #{o['ruby']} / Parsanol #{o['parsanol']}.",
             "# data/unicodemath-grammar.json sha256:#{Digest::SHA256.hexdigest(@bytes)}",
             "#",
             "# Every legacy rule is one rule here with the same alternatives, order and",
             "# capture names (`space?` becomes space_opt), plus the captures that the",
             "# shape normalization adds (scripts/normalize_shapes.rb, listed in",
             "# grammars/unicodemath.wrappers.json), so that every capture holds one kind",
             "# of value. The accepted language is unchanged. The input is the",
             "# entity-encoded text that the legacy preprocessing produces. Rules that",
             "# reach the decimal marker are emitted once per marker with a",
             "# __<entry> suffix:"]
    @markers.each do |m|
      lines << "#   entry #{m['entry']}: decimal marker U+#{format('%04X', m['marker'].ord)}"
    end
    lines
  end

  def refs(node, out = Set.new)
    case (k = node.keys.first)
    when "ref" then out << node["ref"]
    when "seq", "alt" then node[k].each { |c| refs(c, out) }
    when "rep", "look" then refs(node[k], out)
    when "as" then refs(node["of"], out)
    end
    out
  end

  def uses_marker?(node)
    case (k = node.keys.first)
    when "decimal_marker" then true
    when "seq", "alt" then node[k].any? { |c| uses_marker?(c) }
    when "rep", "look" then uses_marker?(node[k])
    when "as" then uses_marker?(node["of"])
    else false
    end
  end

  def decimal_dependent
    deps = @rules.transform_values { |n| refs(n) }
    dep = Set.new(@rules.select { |_, n| uses_marker?(n) }.keys)
    loop do
      added = deps.select { |r, rs| !dep.include?(r) && rs.any? { |t| dep.include?(t) } }.keys
      break if added.empty?

      dep.merge(added)
    end
    dep
  end

  def composite?(text)
    !text.match?(/\A(?:"(?:[^"\\]|\\.)*"|%x[0-9A-Fa-f.\-]+|[A-Za-z_]\w*)\z/)
  end

  def wrap(text)
    composite?(text) ? "(#{text})" : text
  end

  def emit(node, entry, dependent)
    case node.keys.first
    when "ref"
      n = node["ref"]
      id = @names.fetch(n)
      dependent.include?(n) ? "#{id}__#{entry}" : id
    when "decimal_marker" then "decimal_marker__#{entry}"
    when "seq" then node["seq"].map { |c| wrap(emit(c, entry, dependent)) }.join(" ")
    when "alt" then alt(node["alt"], entry, dependent)
    when "rep" then rep(node, entry, dependent)
    when "look" then "#{node['positive'] ? '&' : '!'}(#{emit(node['look'], entry, dependent)})"
    when "as"
      cap = node["as"]
      abort "bad capture name #{cap.inspect}" unless cap.match?(/\A[A-Za-z_]\w*\z/) && !KEYWORDS.include?(cap)
      # "" as name: PARG's zero-width marker (str("").as(:name)).
      return "\"\" as #{cap}" if node["of"] == { "str" => "" }

      "(#{emit(node['of'], entry, dependent)}) as #{cap}"
    when "str" then literal(node["str"])
    when "re" then char_class(node["re"])
    else abort "unknown node #{node.keys.first.inspect}"
    end
  end

  # PEG ordered choice is associative, so a wide alternation of literal
  # branches (the constant tables) is regrouped into nested alternations of
  # at most NEST branches: acceptance and trees stay the same, and the
  # compiler's order lint, which compares the branches of one alternation
  # pairwise, stays small (a flat 3,000-branch table makes the artifact grow
  # to over 100 MB).
  def alt(branches, entry, dependent)
    if branches.size > NEST && branches.all? { |c| literal_branch?(c) }
      groups = branches.each_slice((branches.size.to_f / NEST).ceil)
      return groups.map { |g| "(#{alt(g, entry, dependent)})" }.join(" / ")
    end

    seen = []
    branches.map do |c|
      text = emit(c, entry, dependent)
      if c.keys.first == "str"
        # The compiler refuses a literal branch that an earlier literal
        # branch equals or prefixes. The legacy grammar can still reach such
        # a branch (when the earlier one matches but the rest fails), so it
        # is kept behind a one-literal rule, which yields the same tree.
        text = hoist(text) if seen.any? { |e| c["str"].start_with?(e) }
        seen << c["str"]
      end
      wrap(text)
    end.join(" / ")
  end

  def rep(node, entry, dependent)
    body = emit(node["rep"], entry, dependent)
    min = node["min"]
    max = node["max"]
    if node["tag"] == "maybe"
      abort "maybe with min/max #{min}/#{max}" unless min.zero? && max == 1
      "[#{body}]"
    else
      "#{min.zero? ? '' : min}*#{max}(#{body})"
    end
  end

  def literal_branch?(node)
    case node.keys.first
    when "str" then true
    when "as" then literal_branch?(node["of"])
    when "seq" then node["seq"].all? { |c| literal_branch?(c) || c.keys.first == "look" }
    else false
    end
  end

  def hoist(text)
    @hoisted[text] ||= "shadowed_literal_#{@hoisted.size}"
  end

  def literal(str)
    abort "empty literal" if str.empty?
    pieces = str.each_char.chunk_while { |a, b| printable?(a) == printable?(b) }.map do |run|
      if printable?(run.first)
        "\"#{run.join.gsub(/["\\]/) { |c| "\\#{c}" }}\""
      else
        "%x#{run.map { |c| format('%02X', c.ord) }.join('.')}"
      end
    end
    pieces.size == 1 ? pieces.first : "(#{pieces.join(' ')})"
  end

  # ASCII only: everything else is written as %x code points, so the
  # generated source is pure ASCII (the PARG lexer is slow on non-ASCII
  # source, which the artifact embeds and re-lexes when it loads).
  def printable?(char)
    char.ord >= 0x20 && char.ord < 0x7F
  end

  def range(lo, hi)
    lo == hi ? format("%%x%02X", lo) : format("%%x%02X-%02X", lo, hi)
  end

  def char_class(pattern)
    ranges = @classes.fetch(pattern) { abort "no character class for #{pattern.inspect}" }
    body = ranges.map { |lo, hi| range(lo, hi) }.join(" / ")
    ranges.size == 1 ? body : "(#{body})"
  end
end

if (i = ARGV.index("--export"))
  checkout = ARGV[i + 1] or abort "usage: --export ORACLE_CHECKOUT"
  ARGV.slice!(i, 2)
  abort "usage: ruby scripts/generate_grammar.rb [--check | --export ORACLE_CHECKOUT]" unless ARGV.empty?
  Exporter.new(checkout).run
  exit
end

check = ARGV.delete("--check")
abort "usage: ruby scripts/generate_grammar.rb [--check | --export ORACLE_CHECKOUT]" unless ARGV.empty?

generator = Generator.new(File.binread(EXPORT))
grammar = generator.generate
norm = generator.normalizer
wrappers = "#{JSON.pretty_generate(
  'format' => 'unicodemath-wrappers/1',
  'wrappers' => norm.wrapper_list,
  'rules' => norm.counts.sort.to_h,
)}\n"
normalized = "#{JSON.generate('format' => FORMAT, 'root' => generator.root, 'rules' => norm.rules)}\n"
outputs = { OUT => grammar, WRAPPERS_OUT => wrappers, NORMALIZED_OUT => normalized }
if check
  stale = outputs.reject { |path, text| File.exist?(path) && File.read(path, encoding: "UTF-8") == text }.keys
  if stale.empty?
    puts "#{outputs.keys.map { |p| p.delete_prefix("#{ROOT}/") }.join(', ')} up to date"
  else
    warn "stale: #{stale.map { |p| p.delete_prefix("#{ROOT}/") }.join(', ')}; run ruby scripts/generate_grammar.rb"
    exit 1
  end
else
  outputs.each do |path, text|
    File.write(path, text)
    puts "wrote #{path.delete_prefix("#{ROOT}/")} bytes=#{text.bytesize} sha256:#{Digest::SHA256.hexdigest(text)}"
  end
end
