# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/umath/schema"

RSpec.describe Umath::Schema do
  it "loads the checksum-verified complete declaration graph" do
    expect(described_class.bundle.fetch("models").length).to eq(75)
    expect(File.file?(described_class.bundle_path)).to be(true)
  end

  it "refuses changed declaration bytes" do
    Dir.mktmpdir("umath-schema-") do |directory|
      path = File.join(directory, "changed.json")
      File.binwrite(path, described_class.bundle_json + " ")
      stub_const("Umath::Schema::BUNDLE_PATH", path)
      expect { described_class.bundle_json }.to raise_error(Umath::Schema::ChecksumMismatch)
    end
  end
end
