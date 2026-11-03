# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "oracle capture classification" do
  def capture_one(command, deadline: 5)
    inventory = write_inventory(@dir, "case" => command)
    status, report, err = run_capture(@dir, inventory, deadline: deadline)
    [status, report, row(@dir, "case"), err]
  end

  it "records a worker success as succeeded" do
    status, report, row, = capture_one("ok")
    expect(row["outcome"]).to eq("succeeded")
    expect(report["complete"]).to be(true)
    expect(status.exitstatus).to eq(0)
  end

  it "records a parse refusal as data, not as an incomplete capture" do
    status, report, row, = capture_one("refuse")
    expect(row["outcome"]).to eq("refused")
    expect(report["counts"]).to include("refused" => 1, "timed_out" => 0, "crashed" => 0)
    expect(status.exitstatus).to eq(0)
  end

  it "records an oracle exception as errored data" do
    _, report, row, = capture_one("error")
    expect(row["outcome"]).to eq("errored")
    expect(report["complete"]).to be(true)
  end

  it "times out a worker that runs past the real deadline" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, report, row, = capture_one("sleep:30", deadline: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(row["outcome"]).to eq("timed_out")
    expect(row["process"]["termsig"]).to eq(Signal.list["TERM"])
    expect(report["counts"]).to include("timed_out" => 1, "refused" => 0)
    expect(report["complete"]).to be(false)
    expect(status.exitstatus).to eq(2)
    expect(elapsed).to be < 15
  end

  it "classifies a signal death as crashed" do
    _, report, row, = capture_one("crash-signal")
    expect(row["outcome"]).to eq("crashed")
    expect(row["process"]["termsig"]).to eq(Signal.list["KILL"])
    expect(report["complete"]).to be(false)
  end

  it "classifies a non-zero exit as crashed" do
    _, _, row, = capture_one("crash-exit")
    expect(row["outcome"]).to eq("crashed")
    expect(row["process"]["exitstatus"]).to eq(3)
  end

  it "classifies a clean exit with a truncated result as crashed" do
    _, _, row, = capture_one("partial")
    expect(row["outcome"]).to eq("crashed")
    expect(row["detail"]).to match(/without a complete result/)
  end

  it "does not let a worker claim an incomplete outcome for itself" do
    _, _, row, = capture_one("bad-outcome")
    expect(row["outcome"]).to eq("crashed")
  end

  it "classifies closing the result pipe without an answer as crashed" do
    _, _, row, = capture_one("close-without-result")
    expect(row["outcome"]).to eq("crashed")
  end

  it "waits for exit after EOF instead of calling it a timeout" do
    status, report, row, = capture_one("eof-then-exit:1.5", deadline: 10)
    expect(row["outcome"]).to eq("succeeded")
    expect(report["timings"]["case"]["eof_before_exit"]).to be(true)
    expect(status.exitstatus).to eq(0)
  end

  it "still times out a worker that hangs after EOF" do
    _, _, row, = capture_one("eof-then-hang:30", deadline: 1)
    expect(row["outcome"]).to eq("timed_out")
  end
end
