# frozen_string_literal: true

require_relative "spec_helper"

# Replays legacy oracle rows (written by scripts/oracle/capture.rb against
# Plurimath at the pinned commit) through the internal raw-tree boundary and
# requires the same preprocessing, the same raw tree in canonical tagged form
# (keys, order, slice text and offsets) after removing the wrappers the shape
# normalization added (scripts/unwrap.rb) and, for refusals, the same
# position.
#
# By default it replays the committed sample in fixtures/oracle/. To
# regenerate those rows (heavy; up to minutes per row):
#
#   bundle exec ruby scripts/oracle/capture.rb --oracle ORACLE_CHECKOUT \
#     --inventory spec/parser/fixtures/oracle/inventory/sample.yml --out OUT
#   cp OUT/rows/*.json spec/parser/fixtures/oracle/rows/
#
# UMATH_ORACLE_INVENTORY and UMATH_ORACLE_ROWS point it at another
# capture (CI's full replay). Every Ruby-engine row runs; the native engine,
# which takes seconds per row, runs on the ids in UMATH_NATIVE_IDS
# ("all" for every row; by default a fixed few).
RSpec.describe "raw-tree parity with the legacy oracle" do
  inventory_path = ENV.fetch("UMATH_ORACLE_INVENTORY",
                             File.join(ParserSpecHelpers::FIXTURES, "inventory", "sample.yml"))
  rows_dir = ENV.fetch("UMATH_ORACLE_ROWS", File.join(ParserSpecHelpers::FIXTURES, "rows"))
  inventory = YAML.safe_load_file(inventory_path).fetch("rows")
  native_ids = ENV.fetch("UMATH_NATIVE_IDS",
                         "unicode-external-001,unicode-external-033,unicode-external-041")
  native_ids = case native_ids
               when "all" then inventory.map { |r| r["id"] }
               when "none" then []
               else native_ids.split(",")
               end

  it "has one complete oracle row per inventory id" do
    ids = inventory.map { |r| r["id"] }
    expect(ids.uniq.size).to eq(ids.size)
    files = Dir[File.join(rows_dir, "*.json")].map { |f| File.basename(f, ".json") }
    expect(files.sort).to eq(ids.sort)
    expect(native_ids - ids).to be_empty
    ids.each do |id|
      row = JSON.parse(File.read(File.join(rows_dir, "#{id}.json")), max_nesting: false)
      expect(%w[succeeded refused errored]).to include(row["outcome"]), id
    end
  end

  inventory.each do |item|
    id = item["id"]
    engines = native_ids.include?(id) ? %i[ruby native] : %i[ruby]
    engines.each do |engine|
      it "reproduces #{id} on the #{engine} engine" do
        skip "native engine not available" if engine == :native && !Umath::Engine.native_available? && !native_required?

        row = JSON.parse(File.read(File.join(rows_dir, "#{id}.json")), max_nesting: false)
        boundaries = row.dig("result", "boundaries")
        options = boundaries.dig("input", "options")
        decimal = ParserSpecHelpers::LOCALE_DECIMALS.fetch(options["locale"])
        input = item.key?("input_base64") ? item["input_base64"].unpack1("m0").force_encoding(Encoding::UTF_8) : item["input"].to_s
        expect(canonical_string(input)).to eq(boundaries.dig("input", "text"))
        expect_parity(boundaries["preprocess"], boundaries["raw"], input, decimal, engine)
      end
    end
  end

  def expect_parity(pre, raw, input, decimal, engine)
    if pre["status"] == "error"
      expect_preprocess_error(pre["error"], input, decimal, engine)
      return
    end

    case raw["status"]
    when "ok"
      result = Umath::RawParser.parse(input, decimal: decimal, engine: engine)
      expect_preprocessing(pre, result)
      expect(canonical(legacy(result.tree))).to eq(raw["tree"])
      expect(result.engine).to eq(engine)
    when "refused"
      expected = raw.dig("error", "message")[/at line 1 char (\d+)\.\z/, 1]
      expect(expected).not_to be_nil, "oracle refusal without a line-1 position"
      expect { Umath::RawParser.parse(input, decimal: decimal, engine: engine) }
        .to raise_error(Umath::ParseError) { |e|
          expect(e).not_to be_a(Umath::NestingTooDeep)
          expect(canonical_string(e.input)).to eq(pre["text"])
          expect(e.char_offset).to eq(expected.to_i - 1)
        }
    when "error"
      expect(raw.dig("error", "class")).to eq("SystemStackError")
      expect { Umath::RawParser.parse(input, decimal: decimal, engine: engine) }
        .to raise_error(Umath::NestingTooDeep)
    else
      raise "unexpected raw status #{raw['status'].inspect}"
    end
  end

  def expect_preprocessing(pre, result)
    expect(canonical_string(result.text)).to eq(pre["text"])
    expect(result.labeled).to eq(pre["label_defined"])
    expect(canonical(result.label)).to eq(pre["label"]) if pre["label_defined"]
  end

  # The legacy preprocessing fails on invalid UTF-8 (ArgumentError) and on
  # input without a formula part (NoMethodError on nil).
  def expect_preprocess_error(error, input, decimal, engine)
    case error["class"]
    when "ArgumentError"
      expect { Umath::RawParser.parse(input, decimal: decimal, engine: engine) }
        .to raise_error(ArgumentError, /UTF-8/)
    when "NoMethodError"
      result = Umath::RawParser.parse(input, decimal: decimal, engine: engine)
      expect(result.text).to be_nil
      expect(result.tree).to be_nil
    else
      raise "unexpected preprocessing error #{error['class']}"
    end
  end
end
