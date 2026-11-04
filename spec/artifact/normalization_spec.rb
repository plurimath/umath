# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../../scripts/unicodemath_shapes"
require_relative "../../scripts/unwrap"

# The capture-shape normalization (shared rules plus the UnicodeMath ones)
# and the test-only unwrap, on small hand-written rule sets.
RSpec.describe UnicodemathShapes do
  def str(s) = { "str" => s }
  def cap(name, node) = { "as" => name, "of" => node }

  it "wraps a text alternative of a node slot, so the capture holds one kind" do
    rules = { "r" => cap("x", { "alt" => [cap("y", str("a")), str("b")] }) }
    norm = described_class.new(rules).run
    expect(norm.rules["r"]).to eq(cap("x", { "alt" => [cap("y", str("a")), cap("literal", str("b"))] }))
    expect(norm.bad_captures).to be_empty
  end

  it "captures the text of a symbol capture as spelling" do
    norm = described_class.new({ "r" => cap("op", str("+")) }, symbols: ["op"]).run
    expect(norm.rules["r"]).to eq(cap("op", cap("spelling", str("+"))))
  end

  it "refuses a symbol capture that the grammar does not have" do
    expect { described_class.new({ "r" => cap("op", str("+")) }, symbols: ["other"]).run }
      .to raise_error(/not in the grammar: other/)
  end

  it "keeps the keys of a capture nested in a capture of the same name" do
    rules = { "r" => cap("x", { "seq" => [cap("x", cap("a", str("1"))), cap("b", str("2"))] }) }
    expect(described_class.new(rules, normalized: true).solve["x"].hash_keys.to_a.sort).to eq(%w[a b x])
  end

  it "reports a capture that holds nil" do
    norm = described_class.new({ "r" => cap("x", { "look" => str("a") }) }, normalized: true)
    expect(norm.bad_captures).to eq(["x (nil)"])
  end

  it "reports a sequence with two hash parts after a list wrapper" do
    list = cap("list", { "rep" => cap("i", str("a")), "min" => 1 })
    rules = { "r" => { "seq" => [list, cap("a", str("b")), cap("b", str("c"))] } }
    norm = described_class.new(rules, normalized: true)
    expect(norm.list_tails).to eq(["in r (2 parts)"])
    one = described_class.new({ "r" => { "seq" => [list, cap("a", str("b"))] } }, normalized: true)
    expect(one.list_tails).to be_empty
  end
end

RSpec.describe UnicodemathUnwrap do
  it "removes wrappers as legacy folded the parts" do
    table = { "literal" => "text", "spelling" => "text", "empty" => "empty", "list" => "list", "present" => "nil" }
    expect(described_class.call({ x: { literal: "b" } }, table)).to eq(x: "b")
    expect(described_class.call({ op: { spelling: "+" } }, table)).to eq(op: "+")
    expect(described_class.call({ x: { empty: "" } }, table)).to eq(x: "")
    expect(described_class.call({ x: { a: "1", list: [{ i: "2" }] } }, table)).to eq(x: [{ a: "1" }, { i: "2" }])
    expect(described_class.call({ x: { present: "" } }, table)).to eq(x: nil)
  end

  it "reads the committed wrapper table" do
    expect(described_class.wrappers).to include("literal" => "text", "spelling" => "text", "list" => "list")
  end
end
