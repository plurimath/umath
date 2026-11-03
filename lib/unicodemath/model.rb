# frozen_string_literal: true

require "lutaml/model"

module Unicodemath
  # The typed UnicodeMath language model, declared with LutaML Model.
  #
  # Unicodemath.parse returns a Model::Document. Its tree is built by
  # lutaml-model from the declared attribute types (Document.new on the
  # grammar's bound tree, see Parser); no code here walks the parse tree.
  # The node classes follow the grammar's captures one to one; see
  # docs/model-contract.adoc for the rules and the field inventory.
  module Model
    # Base of every node class.
    #
    # A capture whose value is usually a node can also hold plain text (the
    # grammar matched no inner capture). Classes that can receive text
    # declare a +literal+ attribute and keep the text there, so every
    # attribute holds a value of its declared type.
    class Node < Lutaml::Model::Serializable
      # lutaml-model calls cast for a non-Hash value of a model-typed
      # attribute; text becomes the node's literal.
      def self.cast(value)
        return value unless value.is_a?(::String) && attributes.key?(:literal)

        new(literal: value)
      end
    end

    # A symbol token: an operator, relation, letter, paren or other
    # character the legacy transform resolves through Plurimath's symbol
    # catalog.
    #
    # +spelling+ is the token as the grammar matched it, in the grammar
    # input (entity-encoded: "&#x3b1;" for "α", "alpha" for "\alpha").
    # +value+ is the Unicode text it stands for and +kind+ its catalog kind:
    # "symbol", "paren", or "unlisted" when the catalog has no entry (the
    # legacy transform then keeps the spelling as a plain symbol; +value+ is
    # the spelling with its character references decoded). Construction
    # fills only +spelling+; Symbols.resolve fills the rest.
    class MathSymbol < Lutaml::Model::Serializable
      attribute :spelling, :string
      attribute :value, :string
      attribute :kind, :string, values: %w[symbol paren unlisted]

      def self.cast(value)
        value.is_a?(::String) ? new(spelling: value) : value
      end
    end

    # The root: one parsed UnicodeMath formula.
    #
    # +expression+ is the formula's tree. +label+ is the equation label,
    # the text after the last "#" (nil when the input has none; the legacy
    # facade rule). +decimal+ is the decimal marker the input was parsed
    # with; numbers keep their digits and marker as written
    # (DecimalNumber).
    class Document < Lutaml::Model::Serializable
      attribute :expression, "Unicodemath::Model::Expression"
      attribute :label, :string
      attribute :decimal, :string
    end
  end
end

require_relative "model/nodes"
require_relative "model/capture_tree"
