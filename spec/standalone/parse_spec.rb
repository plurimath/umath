# frozen_string_literal: true

require "tmpdir"
require "unicodemath"

# The public API: Unicodemath.parse returns the typed model, standalone.
RSpec.describe "Unicodemath.parse" do
  def parse(input, **options)
    Unicodemath.parse(input, engine: :ruby, **options)
  end

  it "returns the typed document without loading Plurimath" do
    document = parse("a/b")
    expect(document).to be_a(Unicodemath::Model::Document)
    expect(document.expression.frac).to be_a(Unicodemath::Model::Frac)
    expect(document.decimal).to eq(".")
    expect(defined?(Plurimath)).to be_nil
    expect($LOADED_FEATURES.grep(%r{/plurimath[/.]})).to be_empty
  end

  it "serializes the document" do
    hash = parse("a+b").to_hash
    expect(hash.dig("expression", "expr", "operator")).to eq("spelling" => "+", "value" => "+", "kind" => "symbol")
  end

  it "records the engine" do
    parse("a")
    expect(Unicodemath.last_engine).to eq(:ruby)
  end

  it "parses on the native engine where it is available" do
    skip "native engine not available" unless Unicodemath::Engine.native_available? || ENV["UNICODEMATH_REQUIRE_NATIVE"] == "1"

    native = Unicodemath.parse("a/b", engine: :native)
    expect(Unicodemath.last_engine).to eq(:native)
    expect(native.to_hash).to eq(parse("a/b").to_hash)
  end

  describe "refusals" do
    it "reports positions in the caller's text, not the entity-encoded grammar input" do
      expect { parse("α)") }.to raise_error(Unicodemath::ParseError) { |e|
        expect([e.char_offset, e.byte_offset, e.input]).to eq([1, 2, "α)"])
      }
      expect { parse("αβγ+)") }.to raise_error(Unicodemath::ParseError) { |e|
        expect([e.char_offset, e.byte_offset]).to eq([4, 7])
      }
    end

    it "maps positions after a removed comment and across lines" do
      expect { parse("a⫷c⫸+)") }.to raise_error(Unicodemath::ParseError) { |e|
        expect(e.input[e.char_offset]).to eq(")")
        expect(e.input.byteslice(e.byte_offset, 1)).to eq(")")
      }
    end

    it "refuses input without a formula (the legacy facade raises NoMethodError)" do
      ["", "#", "###"].each do |input|
        expect { parse(input) }.to raise_error(Unicodemath::ParseError) { |e|
          expect([e.char_offset, e.byte_offset, e.input]).to eq([0, 0, input])
        }
      end
    end

    it "refuses an empty formula before a label" do
      expect { parse("#b") }.to raise_error(Unicodemath::ParseError) { |e| expect(e.char_offset).to eq(0) }
    end

    it "classifies input too deep for the engine" do
      expect { parse("#{'(' * 150}x#{')' * 150}") }.to raise_error(Unicodemath::NestingTooDeep) { |e|
        expect(e.byte_offset).to be_nil
        expect(e.input).to start_with("(((")
      }
    end
  end

  describe "arguments" do
    it "rejects invalid input, decimal markers and engines" do
      expect { parse(1) }.to raise_error(ArgumentError, /must be a String/)
      expect { parse("a\xFF".dup.force_encoding("UTF-8")) }.to raise_error(ArgumentError, /not valid UTF-8/)
      expect { parse("1", decimal: ";") }.to raise_error(ArgumentError, /unsupported decimal marker/)
      expect { Unicodemath.parse("a", engine: :fast) }.to raise_error(ArgumentError, /unknown engine/)
    end
  end
end

RSpec.describe Unicodemath::SourceMap do
  # The map's text must be the preprocessed text exactly.
  it "reproduces the preprocessor's text" do
    inputs = ["a+b", "α<β>'x'", "  a\t+\nb  ", "a⫷x⫸+b⫷y⫸c", "\\u03B1abcdefg", "a\\\\b", "✎(a#b)#(2)",
              "a#b#c", "x\"replacement\"y", "a&#x26;b", "𝐀+ℂ", " #x"]
    random = Random.new(541)
    alphabet = ["a", "#", "✎", "(", ")", "⫷", "⫸", "\\", "u", "1", "&", "\"", " ", "α", "\n", "x"]
    inputs += Array.new(500) { Array.new(random.rand(1..12)) { alphabet.sample(random: random) }.join }
    inputs.each do |input|
      pre = Unicodemath::Preprocessor.call(input)
      next if pre.text.nil?

      expect(described_class.build(input).text).to eq(pre.text), input.inspect
    end
  end
end
