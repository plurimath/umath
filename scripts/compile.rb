# frozen_string_literal: true

# grammars/umath.parg -> artifacts/umath.json (Parsanol PARG artifact)
#
# Usage:
#   bundle exec ruby scripts/compile.rb [--determinism]
#
# The bundle must provide the `parsanol` executable (the version is
# recorded in the checksum manifest). Steps, as in amath:
#   1. scripts/generate_grammar.rb --check (the .parg matches its export)
#   2. bundle exec parsanol parg compile  -> artifacts/umath.json
#   3. bundle exec parsanol parg check    (artifact matches source + compiler)
#   4. bundle exec parsanol parg compile ... --bindings all: one checksummed
#      parg-bindings artifact per Parsanol binding target beside the
#      artifact, artifacts/umath.bindings.<target>.json (the flag
#      needs parsanol >= 1.3.131; the script refuses a run that emits none)
#   5. --determinism: compile and emit again into a temporary directory and
#      require identical bytes for every emitted file
#   6. write artifacts/umath.checksums.txt
# Exits nonzero on the first failing step.

require "digest"
require "json"
require "open3"
require "parsanol"
require "rbconfig"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
GRAMMAR = File.join(ROOT, "grammars/umath.parg")
EXPORT = File.join(ROOT, "data/umath-grammar.json")
ARTIFACT = File.join(ROOT, "artifacts/umath.json")
CHECKSUMS = File.join(ROOT, "artifacts/umath.checksums.txt")

determinism = ARGV.delete("--determinism")
abort "usage: ruby scripts/compile.rb [--determinism]" unless ARGV.empty?

def run!(*cmd)
  out, status = Open3.capture2e(*cmd, chdir: ROOT)
  puts out
  abort "FAILED (exit #{status.exitstatus}): #{cmd.join(' ')}" unless status.success?
  out
end

def relative(path)
  path.delete_prefix("#{ROOT}/")
end

# The bindings artifacts beside +artifact+.
def binding_files(artifact)
  Dir[artifact.sub(/\.json\z/, ".bindings.*.json")].sort
end

# Compiles the parse artifact and, with --bindings all, one bindings
# artifact per Parsanol binding target.
def compile!(output)
  run!("bundle", "exec", "parsanol", "parg", "compile", GRAMMAR, "-o", output, "--bindings", "all")
  expected = Parsanol::PARG::Bindings::Artifact::TARGETS.map { |t| output.sub(/\.json\z/, ".bindings.#{t}.json") }.sort
  return if binding_files(output) == expected

  abort "FAILED: --bindings all emitted #{binding_files(output).map { |f| File.basename(f) }}, " \
        "expected #{expected.map { |f| File.basename(f) }} (parsanol #{Parsanol::VERSION}; needs >= 1.3.131)"
end

run!(RbConfig.ruby, "scripts/generate_grammar.rb", "--check")
binding_files(ARTIFACT).each { |f| File.delete(f) }
compile!(ARTIFACT)
run!("bundle", "exec", "parsanol", "parg", "check", "--source", GRAMMAR, "--artifact", ARTIFACT)
puts "bindings: #{binding_files(ARTIFACT).map { |f| relative(f) }.join(' ')}"
emitted = [ARTIFACT, *binding_files(ARTIFACT)]

if determinism
  Dir.mktmpdir do |dir|
    again = File.join(dir, File.basename(ARTIFACT))
    compile!(again)
    others = [again, *binding_files(again)]
    names = ->(list) { list.map { |f| File.basename(f) } }
    abort "FAILED: recompilation emitted #{names.call(others)}, not #{names.call(emitted)}" unless names.call(others) == names.call(emitted)

    emitted.zip(others).each do |mine, other|
      abort "FAILED: #{relative(mine)} is not byte-identical on recompilation" unless File.binread(mine) == File.binread(other)
    end
    puts "determinism: #{emitted.size} recompiled file(s) byte-identical"
  end
end

envelope = JSON.parse(File.binread(ARTIFACT))
lines = [
  "# Written by scripts/compile.rb. Envelope checksums are Parsanol's own;",
  "# the sha256 lines are of the files' bytes.",
  "artifact_checksum #{envelope.fetch('checksum')}",
  "compiler_version #{envelope.fetch('compiler_version')}",
  "edition #{envelope.fetch('edition', 2)}",
  "source_hash sha256:#{envelope.fetch('source_hash')}",
  "#{relative(ARTIFACT)} sha256:#{Digest::SHA256.file(ARTIFACT).hexdigest}",
]
binding_files(ARTIFACT).each do |file|
  payload = JSON.parse(File.binread(file))
  lines << "bindings #{payload.fetch('target')} checksum #{payload.fetch('checksum')}"
  lines << "#{relative(file)} sha256:#{Digest::SHA256.file(file).hexdigest}"
end
lines.push(
  "#{relative(GRAMMAR)} sha256:#{Digest::SHA256.file(GRAMMAR).hexdigest}",
  "#{relative(EXPORT)} sha256:#{Digest::SHA256.file(EXPORT).hexdigest}",
  "entries #{envelope.fetch('entries').keys.join(' ')}",
  "order_warnings #{envelope.dig('lint', 'order_warnings').size}",
)
File.write(CHECKSUMS, "#{lines.join("\n")}\n")
puts File.read(CHECKSUMS)
