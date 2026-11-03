# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Unicodemath::Preprocessor do
  def call(input)
    described_class.call(input).to_h
  end

  it "encodes everything outside printable ASCII and < > ' as hexadecimal entities" do
    expect(call("α<β>'x'")[:text]).to eq("&#x3b1;&#x3c;&#x3b2;&#x3e;&#x27;x&#x27;")
  end

  it "keeps & and \" unencoded" do
    expect(call("a&\"b\"")[:text]).to eq("a&\"b\"")
  end

  it "encodes control characters and strips surrounding spaces" do
    expect(call("  a\tb\n  ")[:text]).to eq("a&#x9;b&#xa;")
  end

  it "removes everything from the first comment opener to the last closer" do
    expect(call("a⫷x⫸+b⫷y⫸c")[:text]).to eq("ac")
  end

  it "folds double backslashes and turns \\u escapes into entities" do
    expect(call("a\\\\b")[:text]).to eq("a\\b")
    expect(call("\\u03B1+b")[:text]).to eq("&#x03B1;+b")
    # The legacy pattern takes up to five hex digits and then swallows up
    # to five more word characters.
    expect(call("\\u03B1abcdefg")[:text]).to eq("&#x03B1a;g")
  end

  it "splits a label off at the last #" do
    expect(call("a+b#(1)")).to eq(text: "a+b", label: "(1)", labeled: true)
    expect(call("a#b#c")).to eq(text: "a", label: "c", labeled: true)
    expect(call("a#")).to eq(text: "a", label: nil, labeled: false)
  end

  it "protects a # inside ✎(...)" do
    expect(call("✎(a#b)")).to eq(text: "&#x270e;(a#b)", label: nil, labeled: false)
    # The legacy pattern is greedy: it runs to the last ")", so a label
    # after the group is protected too.
    expect(call("✎(a#b)#(2)")).to eq(text: "&#x270e;(a#b)#(2)", label: nil, labeled: false)
  end

  it "reports no formula text for input without a formula part" do
    expect(call("")).to eq(text: nil, label: nil, labeled: false)
    expect(call("###")).to eq(text: nil, label: nil, labeled: false)
    expect(call("#b")).to eq(text: "", label: "b", labeled: true)
  end
end
