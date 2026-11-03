# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "typed model construction" do
  M = Unicodemath::Model

  it "builds typed nodes from the declared attribute types" do
    frac = parse("a/b").expression.frac
    expect(frac).to be_a(M::Frac)
    expect(frac.numerator).to be_a(M::Expression)
    expect(frac.numerator.atom).to be_a(M::Atom)
    expect(frac.denominator.factor.atom.alphanumeric).to be_a(M::MathSymbol)
  end

  it "builds recursive and repeated structures" do
    table = parse("■(a&b@c&d)").expression.table
    expect(table.array).to be_a(M::ArrayNode)
    expect(table.array.trs.tr.tds.td.exp.factor.atom.alphanumeric.spelling).to eq("d")
    accents = parse("f′′(x)").expression.accents
    expect(accents).to all(be_a(M::Accents))
    expect(accents.first.prime_accent_symbols.first.literal.value).to eq("′′")
  end

  it "keeps the text of a capture that holds text instead of a node as the node's literal" do
    base = parse("x^2").expression.sup_exp.base
    expect(base.symbol).to be_a(M::SymbolNode)
    expect(base.symbol.literal.spelling).to eq("x")
  end

  it "keeps numbers as written with their decimal marker" do
    number = parse("3.14").expression.factor.decimal_number
    expect([number.whole.number, number.decimal, number.fractional.number]).to eq(%w[3 . 14])
    comma = parse("3,14", decimal: ",").expression.factor.decimal_number
    expect(comma.decimal).to eq(",")
    expect(parse("3,14", decimal: ",").decimal).to eq(",")
  end

  it "resolves symbols through the exported catalog" do
    expression = parse("\\alpha+β").expression
    alpha = expression.factor.ordinary_symbols
    expect([alpha.spelling, alpha.value, alpha.kind]).to eq(["alpha", "α", "symbol"])
    expect(expression.expr.operator.kind).to eq("symbol")
    paren = parse("(a)").expression.factor.intermediate_exp.open_paren.literal
    expect([paren.value, paren.kind]).to eq(["(", "paren"])
    unlisted = parse("a").expression.factor.atom.alphanumeric
    expect([unlisted.value, unlisted.kind]).to eq(%w[a unlisted])
  end

  it "keeps the label as a root field" do
    document = parse("E=mc^2#(1)")
    expect(document.label).to eq("(1)")
    expect(parse("a").label).to be_nil
  end

  it "reproduces the bound capture tree" do
    ["a/b", "∑_(i=1)^n i", "■(a&b@c&d)", "f′′(x)", "√(3&x)", "[a,b)", "x²+y₁", "✎(red&x)"].each do |input|
      expect(capture_tree_equal?(input)).to be(true), input
    end
  end

  it "reports a bound capture the model does not declare" do
    expect { M::CaptureTree.normalize({ "nonexistent" => "x" }) }
      .to raise_error(M::CaptureTree::Undeclared, /does not declare nonexistent/)
  end

  it "reports an attribute holding a value of another type" do
    node = M::Frac.new(mini_numerator: "bare text")
    expect { M::CaptureTree.dump(node) }.to raise_error(M::CaptureTree::Untyped, /Frac#mini_numerator/)
  end
end

RSpec.describe Unicodemath::Symbols do
  it "decodes character references of unlisted spellings" do
    expect(described_class.lookup("&#x1d400;")).to eq(["𝐀", "unlisted"])
    expect(described_class.lookup("&#65;b")).to eq(%w[Ab unlisted])
  end

  it "refuses a catalog of another format" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "s.json")
      File.write(path, JSON.generate("format" => "other", "symbols" => {}))
      expect { described_class.load(path) }.to raise_error(Unicodemath::ArtifactError, /format "other"/)
    end
  end
end
