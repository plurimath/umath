# frozen_string_literal: true

module Unicodemath
  module Model
    # Construction check: projects a model back onto the grammar's capture
    # tree, to compare it with the tree the bindings produced.
    #
    # Internal; used by the model specs and scripts/replay_corpus.rb to show
    # that constructing the model kept every capture (lutaml-model ignores
    # keys a class does not declare, so a missing declaration would
    # otherwise lose data silently).
    module CaptureTree
      # A capture the bound tree has but the model class does not declare.
      class Undeclared < StandardError; end

      # An attribute holding a value that is not of its declared type.
      class Untyped < StandardError; end

      module_function

      # The capture tree of +value+, a model node (or Array of them, or
      # text): Hashes with String keys in declaration order, Arrays and
      # Strings. A MathSymbol is its spelling; a node holding only text is
      # that text.
      def dump(value)
        case value
        when ::Array then value.map { |v| dump(v) }
        when MathSymbol then value.spelling
        when Node
          set = value.class.attributes.keys.reject { |name| value.public_send(name).nil? }
          return dump(value.literal) if set == [:literal]

          set.to_h do |name|
            held = value.public_send(name)
            check_type(value.class, name, held)
            [name.to_s, dump(held)]
          end
        else value
        end
      end

      def check_type(klass, name, held)
        attribute = klass.attributes.fetch(name)
        type = attribute.type
        expected = type.is_a?(Class) && type <= Lutaml::Model::Serializable ? type : ::String
        items = attribute.collection? ? held : [held]
        return if items.is_a?(::Array) && items.all? { |item| item.is_a?(expected) }

        raise Untyped, "#{klass.name}##{name} holds #{held.inspect[0, 80]}, not #{expected.name}"
      end

      # +data+ (the bound tree) as dump would render the model of +klass+
      # built from it: one-element collections for a single node, and an
      # Undeclared error for a key +klass+ does not declare.
      def normalize(data, klass = Expression)
        case data
        when ::Array then data.map { |v| normalize(v, klass) }
        when ::Hash
          ordered = klass.attributes.keys.map(&:to_s).select { |name| data.key?(name) && !data[name].nil? }
          undeclared = data.keys - klass.attributes.keys.map(&:to_s)
          raise Undeclared, "#{klass.name} does not declare #{undeclared.join(', ')}" unless undeclared.empty?

          ordered.to_h do |name|
            attribute = klass.attributes.fetch(name.to_sym)
            value = data[name]
            value = [value] if attribute.collection? && !value.is_a?(::Array)
            type = attribute.type
            [name, type.is_a?(Class) && type <= Lutaml::Model::Serializable ? normalize(value, type) : value]
          end
        else data
        end
      end
    end
  end
end
