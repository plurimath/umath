# frozen_string_literal: true

require_relative "spec_helper"

# The node classes against the grammar: every capture the grammar can
# produce is declared, with a field kind that can hold every value the
# grammar can give it (static shapes from data/unicodemath-grammar.json
# under Parslet's flattening rules).
RSpec.describe "the model declarations" do
  let(:shapes) { ModelSpecHelpers.shapes }
  let(:node) { Unicodemath::Model::Node }
  let(:symbol) { Unicodemath::Model::MathSymbol }

  # capture name => [[class, attribute], ...] for every declaration.
  let(:declarations) do
    model_classes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |klass, acc|
      klass.attributes.each { |name, attr| acc[name.to_s] << [klass, attr] unless name == :literal }
    end
  end

  def model_type(attr)
    type = attr.type
    type.is_a?(Class) && type <= Lutaml::Model::Serializable ? type : nil
  end

  it "declares every capture that the grammar can place inside another" do
    nested = shapes.captures.values.flat_map { |s| (s.hash_keys | s.array_keys).to_a } | shapes.root_shape.hash_keys.to_a
    expect(nested - declarations.keys).to be_empty
    expect(declarations.keys - shapes.captures.keys).to be_empty
  end

  it "gives a capture the same type and collection flag wherever it is declared" do
    declarations.each do |capture, uses|
      kinds = uses.map { |_, attr| [attr.type, attr.collection?] }.uniq
      expect(kinds.size).to eq(1), "#{capture}: #{kinds.inspect}"
    end
  end

  it "types node captures as node classes and text captures as text or symbols" do
    declarations.each do |capture, uses|
      shape = shapes.captures.fetch(capture)
      attr = uses.first.last
      structured = shape.kinds.intersect?(Set[:hash, :array])
      type = model_type(attr)
      if structured
        expect(type).to be < node, capture
      else
        expect(type.nil? || type == symbol).to be(true), capture
      end
      expect(attr.collection?).to eq(shape.kinds.include?(:array)), capture
    end
  end

  it "declares in each node class every capture its captures' values can contain" do
    declarations.each do |capture, uses|
      klass = model_type(uses.first.last)
      next unless klass && klass < node

      shape = shapes.captures.fetch(capture)
      missing = (shape.hash_keys | shape.array_keys).to_a.map(&:to_sym) - klass.attributes.keys
      expect(missing).to be_empty, "#{klass.name} (capture #{capture}) lacks #{missing.inspect}"
      if shape.kinds.include?(:string)
        expect(klass.attributes).to include(:literal), "#{klass.name} (capture #{capture}) can receive text"
      end
    end
  end

  it "declares in Expression every capture of the tree's root" do
    missing = shapes.root_shape.hash_keys.to_a.map(&:to_sym) - Unicodemath::Model::Expression.attributes.keys
    expect(missing).to be_empty
  end

  it "declares no node class that no capture uses" do
    used = declarations.values.flatten(1).filter_map { |_, attr| model_type(attr) }.uniq
    expect(model_classes - used - [Unicodemath::Model::Expression]).to be_empty
  end
end
