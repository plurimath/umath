# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe UmathOracle::Canonical do
  def dump(value) = described_class.dump(value)

  it "keeps hash vs array, symbol vs string and nil vs missing apart" do
    expect(dump({ a: nil })).to eq("t" => "hash", "entries" => [[{ "t" => "sym", "v" => "a" }, { "t" => "nil" }]])
    expect(dump({ "a" => [] })["entries"][0]).to eq([{ "t" => "str", "v" => "a" }, { "t" => "array", "items" => [] }])
    expect(dump({})).to eq("t" => "hash", "entries" => [])
    expect(dump("")).not_to eq(dump([]))
  end

  it "keeps hash insertion order and array order" do
    expect(dump({ b: 1, a: 2 })["entries"].map { |k, _| k["v"] }).to eq(%w[b a])
    expect(dump([2, 1])["items"].map { |i| i["v"] }).to eq(%w[2 1])
  end

  it "stores invalid UTF-8 as exact bytes" do
    expect(dump("\xFF".b)).to eq("t" => "bytes", "b64" => "/w==")
  end

  it "keeps number text without float normalisation" do
    expect(dump(1.50)).to eq("t" => "float", "v" => "1.5")
    expect(dump(10)).to eq("t" => "int", "v" => "10")
  end

  it "records object class and instance variables in order" do
    klass = Class.new do
      def initialize
        @z = 1
        @a = "x"
      end
    end
    stub_const("Sample", klass)
    expect(dump(Sample.new)).to eq("t" => "obj", "class" => "Sample",
                                   "ivars" => [["@z", { "t" => "int", "v" => "1" }],
                                               ["@a", { "t" => "str", "v" => "x" }]])
  end

  it "records parser slices with text and both offsets" do
    slice = Class.new do
      def to_s = "é"
      def charpos = 3
      def bytepos = 4
      def offset = 3
    end
    stub_const("Parsanol::Slice", slice)
    expect(dump(Parsanol::Slice.new)).to eq("t" => "slice", "class" => "Parsanol::Slice",
                                            "text_kind" => "str", "v" => "é",
                                            "charpos" => 3, "bytepos" => 4, "offset" => 3)
  end

  it "marks cycles instead of recursing forever" do
    a = []
    a << a
    expect(dump(a)).to eq("t" => "array", "items" => [{ "t" => "cycle", "class" => "Array" }])
  end

  it "does not mark a value shared by two siblings as a cycle" do
    shared = [1]
    expect(dump([shared, shared])["items"].map { |i| i["t"] }).to eq(%w[array array])
  end

  it "scrubs object addresses from messages" do
    expect(described_class.scrub_message("#<Foo:0x00007f3a2b1c>")).to eq("#<Foo:0xADDR>")
  end
end
