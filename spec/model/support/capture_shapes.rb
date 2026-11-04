# frozen_string_literal: true

require "json"
require "set"

module Unicodemath
  module Spec
    # Static result shapes of the normalized grammar's captures, from
    # grammars/unicodemath.normalized-rules.json, under Parslet's flattening
    # rules (Parsanol::Atoms::CanFlatten): for every capture name, whether
    # its value can be nil, a string (slice), a hash (and with which keys) or
    # an array of hashes (and with which keys).
    #
    # Written independently of scripts/normalize_shapes.rb, so the model
    # specs check the generated classes against a second reading of the
    # grammar.
    class CaptureShapes
      Shape = Struct.new(:kinds, :hash_keys, :array_keys) do
        def self.empty = new(Set.new, Set.new, Set.new)
        def self.of(kind, hash_keys = [], array_keys = [])
          new(Set[kind], Set.new(hash_keys), Set.new(array_keys))
        end

        def |(other)
          Shape.new(kinds | other.kinds, hash_keys | other.hash_keys, array_keys | other.array_keys)
        end
      end

      STRING = Shape.of(:string).freeze
      NIL = Shape.of(:nil).freeze

      attr_reader :captures, :root

      # The shape of the root rule's result: the value of the tree capture.
      def root_shape = @rule_shapes[@root]

      def initialize(rules_path)
        doc = JSON.parse(File.read(rules_path, encoding: "UTF-8"))
        @rules = doc.fetch("rules")
        @root = doc.fetch("root")
        @rule_shapes = Hash.new { |h, k| h[k] = Shape.empty }
        @captures = Hash.new { |h, k| h[k] = Shape.empty }
        solve
      end

      private

      def solve
        loop do
          before = snapshot
          @rules.each { |name, node| @rule_shapes[name] |= shape(node, false) }
          break if snapshot == before
        end
      end

      def snapshot
        [@rule_shapes.transform_values(&:to_a), @captures.transform_values(&:to_a)].hash
      end

      def shape(node, named)
        if node.key?("alt") then node["alt"].map { |n| shape(n, false) }.reduce(:|)
        elsif node.key?("seq") then sequence(node["seq"].map { |n| shape(n, false) })
        elsif node.key?("as")
          inner = shape(node["of"], true) # before reading the capture: it may nest in itself
          @captures[node["as"]] |= inner
          Shape.of(:hash, [node["as"]])
        elsif node.key?("ref") then @rule_shapes[node["ref"]]
        elsif node.key?("rep") then repetition(node, named)
        elsif node.key?("look") then NIL
        elsif node.key?("str") || node.key?("re") || node.key?("decimal_marker") then STRING
        else raise "unknown grammar node #{node.keys.inspect}"
        end
      end

      def repetition(node, named)
        inner = shape(node["rep"], false)
        out = Shape.empty
        if node["tag"] == "maybe"
          out |= named ? NIL : STRING # absent
          out |= named ? inner : without_nil(inner) | (inner.kinds.include?(:nil) ? STRING : Shape.empty)
          return out
        end
        out |= (named ? Shape.of(:array) : STRING) if node["min"].zero?
        if inner.kinds.include?(:hash) || inner.kinds.include?(:array)
          out |= Shape.new(Set[:array], Set.new, inner.hash_keys | inner.array_keys)
        end
        out |= STRING if inner.kinds.intersect?(Set[:string, :nil])
        out
      end

      def without_nil(shape)
        Shape.new(shape.kinds - [:nil], shape.hash_keys, shape.array_keys)
      end

      # Parslet's merge_fold over the non-nil results, all combinations.
      def sequence(shapes)
        states = Set[[:none, Set.new, Set.new]] # kind, hash keys, array keys
        shapes.each do |s|
          next_states = Set.new
          states.each do |state|
            s.kinds.each { |k| next_states << fold(state, k, s) }
          end
          states = next_states
        end
        states.reduce(Shape.empty) do |acc, (kind, hk, ak)|
          acc | (kind == :none ? STRING : Shape.new(Set[kind], hk, ak))
        end
      end

      def fold((kind, hk, ak), k, s)
        return [kind, hk, ak] if k == :nil
        return [k, k == :hash ? s.hash_keys : Set.new, k == :array ? s.array_keys : Set.new] if kind == :none

        case [kind, k]
        when %i[string string] then [:string, hk, ak]
        when %i[hash hash] then [:hash, hk | s.hash_keys, ak]
        when %i[array array] then [:array, hk, ak | s.array_keys]
        when %i[string hash] then [:hash, s.hash_keys, ak]
        when %i[hash string] then [:hash, hk, ak]
        when %i[string array] then [:array, hk, s.array_keys]
        when %i[array string] then [:array, hk, ak]
        when %i[array hash] then [:array, hk, ak | s.hash_keys]
        when %i[hash array] then [:array, hk, s.array_keys | hk]
        end
      end
    end
  end
end
