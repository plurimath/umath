# frozen_string_literal: true

require "set"
require_relative "normalize_shapes"

# The UnicodeMath capture-shape normalization: the shared rules N1-N7 of
# scripts/normalize_shapes.rb (kept byte-identical across the stage gems)
# plus what UnicodeMath adds. Used by scripts/generate_grammar.rb and
# scripts/generate_model.rb.
#
#   N8 symbol spelling    a symbol capture (one the legacy transform looks
#                         up in the symbol catalog) that holds text becomes
#                         `((x) as spelling) as name`; in a symbol capture
#                         that holds a node, N1 wraps text as `spelling`
#                         instead of `literal`. The model then gives every
#                         symbol its spelling, value and kind.
#
# #shape also fixes the shared solver for a capture nested in a capture of
# the same name, whose inner keys `@captures[name] |= shape(...)` would drop
# (it reads the old value before the inner call adds to it).
#
# After the rewrite #run requires (#check!) that no capture holds more than
# one kind, nil, or nothing; that no sequence carries one wrapper key twice
# (#collisions); and that no sequence has more than one hash part after a
# list wrapper (#list_tails): there legacy appends each hash to the list
# separately, and the unwrap could not tell two parts from one.
class UmathShapes < ShapeNormalizer
  SPELLING = "spelling"

  # +symbols+: the symbol captures that hold text; +symbol_nodes+: the
  # symbol captures that hold a node.
  def initialize(rules, normalized: false, symbols: [], symbol_nodes: [])
    super(rules, normalized: normalized)
    @symbols = symbols.to_set
    @symbol_nodes = symbol_nodes.to_set
    @in_symbol_node = false
  end

  def run
    super
    spell
    check!
  end

  def shape(node, named)
    return super unless node.key?("as")

    inner = shape(node["of"], true)
    @captures[node["as"]] |= inner
    Shape.of(:hash, [node["as"]])
  end

  def wrapper?(key) = key == SPELLING || super

  # Captures that hold more than one kind, nil, or nothing at all (the
  # model could not tell nil from an absent key). Empty after #run.
  def bad_captures
    solve
    @captures.select { |_, s| s.mixed? || s.kinds.include?(:nil) || s.solid.empty? }
             .map { |k, s| "#{k} (#{s.kinds.to_a.join('|')})" }
  end

  # Raises unless every capture holds one kind and no sequence is ambiguous
  # for the unwrap. Returns self.
  def check!
    problems = bad_captures.map { |c| "capture #{c}" } +
               collisions.map { |c| "wrapper collision #{c}" } +
               list_tails.map { |c| "hash parts after a list #{c}" }
    raise "normalization failed: #{problems.join('; ')}" unless problems.empty?

    self
  end

  # Sequences with more than one part that can give a hash with ordinary
  # (non-wrapper) keys after a part that can carry the list wrapper. Legacy
  # folds such a sequence to list + [h1] + [h2]; the unwrap sees one hash
  # after the list and would give list + [h1.merge(h2)].
  def list_tails
    solve
    found = []
    each_node do |n, rule|
      next unless n.key?("seq")

      seen_list = false
      tail = 0
      n["seq"].each do |c|
        keys = shape(c, false).hash_keys
        tail += 1 if (seen_list || keys.include?("list")) && keys.any? { |key| !wrapper?(key) }
        seen_list ||= keys.include?("list")
      end
      found << "in #{rule} (#{tail} parts)" if tail > 1
    end
    found
  end

  private

  # Yields every node of every rule with the rule's name.
  def each_node
    walk = lambda do |n, rule|
      yield n, rule
      k = n.keys.first
      case k
      when "seq", "alt" then n[k].each { |c| walk.call(c, rule) }
      when "rep", "look" then walk.call(n[k], rule)
      when "as" then walk.call(n["of"], rule)
      end
    end
    @rules.each { |r, b| walk.call(b, r) }
  end

  # N8 (node part): while a symbol node capture is normalized, N1 wraps its
  # text as spelling.
  def visit(node, targets)
    return super unless node.key?("as") && targets.include?(node["as"])

    saved = @in_symbol_node
    @in_symbol_node = @symbol_nodes.include?(node["as"])
    super
  ensure
    @in_symbol_node = saved if node.key?("as") && targets.include?(node["as"])
  end

  def wrap(node, name, rule)
    super(node, @in_symbol_node && rule == "N1 text alternative" ? SPELLING : name, rule)
  end

  # N8 (text part): every site of a text symbol capture gets its slice
  # under spelling. Runs once, after the shared rules converged.
  def spell
    solve
    unknown = (@symbols | @symbol_nodes).reject { |name| @captures.key?(name) }
    raise "symbol captures not in the grammar: #{unknown.to_a.join(', ')}" unless unknown.empty?

    wrong = @symbols.reject { |name| @captures[name].solid == Set[:string] } +
            @symbol_nodes.reject { |name| @captures[name].solid.subset?(Set[:hash, :array]) }
    raise "symbol captures of the wrong kind: #{wrong.join(', ')}" unless wrong.empty?

    rewrite = lambda do |n|
      k = n.keys.first
      case k
      when "seq", "alt" then { k => n[k].map(&rewrite) }
      when "rep", "look" then n.merge(k => rewrite.call(n[k]))
      when "as"
        inner = rewrite.call(n["of"])
        if @symbols.include?(n["as"])
          count("N8 symbol spelling")
          inner = { "as" => SPELLING, "of" => inner }
        end
        { "as" => n["as"], "of" => inner }
      else n
      end
    end
    @rules.transform_values!(&rewrite)
  end
end
