# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "the exported symbol catalog" do
  let(:doc) { JSON.parse(File.read(File.join(ArtifactSpecHelpers::ROOT, "data", "unicodemath-symbols.json"), encoding: "UTF-8")) }

  it "comes from the pinned oracle commit" do
    expect(doc["format"]).to eq("unicodemath-symbol-catalog/1")
    expect(doc.dig("oracle", "commit")).to eq("e7ab4a5186c9be96f62d670574bc2c72f9365ad4")
  end

  it "gives every spelling a Unicode value and a kind, in spelling order" do
    symbols = doc.fetch("symbols")
    expect(symbols.size).to eq(3282)
    expect(symbols.keys).to eq(symbols.keys.sort)
    expect(symbols.values.map { |e| e.keys.sort }.uniq).to eq([%w[kind value]])
    expect(symbols.values.map { |e| e["kind"] }.tally).to eq("symbol" => 3218, "paren" => 64)
    expect(symbols.values.map { |e| e["value"] }).to all(satisfy { |v| v.is_a?(String) && !v.empty? && v.valid_encoding? })
  end

  it "records the legacy resolution of common spellings" do
    symbols = doc.fetch("symbols")
    expect(symbols["&#x3b1;"]).to eq("value" => "α", "kind" => "symbol")
    expect(symbols["alpha"]).to eq("value" => "α", "kind" => "symbol")
    expect(symbols["&#x2211;"]).to eq("value" => "∑", "kind" => "symbol")
    expect(symbols["("]).to eq("value" => "(", "kind" => "paren")
  end
end
