# frozen_string_literal: true

require "stringio"
require_relative "../../scripts/utn28_coverage"

# scripts/utn28_coverage.rb: the status of a few constructs from their rows,
# and the committed coverage table of docs/unicodemath.adoc being current.
# Needs the pinned plurimath-testsuite checkout at tmp/testsuite.
RSpec.describe Utn28Coverage do
  before(:all) do
    unless File.directory?(File.join(Utn28Coverage::DEFAULT_TESTSUITE, ".git"))
      skip "no plurimath-testsuite checkout at tmp/testsuite"
    end

    @mapping = Utn28Coverage.load_mapping
    suite, = Utn28Coverage.testsuite_rows(Utn28Coverage::DEFAULT_TESTSUITE, UmathReplayCorpus::DEFAULT_PIN)
    @rows = (Utn28Coverage.corpus_rows + suite).to_h { |r| [r.id, r] }
  end

  def construct(name)
    @mapping.fetch("constructs").find { |c| c["name"] == name } || raise("no construct #{name}")
  end

  def results(*ids)
    ids.to_h { |id| [id, Utn28Coverage.evaluate(@rows.fetch(id))] }
  end

  it "reads a fraction row as accepted and a trailing slash as refused" do
    expect(results("model-fraction", "unicode-lone-slash.model"))
      .to eq("model-fraction" => "accepted", "unicode-lone-slash.model" => "refused")
  end

  it "calls a construct with matching rows covered, whatever its incomplete rows" do
    fraction = { "name" => "Fraction", "rows" => ["model-fraction"], "malformed" => ["unicode-lone-slash.model"] }
    expect(Utn28Coverage.classify(fraction, results("model-fraction", "unicode-lone-slash.model"))).to eq("covered")
  end

  it "calls the alignment mark outside a matrix refused" do
    alignment = construct("Alignment mark `&` outside a matrix, `a&=b`")
    ids = alignment.values_at("refused", "malformed").flatten
    expect(ids).to include("unicode-ampersand-operator.model")
    expect(Utn28Coverage.classify(alignment, results(*ids))).to eq("refused")
  end

  it "calls a construct with no rows untested" do
    expect(Utn28Coverage.classify(construct("Equation array `█` (`\\eqarray`)"), {})).to eq("untested")
  end

  it "rejects a refused row listed as a row that must parse" do
    wrong = { "name" => "Fraction", "rows" => ["unicode-lone-slash.model"] }
    expect { Utn28Coverage.classify(wrong, results("unicode-lone-slash.model")) }
      .to raise_error(Utn28Coverage::Error, /listed under rows but is refused/)
  end

  it "finds docs/unicodemath.adoc current (--check)" do
    out = StringIO.new
    expect(Utn28Coverage.run(["--check"], out: out)).to eq(0)
    expect(out.string).to match(/\A\d+ constructs: covered=\d+ refused=\d+ untested=\d+\n\z/)
  end
end
