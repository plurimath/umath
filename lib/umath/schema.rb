# frozen_string_literal: true

require "digest"
require "json"

module Umath
  # Verified, data-only declarations shared with foreign language generators.
  module Schema
    class ChecksumMismatch < StandardError; end

    BUNDLE_PATH = File.expand_path("../../schema/umath.bundle.json", __dir__).freeze
    BUNDLE_SHA256 = "0d14e7e8c5971c9bb304f14362784bbb49baa1a208195c4151090524cd425d8b".freeze

    def self.bundle_json
      bytes = File.binread(BUNDLE_PATH)
      actual = Digest::SHA256.hexdigest(bytes)
      unless actual == BUNDLE_SHA256
        raise ChecksumMismatch, "model declaration checksum mismatch: #{actual}"
      end

      bytes.force_encoding(Encoding::UTF_8)
    end

    def self.bundle_path
      bundle_json
      BUNDLE_PATH
    end

    def self.bundle
      JSON.parse(bundle_json)
    end
  end
end
