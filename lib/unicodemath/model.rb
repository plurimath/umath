# frozen_string_literal: true

require "lutaml/model"

module Unicodemath
  # The typed UnicodeMath language model, declared with LutaML Model.
  #
  # Unicodemath.parse returns a Model::Document. Its tree is built by
  # lutaml-model from the declared attribute types (Document.new on the
  # grammar's bound tree, see Parser); no code here walks the parse tree.
  # The node classes in model/nodes.rb are generated from the normalized
  # grammar's capture shapes (scripts/generate_model.rb), one class per
  # capture; see docs/model-contract.adoc.
  module Model
    # The root: one parsed UnicodeMath formula.
    #
    # +expression+ is the formula's tree, nil for input without a formula
    # (empty, or only "#" label separators). +label+ is the equation label,
    # the text after the last "#" (nil when the input has none; the legacy
    # facade rule). +decimal+ is the decimal marker the input was parsed
    # with; numbers keep their digits and marker as written.
    class Document < Lutaml::Model::Serializable
      attribute :expression, "Unicodemath::Model::Expression"
      attribute :label, :string
      attribute :decimal, :string
    end
  end
end

require_relative "model/nodes"
