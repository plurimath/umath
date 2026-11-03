# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "unicodemath"

module ArtifactSpecHelpers
  ROOT = File.expand_path("../..", __dir__)
  ARTIFACT = File.join(ROOT, "artifacts", "unicodemath.json")
  CHECKSUMS = File.join(ROOT, "artifacts", "unicodemath.checksums.txt")
  GRAMMAR = File.join(ROOT, "grammars", "unicodemath.parg")
  EXPORT = File.join(ROOT, "data", "unicodemath-grammar.json")
  TARGETS = Parsanol::PARG::Bindings::Artifact::TARGETS

  def bindings_path(target)
    File.join(ROOT, "artifacts", "unicodemath.bindings.#{target}.json")
  end

  def manifest
    File.readlines(CHECKSUMS, chomp: true).reject { |l| l.start_with?("#") }
  end

  def envelope
    @envelope ||= JSON.parse(File.binread(ARTIFACT))
  end

  # A copy of the bindings payload for +target+ with +changes+ applied and,
  # unless +keep_checksum+, a recomputed checksum.
  def altered_bindings(target, keep_checksum: false, **changes)
    payload = JSON.parse(File.binread(bindings_path(target)))
    changes.each { |key, value| payload[key.to_s] = value }
    unless keep_checksum
      payload.delete("checksum")
      payload["checksum"] = Parsanol::PARG::Compiler.checksum(payload)
    end
    JSON.generate(payload)
  end

  # Runs +block+ with Unicodemath pointed at +parse+/+bindings+, then
  # restores the bundled artifacts.
  def with_artifacts(parse, bindings)
    saved = Unicodemath.artifact_paths
    Unicodemath.use_artifacts(parse, bindings)
    yield
  ensure
    Unicodemath.use_artifacts(*saved)
  end
end

RSpec.configure do |config|
  config.include ArtifactSpecHelpers
end
