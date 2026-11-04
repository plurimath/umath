# frozen_string_literal: true

# Writes lib/unicodemath/model/nodes.rb, the plain LML classes of the
# UnicodeMath model, from the static capture shapes of the normalized
# grammar (grammars/unicodemath.normalized-rules.json, written by
# scripts/generate_grammar.rb).
#
# Usage:
#   ruby scripts/generate_model.rb            write the classes
#   ruby scripts/generate_model.rb --check    exit 1 if they are stale
#
# After normalization every capture holds one kind, so the mapping is
# mechanical and needs no union, cast hook or walker:
#
#   capture of kind hash  -> class <Capture>, one attribute per key
#   capture of kind list  -> class <Capture>Item for the elements; the
#                            attribute is a collection of it
#   capture of kind text  -> :string attribute
#   capture of kind hash with EXPRESSION_KEYS or more keys (a whole
#                         expression: expr, exp, factor, numerator, base,
#                         sub, sup, first_value, the tree itself ...)
#                         -> the shared class Expression, declaring the
#                            union of their keys
#   capture named in SHARED -> that shared class, declaring the union of
#                            the keys of its captures
#   capture of kind hash whose only key is +spelling+ (a symbol, rule N8)
#                         -> the shared class MathSymbol {spelling, value,
#                            kind}; any other class with +spelling+ also
#                            gets +value+ and +kind+ (filled by
#                            Unicodemath::Symbols after construction)
#
# An attribute has the same name and type wherever it occurs, because its
# type is the type of the capture it names. Generation fails on a capture
# that holds more than one kind, nil, or nothing.

require "json"
require_relative "unicodemath_shapes"

ROOT = File.expand_path("..", __dir__)
RULES = File.join(ROOT, "grammars/unicodemath.normalized-rules.json")
OUT = File.join(ROOT, "lib/unicodemath/model/nodes.rb")
TREE = "unicodemath_tree"
NS = "Unicodemath::Model"
RESERVED = { "array" => "ArrayNode", "symbol" => "SymbolNode", "root" => "RootNode",
             "math_symbol" => "MathSymbolNode", "document" => "DocumentNode" }.freeze
SPELLING = "spelling"
SYMBOL_CLASS = "MathSymbol"
SYMBOL_KINDS = %w[symbol paren unlisted].freeze
DERIVED = %w[value kind].freeze
# The expression captures have 25 to 97 keys, every other capture 16 or
# fewer. One class for them keeps the class graph small: lutaml-model
# compiles a serialization transformation per path through the graph, which
# grows past any practical time with one class per expression capture.
EXPRESSION_KEYS = 25
EXPRESSION_CLASS = "Expression"
# For the same reason, captures that would form a cycle of classes outside
# Expression share one class. Generation fails if such a cycle is left.
SHARED = {
  "MiniExpression" => %w[mini_expr mini_intermediate_exp sub_recursion_expr sub_recursions
                         sup_recursion_expr sup_recursions],
  "Paren" => %w[close_paren open_paren],
}.freeze

check = ARGV.delete("--check")
abort "usage: ruby scripts/generate_model.rb [--check]" unless ARGV.empty?

doc = JSON.parse(File.read(RULES, encoding: "UTF-8"))
shapes = UnicodemathShapes.new(doc.fetch("rules"), normalized: true)
caps = shapes.solve
# The generator wraps the root rule in the tree capture; add its shape.
caps[TREE] = shapes.shape({ "ref" => doc.fetch("root") }, true)

kind = lambda do |name|
  shape = caps.fetch(name)
  unless shape.solid.size == 1 && !shape.kinds.include?(:nil)
    abort "capture #{name} holds #{shape.kinds.to_a.join('|').then { |k| k.empty? ? 'nothing' : k }}; " \
          "normalize the grammar first"
  end
  shape.solid.first
end
symbol = ->(name) { kind.call(name) == :hash && caps[name].hash_keys.to_a == [SPELLING] }
clash = caps.keys & DERIVED
abort "the grammar captures #{clash.join(', ')}, which the symbol classes declare" unless clash.empty?
camel = ->(n) { RESERVED[n] || n.split("_").map { |w| w[0].upcase + w[1..] }.join }

expression = ->(name) { kind.call(name) == :hash && caps[name].hash_keys.size >= EXPRESSION_KEYS }
shared = SHARED.flat_map { |cname, names| names.map { |n| [n, cname] } }.to_h
unknown = shared.keys - caps.keys
abort "SHARED names captures the grammar does not have: #{unknown.join(', ')}" unless unknown.empty?
class_of = lambda do |name|
  next EXPRESSION_CLASS if expression.call(name)

  shared.fetch(name) { camel.call(name) }
end

classes = {} # class name => [captures, attribute keys]
caps.keys.sort.each do |name|
  next if symbol.call(name)

  case kind.call(name)
  when :hash
    held, keys = classes[class_of.call(name)] || [[], []]
    unless held.empty? || expression.call(name) || shared.key?(name)
      abort "class name #{class_of.call(name)} is used by #{held.join(', ')} and #{name}"
    end
    classes[class_of.call(name)] = [held + [name], (keys | caps[name].hash_keys.to_a).sort]
  when :array then classes["#{camel.call(name)}Item"] = [[name], caps[name].array_keys.to_a.sort]
  end
end

# No cycle of two or more classes outside Expression (self references are
# fine: lutaml-model stops at a class already on its path).
require "tsort"
edges = classes.to_h do |cname, (_, keys)|
  [cname, keys.filter_map { |k| next if kind.call(k) == :string || symbol.call(k)

                                 kind.call(k) == :array ? "#{camel.call(k)}Item" : class_of.call(k) }.uniq - [cname]]
end
graph = edges.reject { |c, _| c == EXPRESSION_CLASS }.transform_values { |v| v - [EXPRESSION_CLASS] }
cycles = TSort.strongly_connected_components(->(&b) { graph.each_key(&b) }, ->(n, &b) { graph.fetch(n).each(&b) })
              .select { |c| c.size > 1 }
abort "class cycles outside #{EXPRESSION_CLASS}: #{cycles.map { |c| c.sort.join(' ') }.join('; ')}; add them to SHARED" unless cycles.empty?

type_of = lambda do |key|
  return %("#{NS}::#{SYMBOL_CLASS}") if symbol.call(key)

  case kind.call(key)
  when :hash then %("#{NS}::#{class_of.call(key)}")
  when :array then %("#{NS}::#{camel.call(key)}Item", collection: true)
  else ":string"
  end
end

out = +<<~RUBY
  # frozen_string_literal: true

  # GENERATED by scripts/generate_model.rb from the normalized grammar's
  # capture shapes -- do not edit. #{classes.size + 1} classes.
  module Unicodemath
    module Model
      # A symbol: the value of every symbol capture. +spelling+ is the
      # token as the grammar matched it; +value+ (its Unicode text) and
      # +kind+ come from the symbol catalog (Unicodemath::Symbols).
      class #{SYMBOL_CLASS} < Lutaml::Model::Serializable
        attribute :spelling, :string
        attribute :value, :string
        attribute :kind, :string, values: %w[#{SYMBOL_KINDS.join(' ')}]
      end

RUBY
derived = "      attribute :value, :string\n      attribute :kind, :string, values: %w[#{SYMBOL_KINDS.join(' ')}]\n"
classes.sort.each do |cname, (held, keys)|
  what = if held.size > 1 then "A whole expression: the captures #{held.map { |c| "+#{c}+" }.join(', ')}"
         elsif kind.call(held.first) == :array then "An element of capture +#{held.first}+"
         else "Capture +#{held.first}+"
         end
  comment = "# #{what}.".gsub(/(.{1,72})(\s+|\z)/, "\\1\n").lines.map { |l| "    #{l.start_with?('#') ? l : "# #{l}"}" }.join
  out << "#{comment}    class #{cname} < Lutaml::Model::Serializable\n"
  keys.each { |k| out << "      attribute :#{k}, #{type_of.call(k)}\n" }
  out << derived if keys.include?(SPELLING)
  out << "    end\n\n"
end
out.chomp!("\n")
out << "  end\nend\n"

if check
  if File.exist?(OUT) && File.read(OUT, encoding: "UTF-8") == out
    puts "#{OUT.delete_prefix("#{ROOT}/")} is up to date"
  else
    warn "#{OUT.delete_prefix("#{ROOT}/")} is stale; run ruby scripts/generate_model.rb"
    exit 1
  end
else
  File.write(OUT, out)
  puts "wrote #{OUT.delete_prefix("#{ROOT}/")}: #{classes.size + 1} classes"
end
