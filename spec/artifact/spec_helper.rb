# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "umath"

module ArtifactSpecHelpers
  ROOT = File.expand_path("../..", __dir__)
  ARTIFACT = File.join(ROOT, "artifacts", "umath.json")
  CHECKSUMS = File.join(ROOT, "artifacts", "umath.checksums.txt")
  GRAMMAR = File.join(ROOT, "grammars", "umath.parg")
  EXPORT = File.join(ROOT, "data", "umath-grammar.json")
  TARGETS = Parsanol::PARG::Bindings::Artifact::TARGETS

  def bindings_path(target)
    File.join(ROOT, "artifacts", "umath.bindings.#{target}.json")
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

  # Runs +block+ with Umath pointed at +parse+/+bindings+, then
  # restores the bundled artifacts.
  def with_artifacts(parse, bindings)
    saved = Umath.artifact_paths
    Umath.use_artifacts(parse, bindings)
    yield
  ensure
    Umath.use_artifacts(*saved)
  end
end

RSpec.configure do |config|
  config.include ArtifactSpecHelpers
end
