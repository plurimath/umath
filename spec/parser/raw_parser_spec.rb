# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Unicodemath::RawParser do
  def parse(input, **opts)
    described_class.parse(input, engine: :ruby, **opts)
  end

  it "returns the normalized tree for a + b, and the legacy tree after unwrap" do
    tree = parse("a+b").tree
    expect(tree.keys).to eq(%i[factor expr])
    expect(tree.dig(:expr, :operator, :spelling).to_s).to eq("+")
    expect(tree.dig(:expr, :operator, :spelling)).to be_a(Parsanol::Slice)
    expect(legacy(tree).dig(:expr, :operator)).to be_a(Parsanol::Slice)
    expect(legacy(tree).dig(:expr, :operator).to_s).to eq("+")
  end

  it "keeps slice offsets in the grammar input" do
    tree = parse("α+b").tree
    slices = []
    walk = lambda do |node|
      case node
      when Hash then node.each_value(&walk)
      when Array then node.each(&walk)
      when Parsanol::Slice then slices << node
      end
    end
    walk.call(tree)
    expect(slices.map { |s| [s.to_s, s.offset] }).to include(["+", 7])
  end

  it "selects the grammar entry by decimal marker" do
    # "," and "." are decimal separators in every entry; the Arabic marker
    # only in its own.
    arabic = "1٫5"
    expect(parse(arabic, decimal: "٫").tree.to_s).to include("decimal_number")
    expect(parse(arabic).tree.to_s).not_to include("decimal_number")
  end

  it "does not load Plurimath" do
    parse("a")
    expect($LOADED_FEATURES.grep(%r{/plurimath[/.]})).to be_empty
    expect(defined?(Plurimath)).to be_nil
  end

  describe "arguments" do
    it "rejects non-String input" do
      expect { parse(12) }.to raise_error(ArgumentError, /must be a String/)
    end

    it "rejects invalid UTF-8" do
      expect { parse("a\xFF".dup.force_encoding("UTF-8")) }.to raise_error(ArgumentError, /not valid UTF-8/)
    end

    it "transcodes other encodings" do
      expect(parse("\xE9".dup.force_encoding("ISO-8859-1")).text).to eq("&#xe9;")
    end

    it "rejects an unsupported decimal marker" do
      expect { parse("1", decimal: ";") }.to raise_error(ArgumentError, /unsupported decimal marker/)
    end

    it "rejects an unknown engine" do
      expect { described_class.parse("a", engine: :fast) }.to raise_error(ArgumentError, /unknown engine/)
    end
  end

  describe "refusals" do
    it "raises ParseError with offsets into the grammar input" do
      expect { parse("α)") }.to raise_error(Unicodemath::ParseError) { |e|
        expect(e.input).to eq("&#x3b1;)")
        expect([e.char_offset, e.byte_offset]).to eq([7, 7])
      }
    end
  end

  describe "engines" do
    it "records the engine that ran" do
      parse("a")
      expect(Unicodemath::Engine.last_engine).to eq(:ruby)
    end

    it "raises EngineUnavailable for :native without the extension" do
      allow(Unicodemath::Engine).to receive(:native_available?).and_return(false)
      expect { described_class.parse("a", engine: :native) }.to raise_error(Unicodemath::EngineUnavailable)
    end

    it "uses Ruby under :auto without the extension" do
      allow(Unicodemath::Engine).to receive(:native_available?).and_return(false)
      expect(described_class.parse("a", engine: :auto).engine).to eq(:ruby)
    end

    it "refuses deep input on native off the main thread, and reruns it on Ruby under :auto" do
      skip "native engine not available" unless Unicodemath::Engine.native_available? || native_required?

      deep = "#{'(' * 30}a#{')' * 30}"
      Thread.new do
        expect { described_class.parse(deep, engine: :native) }.to raise_error(Unicodemath::NestingTooDeep)
        expect(Unicodemath::Engine.last_engine).to eq(:native)
        expect(described_class.parse(deep, engine: :auto).engine).to eq(:ruby)
      end.join
    end

    it "turns an exhausted Ruby stack into NestingTooDeep" do
      deep = "#{'(' * 400}a#{')' * 400}"
      expect { parse(deep) }.to raise_error(Unicodemath::NestingTooDeep) { |e|
        expect([e.byte_offset, e.char_offset]).to eq([nil, nil])
      }
    end
  end

  describe "the declared bindings" do
    it "carry the parse shape's tree unchanged" do
      loaded = Unicodemath.artifacts
      shape = loaded.parse.root_atom("dot").parse("a/b", compatibility: :parslet)
      bound = loaded.bindings.apply("dot", shape)
      expect(bound.keys).to eq(%i[unicodemath_tree model])
      expect(bound[:unicodemath_tree]).to equal(shape[:unicodemath_tree])
      expect(canonical(parse("a/b").tree)).to eq(canonical(shape[:unicodemath_tree]))
    end

    it "carry the same tree as plain data for the model" do
      result = parse("a/b")
      expect(result.model_data).to eq(
        "frac" => { "numerator" => { "atom" => { "alphanumeric" => { "spelling" => "a" } } },
                    "denominator" => { "factor" => { "atom" => { "alphanumeric" => { "spelling" => "b" } } } } },
      )
    end
  end
end
