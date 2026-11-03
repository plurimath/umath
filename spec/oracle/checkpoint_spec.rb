# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "oracle capture checkpoints" do
  let(:rows) do
    { "r1" => "ok", "r2" => "refuse", "r3" => "ok", "r4" => "error" }
  end

  it "resumes after a stop without redoing finished rows" do
    inventory = write_inventory(@dir, rows)
    status, report, = run_capture(@dir, inventory, "--max-attempts", "2")
    expect(status.exitstatus).to eq(2)
    expect(report).to include("stopped_early" => true, "attempted_this_run" => 2,
                              "complete" => false)
    expect(report["missing"]).to eq(%w[r3 r4])

    first = File.read(File.join(@dir, "out", "rows", "r1.json"))
    status, report, = run_capture(@dir, inventory)
    expect(status.exitstatus).to eq(0)
    expect(report).to include("reused" => 2, "attempted_this_run" => 2, "complete" => true,
                              "expected" => 4, "rows_found" => 4)
    expect(report["counts"]).to include("succeeded" => 2, "refused" => 1, "errored" => 1)
    expect(report["counts"].values.sum).to eq(report["expected"])
    expect(File.read(File.join(@dir, "out", "rows", "r1.json"))).to eq(first)
  end

  it "resumes after the supervisor is killed mid-row" do
    inventory = write_inventory(@dir, "a" => "ok", "b" => "sleep:30", "c" => "ok")
    cmd = [RbConfig.ruby, OracleSpecHelpers::CAPTURE, "--worker", OracleSpecHelpers::FAKE_WORKER,
           "--inventory", inventory, "--out", File.join(@dir, "out"), "--deadline", "60"]
    pid = Process.spawn(*cmd, err: File::NULL)
    a_row = File.join(@dir, "out", "rows", "a.json")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
    sleep 0.05 until File.file?(a_row) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 0.3
    Process.kill(:KILL, pid)
    Process.wait(pid)

    rows_dir = File.join(@dir, "out", "rows")
    expect(Dir.children(rows_dir).sort).to eq(["a.json"])

    File.write(inventory, File.read(inventory).sub("sleep:30", "ok"))
    status, report, = run_capture(@dir, inventory)
    expect(status.exitstatus).to eq(0)
    expect(report).to include("reused" => 1, "attempted_this_run" => 2, "complete" => true)
  end

  it "retries incomplete rows on resume instead of reusing them" do
    inventory = write_inventory(@dir, "slow" => "sleep:30")
    run_capture(@dir, inventory, deadline: 1)
    expect(row(@dir, "slow")["outcome"]).to eq("timed_out")

    File.write(inventory, File.read(inventory).sub("sleep:30", "ok"))
    status, report, = run_capture(@dir, inventory)
    expect(status.exitstatus).to eq(0)
    expect(report).to include("reused" => 0, "attempted_this_run" => 1)
    expect(row(@dir, "slow")["outcome"]).to eq("succeeded")
  end

  it "redoes a row whose request changed" do
    inventory = write_inventory(@dir, "x" => "ok")
    run_capture(@dir, inventory)
    File.write(inventory, File.read(inventory).sub("input: ok", "input: refuse"))
    _, report, = run_capture(@dir, inventory)
    expect(report).to include("reused" => 0, "attempted_this_run" => 1)
    expect(row(@dir, "x")["outcome"]).to eq("refused")
  end
end
