# frozen_string_literal: true

module Umath
  module Model
    # Builds the typed tree from the bound model data (Hashes, Arrays and
    # Strings with String keys).
    #
    # The result is the tree that Document.new builds from the same data:
    # equal nodes, the same attribute values and the same default marks.
    # Document.new walks every declared attribute of every node to seed
    # its default, and Expression alone declares over a hundred, so that
    # walk was most of the time Umath.parse spent outside the grammar.
    # Here each node is allocated with its defaults already seeded
    # (lutaml-model's allocate_for_walk) and only the attributes present
    # in the data are written. Without allocate_for_walk (lutaml-model
    # releases before it) the tree is built by Document.new.
    #
    # Internal.
    module Builder
      @plans = {}
      ABSENT = Object.new.freeze

      module_function

      def document(expression, label:, decimal:)
        data = { "expression" => expression, "label" => label, "decimal" => decimal }
        return Document.new(expression: expression, label: label, decimal: decimal) unless walk_seed?

        node(Document, data)
      end

      def walk_seed?
        Document.respond_to?(:allocate_for_walk)
      end

      def node(klass, data)
        instance = klass.allocate_for_walk
        plan(klass).each do |name, symbol, writer, type, collection|
          value = data.fetch(name) { data.fetch(symbol, ABSENT) }
          next if value.equal?(ABSENT)

          instance.public_send(writer, value(value, type, collection))
        end
        instance
      end

      def value(value, type, collection)
        return value unless type

        if collection && value.is_a?(::Array)
          value.map { |item| item.is_a?(::Hash) ? node(type, item) : item }
        elsif !collection && value.is_a?(::Hash)
          node(type, value)
        else
          value
        end
      end

      # [String name, Symbol name, writer, model class or nil,
      # collection?] per declared attribute of +klass+, in declaration
      # order. Document.new reads String or Symbol keys; so does this.
      def plan(klass)
        @plans[klass] ||= klass.attributes.map do |name, attribute|
          type = attribute.type
          model = type if type.is_a?(Class) && type < Lutaml::Model::Serializable
          [name.to_s, name.to_sym, :"#{name}=", model, attribute.collection?].freeze
        end.freeze
      end

      private_class_method :walk_seed?, :node, :value, :plan
    end
  end
end
