# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Umath native recursion limit" do
  before do
    skip "native extension unavailable" unless Umath::Engine.native_available?
    allow(Parsanol::Native).to receive(:_parse_handle_with_compatibility)
      .and_raise(RuntimeError, "Recursion limit exceeded: depth 1001 exceeds limit of 1000")
  end

  it "reruns on the Ruby engine under engine: :auto" do
    Umath.parse("x", engine: :auto)
    expect(Umath.last_engine).to eq(:ruby)
  end

  it "raises NestingTooDeep under engine: :native" do
    expect { Umath.parse("x", engine: :native) }
      .to raise_error(Umath::NestingTooDeep, /recursion limit/)
  end

  it "leaves engine: :ruby untouched" do
    Umath.parse("x", engine: :ruby)
    expect(Umath.last_engine).to eq(:ruby)
  end
end
