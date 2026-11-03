# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../scripts/oracle/capture"

module OracleSpecHelpers
  ROOT = File.expand_path("../..", __dir__)
  CAPTURE = File.join(ROOT, "scripts", "oracle", "capture.rb")
  FAKE_WORKER = File.join(__dir__, "fixtures", "fake_worker.rb")

  # Writes an inventory whose inputs are commands for the fake worker.
  def write_inventory(dir, rows)
    path = File.join(dir, "inventory.yml")
    doc = { "schema" => UnicodemathOracle::INVENTORY_SCHEMA,
            "rows" => rows.map { |id, input| { "id" => id, "input" => input } } }
    File.write(path, doc.to_yaml)
    path
  end

  # Runs the real capture CLI in a child process against the fake worker.
  def run_capture(dir, inventory, *args, deadline: 5)
    cmd = [RbConfig.ruby, CAPTURE, "--worker", FAKE_WORKER, "--inventory", inventory,
           "--out", File.join(dir, "out"), "--deadline", deadline.to_s, *args]
    _out, err, status = Open3.capture3(*cmd)
    report_path = File.join(dir, "out", "report.json")
    report = File.file?(report_path) ? JSON.parse(File.read(report_path)) : nil
    [status, report, err]
  end

  def row(dir, id)
    JSON.parse(File.read(File.join(dir, "out", "rows", "#{id}.json")))
  end
end

RSpec.configure do |config|
  config.include OracleSpecHelpers
  config.around do |example|
    Dir.mktmpdir("unicodemath-oracle") do |dir|
      @dir = dir
      example.run
    end
  end
end
