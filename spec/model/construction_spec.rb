# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "typed model construction" do
  M = Umath::Model

  it "builds typed nodes from the declared attribute types" do
    frac = parse("a/b").expression.frac
    expect(frac).to be_a(M::Frac)
    expect(frac.numerator).to be_a(M::Expression)
    expect(frac.numerator.atom).to be_a(M::Atom)
    expect(frac.denominator.factor.atom.alphanumeric).to be_a(M::MathSymbol)
  end

  it "builds recursive and repeated structures" do
    tds = parse("■(a&b@c&d)").expression.table.array.trs.tr
    expect(tds).to be_a(M::Tr)
    primes = parse("f′′(x)").expression.accents.prime_accent_symbols
    expect(primes).to all(be_a(M::PrimeAccentSymbolsItem))
    expect(primes.map(&:value)).to eq(%w[′ ′])
  end

  it "captures the text of a symbol node as its spelling" do
    base = parse("x^2").expression.sup_exp.base
    expect(base.symbol).to be_a(M::SymbolNode)
    expect([base.symbol.spelling, base.symbol.value, base.symbol.kind]).to eq(%w[x x unlisted])
  end

  it "keeps numbers as written with their decimal marker" do
    number = parse("3.14").expression.factor.decimal_number
    expect([number.whole.number, number.decimal, number.fractional.number]).to eq(%w[3 . 14])
    comma = parse("3,14", decimal: ",")
    expect(comma.expression.factor.decimal_number.decimal).to eq(",")
    expect(comma.decimal).to eq(",")
  end

  it "resolves symbols through the exported catalog" do
    expression = parse("\\alpha+β").expression
    alpha = expression.factor.ordinary_symbols
    expect([alpha.spelling, alpha.value, alpha.kind]).to eq(["alpha", "α", "symbol"])
    expect(expression.expr.operator.kind).to eq("symbol")
    paren = parse("(a)").expression.factor.intermediate_exp.open_paren
    expect([paren.spelling, paren.value, paren.kind]).to eq(["(", "(", "paren"])
    unlisted = parse("a").expression.factor.atom.alphanumeric
    expect([unlisted.value, unlisted.kind]).to eq(%w[a unlisted])
  end

  it "keeps the label as a root field" do
    document = parse("E=mc^2#(1)")
    expect(document.label).to eq("(1)")
    expect(parse("a").label).to be_nil
  end

  it "holds exactly the bound tree" do
    ["a/b", "∑_(i=1)^n i", "■(a&b@c&d)", "f′′(x)", "√(3&x)", "[a,b)", "x²+y₁", "✎(red&x)"].each do |input|
      expect(lossless?(input)).to be(true), input
    end
  end

  it "reports an attribute holding a value of another type" do
    node = M::Frac.new
    node.instance_variable_set(:@numerator, "bare text")
    expect { UmathModelTree.dump(node) }.to raise_error(TypeError, /Frac#numerator/)
  end
end

RSpec.describe Umath::Symbols do
  it "decodes character references of unlisted spellings" do
    expect(described_class.lookup("&#x1d400;")).to eq(["𝐀", "unlisted"])
    expect(described_class.lookup("&#65;b")).to eq(%w[Ab unlisted])
  end

  it "refuses a catalog of another format" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "s.json")
      File.write(path, JSON.generate("format" => "other", "symbols" => {}))
      expect { described_class.load(path) }.to raise_error(Umath::ArtifactError, /format "other"/)
    end
  end
end
