# frozen_string_literal: true

# Writes the next unicode stage generation for plurimath-testsuite: every
# payload of the source generation copied byte for byte, plus one stage-case
# payload (plurimath-stage/unicode/cases/1) per legacy-oracle payload of the
# source generation, with the outcome of each of its inputs.
#
#   bundle exec ruby scripts/stage_cases.rb --testsuite TESTSUITE_CHECKOUT \
#     --out OUT [--source-generation N] [--boundary raw-tree|typed-model]
#
# With --boundary raw-tree (the default) the payloads are raw-<group>.yaml
# with row ids "<id>.raw": the Unicodemath::RawParser outcome. The tree is
# written in the legacy grammar's shape: the wrappers the capture-shape
# normalization added are removed with scripts/unwrap.rb, so the rows stay
# comparable with the legacy rows. Refusals carry their byte offset into the
# preprocessed text.
#
# With --boundary typed-model the payloads are model-<group>.yaml with row
# ids "<id>.model": the typed model (Unicodemath::Model::Document) that
# Unicodemath.parse returns. It is written from the bound data the model is
# built from (the model binding's `(any)` output) and typed by the declared
# model attributes: each object is {node: <model class>, fields: [...]} with
# its set fields in declaration order; nil fields are left out. The value
# and kind of a node with a spelling come from the symbol catalog, as
# Symbols.resolve fills them. A walk of the built model through its declared
# attributes must give the same value, or the run stops; lutaml-model
# serialization is never used. Refusals carry their byte offset into the
# caller's input. The producer block names the committed LML export
# (model/unicodemath.lml.json).
#
# TESTSUITE_CHECKOUT is a clean plurimath-testsuite checkout. The source
# generation (default: the latest in generations/unicode.yaml) has its
# snapshot digest and every file checksum verified before anything is read.
# Every input is parsed on the Ruby and the native engine; the run fails
# unless both engines give the same outcome. In typed-model mode the ids in
# spec/parser/fixtures/oracle/native-divergences.yml are treated as the
# parity spec treats them: the Ruby outcome is written and the native one
# must still differ. Refusals are recorded with their category and byte
# offset; nothing else (nesting limits, invalid input, unexpected values) is
# turned into data.
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
require "json"
require "open3"
require "optparse"
require "yaml"
require "unicodemath"
require_relative "unwrap"

module StageCases
  class Failure < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  LANGUAGE = "unicode"
  REPOSITORY = "https://github.com/plurimath/unicodemath"
  TESTSUITE_REPOSITORY = "https://github.com/plurimath/plurimath-testsuite"
  GENERATOR_PATH = "scripts/stage_cases.rb"
  CASES_SCHEMA = "plurimath-stage/unicode/cases/1"
  PROVENANCE_SCHEMA = "plurimath-stage/provenance/1"
  ENGINES = %i[native ruby].freeze
  DECIMAL = "."
  BOUNDARIES = %w[raw-tree typed-model].freeze
  PRODUCER_NAMES = { "raw-tree" => "unicodemath-raw", "typed-model" => "unicodemath-model" }.freeze
  ROW_SUFFIXES = { "raw-tree" => ".raw", "typed-model" => ".model" }.freeze
  PAYLOAD_PREFIXES = { "raw-tree" => "raw-", "typed-model" => "model-" }.freeze
  ENTRY_POINTS = { "raw-tree" => "Unicodemath::RawParser.parse", "typed-model" => "Unicodemath.parse" }.freeze
  LML = "model/unicodemath.lml.json"
  LML_CHECKSUMS = "model/unicodemath.lml.checksums.txt"
  DIVERGENCES = "spec/parser/fixtures/oracle/native-divergences.yml"
  # The source payloads whose inputs are read: the rows the legacy facade
  # produced, not earlier stage-case payloads.
  SOURCE_PRODUCER_KIND = "legacy-oracle"
  # Files whose bytes decide the rows; they must be committed as they are.
  PRODUCER_FILES = [
    GENERATOR_PATH,
    "scripts/unwrap.rb",
    "lib",
    "artifacts",
    "grammars",
    "data",
    "model",
    DIVERGENCES,
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

      { "preprocessed" => Canonical.dump(result.text), "tree" => Canonical.dump(UnicodemathUnwrap.call(result.tree)) }
    rescue Unicodemath::NestingTooDeep => e
      raise Failure, "nesting too deep on the #{engine} engine (#{e.message}); not a refusal"
    rescue Unicodemath::ParseError => e
      { "refusal" => { "category" => "parse_error", "byte_offset" => e.byte_offset } }
    end

    # One input's typed-model outcome on one engine: the Document of
    # Unicodemath.parse in tagged form, written from its bound data and
    # checked against a walk of the built Document.
    def model_of(input, engine)
      # Unicodemath.parse first: its refusal offsets are in the caller's input.
      document = Unicodemath.parse(input, decimal: DECIMAL, engine: engine)
      text = Unicodemath::RawParser.normalize_input(input)
      raw = Unicodemath::RawParser.parse(text, decimal: DECIMAL, engine: engine)
      raise Failure, "asked for the #{engine} engine, got #{raw.engine}" if raw.text && raw.engine != engine

      data = { "label" => raw.label, "decimal" => DECIMAL }
      data["expression"] = raw.model_data if raw.text
      tree = ModelForm.node(Unicodemath::Model::Document, data)
      unless ModelForm.walk(document) == tree
        raise Failure, "#{input.inspect}: #{engine} engine: the built model differs from its bound data"
      end

      { "preprocessed" => Canonical.dump(raw.text), "tree" => tree }
    rescue Unicodemath::NestingTooDeep => e
      raise Failure, "nesting too deep on the #{engine} engine (#{e.message}); not a refusal"
    rescue Unicodemath::ParseError => e
      ran = Unicodemath.last_engine
      raise Failure, "asked for the #{engine} engine, got #{ran}" unless ran == engine

      { "refusal" => { "category" => "parse_error", "byte_offset" => e.byte_offset } }
    end

    # The same outcome on every engine, or a Failure naming the difference.
    # For an id in +divergent+ the Ruby outcome is written, and the native
    # one must still differ (a known Parsanol native-engine divergence).
    def agreed(id, input, boundary = "raw-tree", divergent: [])
      outcomes = ENGINES.to_h do |engine|
        [engine, boundary == "typed-model" ? model_of(input, engine) : of(input, engine)]
      end
      if divergent.include?(id)
        if outcomes.values.uniq.size == 1
          raise Failure, "#{id}: listed in #{DIVERGENCES} but the engines agree; remove it from the list"
        end

        return outcomes.fetch(:ruby)
      end
      return outcomes.values.first if outcomes.values.uniq.size == 1

      raise Failure, "#{id}: the engines disagree: " +
                     outcomes.map { |e, o| "#{e}=#{o.inspect}" }.join(" ")
    end
  end

  # The typed model in canonical tagged form.
  module ModelForm
    module_function

    def model_class?(type)
      type.is_a?(Class) && type < Lutaml::Model::Serializable
    end

    # The tagged node of +klass+ from its bound data +data+ (attribute name
    # => plain data). A node with a spelling gets the value and kind the
    # symbol catalog gives it (Symbols.resolve). +path+ names the place for
    # error messages.
    def node(klass, data, path = "")
      raise Failure, "#{path}/: #{klass} data is a #{data.class}, not a Hash" unless data.is_a?(Hash)

      attributes = klass.attributes
      unknown = data.keys.map(&:to_s) - attributes.keys.map(&:to_s)
      raise Failure, "#{path}/: #{klass} has no attribute #{unknown.join(', ')}" unless unknown.empty?

      data = resolved(attributes, data, path)
      fields = attributes.filter_map do |name, attribute|
        raise Failure, "#{path}/#{name}: derived attributes are not supported" if attribute.derived?

        value = data[name.to_s]
        next if value.nil?

        [name.to_s, field(attribute, value, "#{path}/#{name}")]
      end
      { "node" => klass.name, "fields" => fields }
    end

    def resolved(attributes, data, path)
      return data unless attributes.key?(:spelling) && data["spelling"]

      present = %w[value kind] & data.keys
      raise Failure, "#{path}/: bound data already holds #{present.join(', ')}" unless present.empty?

      value, kind = Unicodemath::Symbols.lookup(data["spelling"])
      data.merge("value" => value, "kind" => kind)
    end

    def field(attribute, value, path)
      return value(attribute.type, value, path) unless attribute.collection?
      raise Failure, "#{path}: a collection holds a #{value.class}" unless value.is_a?(Array)

      { "array" => value.each_with_index.map { |item, i| value(attribute.type, item, "#{path}/#{i}") } }
    end

    def value(type, value, path)
      return node(type, value, path) if model_class?(type)
      return Canonical.dump(value) if type == Lutaml::Model::Type::String && value.is_a?(String)

      raise Failure, "#{path}: #{value.class} for a #{type} attribute"
    end

    # The same tagged form read from a built model through its declared
    # attributes.
    def walk(value)
      case value
      when Lutaml::Model::Serializable
        fields = value.class.attributes.filter_map do |name, _attribute|
          child = value.public_send(name)
          [name.to_s, walk(child)] unless child.nil?
        end
        { "node" => value.class.name, "fields" => fields }
      when Array then { "array" => value.map { |item| walk(item) } }
      when String then Canonical.dump(value)
      else raise Failure, "no canonical form for #{value.class} in the model"
      end
    end
  end

  # The ids spec/parser/fixtures/oracle/native-divergences.yml lists.
  def self.divergent_ids
    doc = YAML.safe_load_file(File.join(ROOT, DIVERGENCES))
    raise Failure, "#{DIVERGENCES}: unexpected schema #{doc['schema'].inspect}" unless doc["schema"] == "unicodemath-native-divergences/1"

    doc.fetch("ids")
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

    # The payload entries whose inputs a generator reads: those of the
    # legacy-oracle producers.
    def input_entries
      producers = @provenance.fetch("producers")
      @provenance["payloads"].select do |p|
        producers.fetch(p["producer"]) { raise Failure, "#{dir}: no producer #{p['producer']}" }["kind"] == SOURCE_PRODUCER_KIND
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
  # stage-gem producer block (see Identity); +boundary+ is raw-tree or
  # typed-model; +divergent+ the ids with a known native-engine divergence
  # (typed-model only); +progress+ receives one line per row.
  class Generator
    def initialize(source, producer, boundary: "raw-tree", divergent: [], progress: nil)
      raise Failure, "unknown boundary #{boundary.inspect} (#{BOUNDARIES.join(', ')})" unless BOUNDARIES.include?(boundary)

      @source = source
      @producer = producer
      @boundary = boundary
      @divergent = divergent
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

    def model?
      @boundary == "typed-model"
    end

    def producer_name
      PRODUCER_NAMES.fetch(@boundary)
    end

    def prefix
      PAYLOAD_PREFIXES.fetch(@boundary)
    end

    def build
      payloads = {}
      entries = []
      inputs = @source.input_entries.map { |e| e["path"] }
      raise Failure, "#{@source.dir} has no #{SOURCE_PRODUCER_KIND} payload to read" if inputs.empty?

      @source.payloads.each do |entry, doc|
        bytes = @source.files.fetch(entry["path"])
        payloads[entry["path"]] = bytes
        entries << entry.merge("source" => { "relation" => "copy", "file" => @source.file_ref(entry["path"]) })
        next unless inputs.include?(entry["path"])

        name = "#{prefix}#{File.basename(entry['path'], '.yaml')}"
        path = "payloads/#{name}.yaml"
        raise Failure, "#{path} already exists in the source generation" if @source.files.key?(path)

        generated = stage_payload(name, entry["path"], doc)
        payloads[path] = generated
        entries << { "path" => path, "bytes" => generated.bytesize,
                     "sha256" => Digest::SHA256.hexdigest(generated), "producer" => producer_name,
                     "source" => { "relation" => "generated", "file" => nil },
                     "rows" => YAML.safe_load(generated)["cases"].map { |c| c["id"] } }
      end
      entries.sort_by! { |e| e["path"].b }

      producers = @source.provenance.fetch("producers").dup
      raise Failure, "source already has a #{producer_name} producer" if producers.key?(producer_name)

      producers[producer_name] = @producer
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
        "change" => "extend", "rationale" => rationale
      }

      out = generation.transform_keys { |p| "#{dir}/#{p}" }
      out["generations/#{LANGUAGE}.yaml"] = ledger_bytes
      out
    end

    def rationale
      if model?
        "Keeps every generation #{@source.generation} payload byte for byte and adds typed-model rows " \
          "(Unicodemath.parse, Ruby and native engines agreeing) for each legacy input, written by " \
          "#{GENERATOR_PATH} at unicodemath #{@producer['commit']}."
      else
        "Keeps every generation #{@source.generation} payload byte for byte and adds " \
          "Unicodemath::RawParser raw-tree rows (Ruby and native engines agreeing) for " \
          "each of their inputs, written by #{GENERATOR_PATH} at unicodemath " \
          "#{@producer['commit']}."
      end
    end

    def notes
      copied = "Generation #{@source.generation} (#{@source.dir} at plurimath-testsuite #{@source.commit}, " \
               "#{@source.entry['snapshot_digest']}) copied byte for byte, plus one #{prefix}<group> "
      if model?
        copied + "payload per legacy-oracle payload with the typed model (Unicodemath.parse, LML export " \
                 "#{LML}) of each of its inputs (row id = source id + #{ROW_SUFFIXES.fetch(@boundary)}). " \
                 "Written by #{GENERATOR_PATH} at unicodemath #{@producer['commit']}. The legacy rows stay " \
                 "the parity oracle; the typed-model rows sit beside them."
      else
        copied + "payload per copied payload with the stage-gem raw-tree outcome of each of its inputs " \
                 "(row id = source id + #{ROW_SUFFIXES.fetch(@boundary)}). Written by #{GENERATOR_PATH} at unicodemath " \
                 "#{@producer['commit']}. The legacy rows stay the parity oracle; the raw-tree rows sit beside them."
      end
    end

    def provenance_bytes(provenance)
      "# Generation #{number} of the #{LANGUAGE} stage corpus. Immutable: never edit this\n" \
        "# directory; add a new generation instead. See docs/stage-corpus-contract.adoc.\n" \
        "# Written by #{GENERATOR_PATH} (plurimath/unicodemath).\n" +
        StageCases.yaml(provenance)
    end

    def stage_payload(name, source_path, doc)
      cases = doc.fetch("cases").map do |c|
        id = c.fetch("id")
        input = c.fetch("input")
        raise Failure, "#{id}: input is not a string" unless input.is_a?(String)

        @progress&.call(id)
        { "id" => "#{id}#{ROW_SUFFIXES.fetch(@boundary)}", "input" => Canonical.dump(input),
          "options" => { "decimal" => DECIMAL },
          "expected" => Outcome.agreed(id, input, @boundary, divergent: @divergent) }
      end
      payload = { "schema" => CASES_SCHEMA, "group" => name, "description" => description(source_path),
                  "boundary" => @boundary, "cases" => cases }
      "# #{model? ? 'Typed-model' : 'Raw-tree'} rows for #{source_path}. Written by #{GENERATOR_PATH}\n" \
        "# (plurimath/unicodemath). Do not edit; see provenance.yaml.\n" +
        StageCases.yaml(payload)
    end

    def description(source_path)
      if model?
        "Typed model (Unicodemath::Model::Document) from Unicodemath.parse for each input of " \
          "#{source_path} (generation #{@source.generation}): the legacy preprocessing and the model, each " \
          "object its model class (#{LML}) with its set fields in declaration order (nil fields left " \
          "out), or a refusal with its byte offset into the caller's input. Default decimal marker; the " \
          "Ruby and native engines agree on every row."
      else
        "Unicodemath::RawParser outcome for each input of #{source_path} " \
          "(generation #{@source.generation}): the legacy preprocessing and the raw " \
          "grammar tree, or a refusal with its byte offset into the preprocessed text. " \
          "Default decimal marker; the Ruby and native engines agree on every row."
      end
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

    def producer(source, boundary = "raw-tree", divergent: [])
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
          source.input_entries.map { |p| source.file_ref(p["path"]) },
        "environment" => {
          "ruby" => { "engine" => RUBY_ENGINE, "version" => RUBY_VERSION },
          "xml_engine" => nil,
          "lockfile" => lockfile,
          "dependencies" => dependencies(boundary),
          "compiler" => {
            "name" => "parsanol", "version" => field.("compiler_version"), "edition" => field.("edition"),
            "artifact_checksum" => field.("artifact_checksum"), "source_hash" => field.("source_hash"),
            "grammar" => file(commit, "grammars/unicodemath.parg"),
            "artifact" => file(commit, "artifacts/unicodemath.json")
          },
          "binding" => {
            "ruby_checksum" => field.("bindings ruby checksum"),
            "artifact" => file(commit, "artifacts/unicodemath.bindings.ruby.json")
          },
          "lml" => (boundary == "typed-model" ? lml(commit) : nil)
        },
        "semantic_boundary" => boundary,
        "configuration" => configuration(source, boundary, commit, divergent)
      }
    end

    def dependencies(boundary)
      names = boundary == "typed-model" ? %w[lutaml-model parsanol] : %w[parsanol]
      names.to_h { |name| [name, Gem.loaded_specs.fetch(name).version.to_s] }
    end

    def configuration(source, boundary, commit, divergent)
      config = {
        "decimal" => DECIMAL, "engines" => ENGINES.map(&:to_s),
        "entry_point" => ENTRY_POINTS.fetch(boundary),
        "source_generation" => {
          "repository" => TESTSUITE_REPOSITORY, "commit" => source.commit, "language" => LANGUAGE,
          "generation" => source.generation, "snapshot_digest" => source.entry["snapshot_digest"]
        }
      }
      return config unless boundary == "typed-model"

      ids = source.payloads.select { |entry, _| source.input_entries.include?(entry) }
                  .flat_map { |_, doc| doc.fetch("cases").map { |c| c["id"] } }
      config.merge(
        "engine_agreement" => "required",
        "native_divergences" => {
          "list" => file(commit, DIVERGENCES),
          "rule" => "as spec/parser/oracle_parity_spec.rb: a listed id is a known Parsanol native-engine " \
                    "divergence; its Ruby outcome is written and the native outcome must still differ",
          "excluded" => ids & divergent
        }
      )
    end

    # The committed LML export the typed-model rows' classes are declared in.
    def lml(commit)
      export = JSON.parse(File.read(File.join(ROOT, LML)))
      line = File.readlines(File.join(ROOT, LML_CHECKSUMS), chomp: true).map(&:split).find { |key, _| key == LML }
      raise Failure, "#{LML_CHECKSUMS} has no line for #{LML}" unless line

      checksum = "sha256:#{Digest::SHA256.file(File.join(ROOT, LML)).hexdigest}"
      raise Failure, "#{LML} does not match #{LML_CHECKSUMS}" unless line[1] == checksum

      { "format" => export.fetch("format"), "root" => export.fetch("root"),
        "checksum" => checksum, "models" => export.fetch("models").size,
        "export" => file(commit, LML), "checksums" => file(commit, LML_CHECKSUMS) }
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
        "bundler" => Bundler::VERSION,
        "resolved" => specs.sort_by(&:name).to_h { |spec| [spec.name, spec.version.to_s] } }
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
        o.banner = "usage: scripts/stage_cases.rb --testsuite DIR --out DIR [--source-generation N] " \
                   "[--boundary #{BOUNDARIES.join('|')}]"
        o.on("--testsuite DIR") { |v| @options[:testsuite] = v }
        o.on("--out DIR") { |v| @options[:out] = v }
        o.on("--source-generation N", Integer) { |v| @options[:generation] = v }
        o.on("--boundary NAME", BOUNDARIES) { |v| @options[:boundary] = v }
      end.parse!(argv)
      raise Failure, "--testsuite and --out are required" unless @options[:testsuite] && @options[:out]
    end

    def run
      source = Source.new(@options[:testsuite], @options[:generation])
      boundary = @options.fetch(:boundary, "raw-tree")
      divergent = boundary == "typed-model" ? StageCases.divergent_ids : []
      generator = Generator.new(source, Identity.producer(source, boundary, divergent: divergent),
                                boundary: boundary, divergent: divergent, progress: ->(id) { warn "  #{id}" })
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
