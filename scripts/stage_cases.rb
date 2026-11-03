# frozen_string_literal: true

# Writes the next unicode stage generation for plurimath-testsuite: every
# payload of the source generation copied byte for byte, plus one raw-tree
# payload (plurimath-stage/unicode/cases/1) per source payload with the
# Unicodemath::RawParser outcome for each of its inputs.
#
#   bundle exec ruby scripts/stage_cases.rb --testsuite TESTSUITE_CHECKOUT \
#     --out OUT [--source-generation N]
#
# TESTSUITE_CHECKOUT is a clean plurimath-testsuite checkout. The source
# generation (default: the latest in generations/unicode.yaml) has its
# snapshot digest and every file checksum verified before anything is read.
# Every input is parsed on the Ruby and the native engine; the run fails
# unless both engines give the same outcome. Refusals are recorded with their
# category and byte offset into the preprocessed text; nothing else (nesting
# limits, invalid input, unexpected values) is turned into data.
#
# OUT receives, at the testsuite's own paths:
#
#   stages/unicode/generations/<next>/provenance.yaml
#   stages/unicode/generations/<next>/payloads/*.yaml
#   generations/unicode.yaml   (the source ledger with one entry appended)
#
# This checkout must be clean for the files the producer block names, so the
# recorded commit is the code that ran.
#
# Exit status: 0 on success, 1 on any failure.

require "digest"
require "fileutils"
require "open3"
require "optparse"
require "yaml"
require "unicodemath"

module StageCases
  class Failure < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  LANGUAGE = "unicode"
  REPOSITORY = "https://github.com/plurimath/unicodemath"
  TESTSUITE_REPOSITORY = "https://github.com/plurimath/plurimath-testsuite"
  GENERATOR_PATH = "scripts/stage_cases.rb"
  PRODUCER_NAME = "unicodemath-raw"
  CASES_SCHEMA = "plurimath-stage/unicode/cases/1"
  PROVENANCE_SCHEMA = "plurimath-stage/provenance/1"
  ENGINES = %i[ruby native].freeze
  DECIMAL = "."
  ROW_SUFFIX = ".raw"
  PAYLOAD_PREFIX = "raw-"
  # Files whose bytes decide the rows; they must be committed as they are.
  PRODUCER_FILES = [
    GENERATOR_PATH,
    "lib",
    "artifacts",
    "grammars",
    "unicodemath.gemspec",
    "Gemfile",
  ].freeze

  # The testsuite's canonical tagged form (plurimath-testsuite
  # docs/tree-parity-contract.adoc): one tag per node, hash entries in
  # insertion order, slices with their text and byte and character offsets.
  # Strings must be valid UTF-8: the form carries no encoding labels.
  module Canonical
    SLICE_CLASSES = %w[Parsanol::Slice Parslet::Slice].freeze

    module_function

    def dump(value)
      case value
      when nil then { "nil" => true }
      when true, false then { "bool" => value }
      when Integer then { "int" => value.to_s }
      when Float then { "float" => value.inspect }
      when String then { "str" => text(value) }
      when Symbol then { "sym" => text(value.to_s) }
      when Array then { "array" => value.map { |v| dump(v) } }
      when Hash then { "hash" => value.map { |k, v| [dump(k), dump(v)] } }
      else
        raise Failure, "no canonical form for #{value.class}" unless SLICE_CLASSES.include?(value.class.name)

        { "slice" => text(value.to_s), "byte_offset" => value.bytepos,
          "char_offset" => value.charpos }
      end
    end

    def text(value)
      utf8 = value.dup.force_encoding(Encoding::UTF_8)
      raise Failure, "string #{value.b.inspect} is not valid UTF-8" unless utf8.valid_encoding?

      utf8
    end
  end

  # One input's outcome on one engine, as the stage-cases `expected` value.
  module Outcome
    module_function

    def of(input, engine)
      result = Unicodemath::RawParser.parse(input, decimal: DECIMAL, engine: engine)
      if result.text && result.engine != engine
        raise Failure, "asked for the #{engine} engine, got #{result.engine}"
      end

      { "preprocessed" => Canonical.dump(result.text), "tree" => Canonical.dump(result.tree) }
    rescue Unicodemath::NestingTooDeep => e
      raise Failure, "nesting too deep on the #{engine} engine (#{e.message}); not a refusal"
    rescue Unicodemath::ParseError => e
      { "refusal" => { "category" => "parse_error", "byte_offset" => e.byte_offset } }
    end

    # The same outcome on every engine, or a Failure naming the difference.
    def agreed(id, input)
      outcomes = ENGINES.to_h { |engine| [engine, of(input, engine)] }
      return outcomes.values.first if outcomes.values.uniq.size == 1

      raise Failure, "#{id}: the engines disagree: " +
                     outcomes.map { |e, o| "#{e}=#{o.inspect}" }.join(" ")
    end
  end

  # A verified generation of the testsuite checkout.
  class Source
    attr_reader :root, :commit, :ledger_bytes, :entry, :provenance, :provenance_bytes, :files

    def initialize(root, generation = nil)
      @root = File.expand_path(root)
      @commit = git(@root, "rev-parse", "HEAD").strip
      dirty = git(@root, "status", "--porcelain", "--", "stages", "generations")
      raise Failure, "testsuite checkout has uncommitted stage files:\n#{dirty}" unless dirty.empty?

      @ledger_bytes = File.binread(File.join(@root, "generations", "#{LANGUAGE}.yaml"))
      entries = YAML.safe_load(@ledger_bytes).fetch("entries")
      @entry = generation ? entries.find { |e| e["generation"] == generation } : entries.last
      raise Failure, "ledger has no generation #{generation}" unless @entry
      if @entry != entries.last
        raise Failure, "generation #{@entry['generation']} is not the latest; the next one would leave a gap"
      end

      load_files
      verify
    end

    def generation
      @entry["generation"]
    end

    def dir
      @entry["path"]
    end

    # [relative path inside the generation, bytes] for every file.
    def load_files
      base = File.join(@root, dir)
      paths = Dir.glob("**/*", File::FNM_DOTMATCH, base: base)
                 .reject { |p| File.directory?(File.join(base, p)) }
      paths.each do |p|
        raise Failure, "#{dir}/#{p} is a symlink" if File.symlink?(File.join(base, p))
      end
      @files = paths.sort_by(&:b).to_h { |p| [p, File.binread(File.join(base, p))] }
      @provenance_bytes = @files.fetch("provenance.yaml") { raise Failure, "#{dir} has no provenance.yaml" }
      @provenance = YAML.safe_load(@provenance_bytes)
    end

    def verify
      digest = StageCases.snapshot_digest(@files)
      if digest != @entry["snapshot_digest"]
        raise Failure, "#{dir}: snapshot digest #{digest} != ledger #{@entry['snapshot_digest']}"
      end

      listed = @provenance.fetch("payloads").map { |p| p["path"] }
      if listed.sort != (@files.keys - ["provenance.yaml"]).sort
        raise Failure, "#{dir}: provenance does not list exactly the payload files"
      end

      @provenance["payloads"].each do |p|
        actual = Digest::SHA256.hexdigest(@files.fetch(p["path"]))
        raise Failure, "#{dir}/#{p['path']}: sha256 #{actual} != #{p['sha256']}" if actual != p["sha256"]
      end
    end

    def file_ref(relative)
      { "repository" => TESTSUITE_REPOSITORY, "commit" => @commit, "path" => "#{dir}/#{relative}",
        "sha256" => Digest::SHA256.hexdigest(@files.fetch(relative)) }
    end

    def payloads
      @provenance["payloads"].map do |p|
        [p, YAML.safe_load(@files.fetch(p["path"]))]
      end
    end

    private

    def git(dir, *args)
      out, err, status = Open3.capture3("git", "-C", dir, *args)
      raise Failure, "git #{args.join(' ')} in #{dir}: #{err}" unless status.success?

      out
    end
  end

  def self.snapshot_digest(files)
    lines = files.sort_by { |path, _| path.b }.map do |path, bytes|
      "#{Digest::SHA256.hexdigest(bytes)}  #{path}\n"
    end
    "sha256:#{Digest::SHA256.hexdigest(lines.join.encode('UTF-8'))}"
  end

  def self.yaml(value)
    YAML.dump(value, line_width: -1)
  end

  # Builds the next generation from a verified Source. +producer+ is the
  # stage-gem producer block (see Identity); +progress+ receives one line
  # per row.
  class Generator
    def initialize(source, producer, progress: nil)
      @source = source
      @producer = producer
      @progress = progress
    end

    def number
      @source.generation + 1
    end

    def dir
      format("stages/%s/generations/%06d", LANGUAGE, number)
    end

    # { path relative to the testsuite root => bytes }
    def files
      @files ||= build
    end

    def write(out)
      files.each do |path, bytes|
        target = File.join(out, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, bytes)
      end
    end

    def ledger_entry
      files
      @ledger_entry
    end

    private

    def build
      payloads = {}
      entries = []
      @source.payloads.each do |entry, doc|
        bytes = @source.files.fetch(entry["path"])
        payloads[entry["path"]] = bytes
        entries << entry.merge("source" => { "relation" => "copy", "file" => @source.file_ref(entry["path"]) })

        name = "#{PAYLOAD_PREFIX}#{File.basename(entry['path'], '.yaml')}"
        path = "payloads/#{name}.yaml"
        raise Failure, "#{path} already exists in the source generation" if @source.files.key?(path)

        generated = raw_payload(name, entry["path"], doc)
        payloads[path] = generated
        entries << { "path" => path, "bytes" => generated.bytesize,
                     "sha256" => Digest::SHA256.hexdigest(generated), "producer" => PRODUCER_NAME,
                     "source" => { "relation" => "generated", "file" => nil },
                     "rows" => YAML.safe_load(generated)["cases"].map { |c| c["id"] } }
      end
      entries.sort_by! { |e| e["path"].b }

      producers = @source.provenance.fetch("producers").dup
      raise Failure, "source already has a #{PRODUCER_NAME} producer" if producers.key?(PRODUCER_NAME)

      producers[PRODUCER_NAME] = @producer
      provenance = {
        "schema" => PROVENANCE_SCHEMA, "language" => LANGUAGE, "generation" => number,
        "notes" => notes, "producers" => producers, "payloads" => entries
      }
      generation = payloads.dup
      generation["provenance.yaml"] = provenance_bytes(provenance)

      rows = entries.sum { |e| e["rows"].size }
      kinds = producers.values.map { |p| p["kind"] }.uniq.sort
      @ledger_entry = {
        "generation" => number, "path" => dir,
        "snapshot_digest" => StageCases.snapshot_digest(generation),
        "payloads" => entries.size, "rows" => rows, "producer_kinds" => kinds,
        "change" => "extend",
        "rationale" => "Keeps every generation #{@source.generation} payload byte for byte and adds " \
                       "Unicodemath::RawParser raw-tree rows (Ruby and native engines agreeing) for " \
                       "each of their inputs, written by #{GENERATOR_PATH} at unicodemath " \
                       "#{@producer['commit']}."
      }

      out = generation.transform_keys { |p| "#{dir}/#{p}" }
      out["generations/#{LANGUAGE}.yaml"] = ledger_bytes
      out
    end

    def notes
      "Generation #{@source.generation} (#{@source.dir} at plurimath-testsuite #{@source.commit}, " \
        "#{@source.entry['snapshot_digest']}) copied byte for byte, plus one #{PAYLOAD_PREFIX}<group> " \
        "payload per copied payload with the stage-gem raw-tree outcome of each of its inputs " \
        "(row id = source id + #{ROW_SUFFIX}). Written by #{GENERATOR_PATH} at unicodemath " \
        "#{@producer['commit']}. The legacy rows stay the parity oracle; the raw-tree rows sit beside them."
    end

    def provenance_bytes(provenance)
      "# Generation #{number} of the #{LANGUAGE} stage corpus. Immutable: never edit this\n" \
        "# directory; add a new generation instead. See docs/stage-corpus-contract.adoc.\n" \
        "# Written by #{GENERATOR_PATH} (plurimath/unicodemath).\n" +
        StageCases.yaml(provenance)
    end

    def raw_payload(name, source_path, doc)
      cases = doc.fetch("cases").map do |c|
        id = c.fetch("id")
        input = c.fetch("input")
        raise Failure, "#{id}: input is not a string" unless input.is_a?(String)

        @progress&.call(id)
        { "id" => "#{id}#{ROW_SUFFIX}", "input" => Canonical.dump(input), "options" => {},
          "expected" => Outcome.agreed(id, input) }
      end
      payload = {
        "schema" => CASES_SCHEMA, "group" => name,
        "description" => "Unicodemath::RawParser outcome for each input of #{source_path} " \
                         "(generation #{@source.generation}): the legacy preprocessing and the raw " \
                         "grammar tree, or a refusal with its byte offset into the preprocessed text. " \
                         "Default decimal marker; the Ruby and native engines agree on every row.",
        "boundary" => "raw-tree", "cases" => cases
      }
      "# Raw-tree rows for #{source_path}. Written by #{GENERATOR_PATH}\n" \
        "# (plurimath/unicodemath). Do not edit; see provenance.yaml.\n" +
        StageCases.yaml(payload)
    end

    def ledger_bytes
      ledger = @source.ledger_bytes.dup.force_encoding(Encoding::UTF_8)
      ledger += "\n" unless ledger.end_with?("\n")
      ledger + StageCases.yaml([@ledger_entry]).delete_prefix("---\n")
    end
  end

  # The stage-gem producer block for this checkout, which must be clean for
  # PRODUCER_FILES so that the recorded commit is the code that runs.
  module Identity
    module_function

    def producer(source)
      commit = git("rev-parse", "HEAD").strip
      dirty = git("status", "--porcelain", "--", *PRODUCER_FILES)
      raise Failure, "unicodemath checkout has uncommitted producer files:\n#{dirty}" unless dirty.empty?
      raise Failure, "the native engine is not available" unless Unicodemath::Engine.native_available?

      checksums = File.read(File.join(ROOT, "artifacts", "unicodemath.checksums.txt"))
      field = ->(key) { checksums[/^#{Regexp.escape(key)} (\S+)$/, 1] }
      {
        "kind" => "stage-gem", "repository" => REPOSITORY, "commit" => commit,
        "version" => Unicodemath::VERSION,
        "generator" => file(commit, GENERATOR_PATH),
        "inputs" => [source.file_ref("provenance.yaml")] +
          source.provenance["payloads"].map { |p| source.file_ref(p["path"]) },
        "environment" => {
          "ruby" => { "engine" => RUBY_ENGINE, "version" => RUBY_VERSION },
          "xml_engine" => nil,
          "lockfile" => lockfile,
          "dependencies" => { "parsanol" => Gem.loaded_specs.fetch("parsanol").version.to_s },
          "compiler" => {
            "name" => "parsanol", "version" => field.("compiler_version"), "edition" => field.("edition"),
            "artifact_checksum" => field.("artifact_checksum"), "source_hash" => field.("source_hash"),
            "grammar" => file(commit, "grammars/unicodemath.parg"),
            "artifact" => file(commit, "artifacts/unicodemath.json")
          },
          "binding" => {
            "target" => "ruby", "checksum" => field.("bindings ruby checksum"),
            "artifact" => file(commit, "artifacts/unicodemath.bindings.ruby.json")
          },
          "lml" => nil
        },
        "semantic_boundary" => "raw-tree",
        "configuration" => {
          "entry_point" => "Unicodemath::RawParser.parse", "decimal" => DECIMAL,
          "engines" => ENGINES.map(&:to_s), "engines_must_agree" => true,
          "native_available" => true,
          "source_generation" => {
            "repository" => TESTSUITE_REPOSITORY, "commit" => source.commit, "language" => LANGUAGE,
            "generation" => source.generation, "snapshot_digest" => source.entry["snapshot_digest"]
          }
        }
      }
    end

    def file(commit, path)
      { "repository" => REPOSITORY, "commit" => commit, "path" => path,
        "sha256" => Digest::SHA256.file(File.join(ROOT, path)).hexdigest }
    end

    # Gemfile.lock is not committed in this repository; its digest and
    # resolved gem count identify the bundle that ran.
    def lockfile
      path = ENV.fetch("BUNDLE_GEMFILE", File.join(ROOT, "Gemfile")) + ".lock"
      raise Failure, "no lockfile at #{path}" unless File.file?(path)

      specs = Bundler::LockfileParser.new(File.read(path)).specs
      { "path" => "Gemfile.lock", "committed" => false,
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "resolved_gems" => specs.map(&:name).uniq.size,
        "bundler" => Bundler::VERSION }
    end

    def git(*args)
      out, err, status = Open3.capture3("git", "-C", ROOT, *args)
      raise Failure, "git #{args.join(' ')}: #{err}" unless status.success?

      out
    end
  end

  class CLI
    def initialize(argv)
      @options = {}
      OptionParser.new do |o|
        o.banner = "usage: scripts/stage_cases.rb --testsuite DIR --out DIR [--source-generation N]"
        o.on("--testsuite DIR") { |v| @options[:testsuite] = v }
        o.on("--out DIR") { |v| @options[:out] = v }
        o.on("--source-generation N", Integer) { |v| @options[:generation] = v }
      end.parse!(argv)
      raise Failure, "--testsuite and --out are required" unless @options[:testsuite] && @options[:out]
    end

    def run
      source = Source.new(@options[:testsuite], @options[:generation])
      generator = Generator.new(source, Identity.producer(source), progress: ->(id) { warn "  #{id}" })
      generator.write(@options[:out])
      entry = generator.ledger_entry
      puts "#{generator.dir}: #{entry['payloads']} payloads, #{entry['rows']} rows, #{entry['snapshot_digest']}"
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit StageCases::CLI.new(ARGV).run
  rescue StageCases::Failure, OptionParser::ParseError => e
    warn "stage_cases: #{e.message}"
    exit 1
  end
end
