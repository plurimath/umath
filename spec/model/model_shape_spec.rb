# frozen_string_literal: true

require_relative "spec_helper"

# The generated node classes against the normalized grammar: every capture
# holds one kind and never nil, and each is declared with the type of that
# kind (static shapes from grammars/unicodemath.normalized-rules.json under
# Parslet's flattening rules, computed by spec/model/support).
RSpec.describe "the generated model declarations" do
  let(:shapes) { ModelSpecHelpers.shapes }
  let(:captures) { shapes.captures }
  let(:symbol_class) { Unicodemath::Model::MathSymbol }
  let(:tree) { Unicodemath::Configuration::TREE_CAPTURE.to_s }

  # The generator's class rules (scripts/generate_model.rb): whole
  # expressions (25 or more keys) share Expression, the SHARED groups share
  # their class, any other capture has its own.
  def shared_classes
    { "MiniExpression" => %w[mini_expr mini_intermediate_exp sub_recursion_expr sub_recursions
                             sup_recursion_expr sup_recursions],
      "Paren" => %w[close_paren open_paren] }
  end

  def expression?(shape) = shape.kinds == Set[:hash] && shape.hash_keys.size >= 25

  def class_name(capture)
    shape = capture == tree ? shapes.root_shape : captures.fetch(capture)
    return "Expression" if expression?(shape)

    shared = shared_classes.find { |_, names| names.include?(capture) }&.first
    shared || { "array" => "ArrayNode", "symbol" => "SymbolNode", "root" => "RootNode" }.fetch(capture) do
      capture.split("_").map { |w| w[0].upcase + w[1..] }.join
    end
  end

  def symbol?(shape) = shape.kinds == Set[:hash] && shape.hash_keys == Set["spelling"]

  # capture name => [[class, attribute], ...] for every declaration.
  let(:declarations) do
    model_classes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |klass, acc|
      klass.attributes.each { |name, attr| acc[name.to_s] << [klass, attr] }
    end
  end

  it "gives every capture exactly one kind, never nil" do
    bad = captures.reject { |_, s| s.kinds.size == 1 && !s.kinds.include?(:nil) }
    expect(bad.transform_values { |s| s.kinds.to_a }).to be_empty
  end

  it "declares every capture with the type of its kind" do
    nested = captures.values.flat_map { |s| (s.hash_keys | s.array_keys).to_a }.uniq | shapes.root_shape.hash_keys.to_a
    nested.each do |capture|
      shape = captures.fetch(capture)
      uses = declarations.fetch(capture)
      types = uses.map { |_, attr| [attr.type, attr.collection?] }.uniq
      expect(types.size).to eq(1), "#{capture}: #{types.inspect}"
      type, collection = types.first
      case shape.kinds.first
      when :string then expect([type, collection]).to eq([Lutaml::Model::Type::String, false]), capture
      when :array
        expect([type.name, collection]).to eq(["Unicodemath::Model::#{class_name(capture)}Item", true]), capture
      when :hash
        expected = symbol?(shape) ? symbol_class.name : "Unicodemath::Model::#{class_name(capture)}"
        expect([type.name, collection]).to eq([expected, false]), capture
      end
    end
  end

  it "declares in each class exactly the keys its captures can hold" do
    expected = Hash.new { |h, k| h[k] = Set.new }
    (captures.to_a + [[tree, shapes.root_shape]]).each do |capture, shape|
      next if symbol?(shape) || shape.kinds.first == :string

      list = shape.kinds.first == :array
      keys = (list ? shape.array_keys : shape.hash_keys).to_a
      keys |= %w[value kind] if keys.include?("spelling")
      expected["#{class_name(capture)}#{'Item' if list}"].merge(keys)
    end
    expected.each do |name, keys|
      klass = Unicodemath::Model.const_get(name)
      expect(klass.attributes.keys.map(&:to_s).sort).to eq(keys.to_a.sort), name
    end
  end

  it "declares no class that no capture uses" do
    used = declarations.values.flatten(1).map { |_, attr| attr.type }.uniq
    expect(model_classes - used - [Unicodemath::Model::Document]).to be_empty
  end

  it "roots the document at the tree capture" do
    expect(Unicodemath::Model::Document.attributes[:expression].type).to eq(Unicodemath::Model::Expression)
  end
end
