# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe UnicodemathOracle::Inventory do
  def write(name, rows)
    path = File.join(@dir, name)
    File.write(path, { "schema" => UnicodemathOracle::INVENTORY_SCHEMA, "rows" => rows }.to_yaml)
    path
  end

  it "rejects the same id in two files" do
    a = write("a.yml", [{ "id" => "x", "input" => "1" }])
    b = write("b.yml", [{ "id" => "x", "input" => "2" }])
    expect { described_class.load([a, b]) }.to raise_error(UnicodemathOracle::Error, /duplicate inventory ids: x/)
  end

  it "rejects ids that are unsafe as file names" do
    a = write("a.yml", [{ "id" => "../x", "input" => "1" }])
    expect { described_class.load([a]) }.to raise_error(UnicodemathOracle::Error, /bad row id/)
  end

  it "rejects requested ids missing from the inventory" do
    inv = described_class.load([write("a.yml", [{ "id" => "x", "input" => "1" }])])
    expect { inv.select(%w[x y]) }.to raise_error(UnicodemathOracle::Error, /not in inventory: y/)
  end

  it "rejects an id requested twice" do
    inv = described_class.load([write("a.yml", [{ "id" => "x", "input" => "1" }])])
    expect { inv.select(%w[x x]) }.to raise_error(UnicodemathOracle::Error, /duplicate ids requested/)
  end

  it "decodes base64 inputs to exact bytes, including invalid UTF-8" do
    inv = described_class.load([write("a.yml", [{ "id" => "bad", "input_base64" => ["\xFFa".b].pack("m0") }])])
    expect(inv.rows["bad"]["input"].b).to eq("\xFFa".b)
  end

  it "fails the CLI with status 1 on an unknown id" do
    inventory = write_inventory(@dir, "x" => "ok")
    status, report, err = run_capture(@dir, inventory, "--ids", "x,nope")
    expect(status.exitstatus).to eq(1)
    expect(report).to be_nil
    expect(err).to match(/not in inventory: nope/)
  end

  it "ships a smoke inventory with the two smoke rows" do
    path = File.join(OracleSpecHelpers::ROOT, "corpora", "oracle", "inventory", "smoke.yml")
    expect(described_class.load([path]).rows.keys).to eq(%w[smoke-success smoke-refusal])
  end
end
