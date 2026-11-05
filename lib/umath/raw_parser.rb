# frozen_string_literal: true

module Umath
  # The internal raw-tree boundary: the legacy preprocessing, then the
  # grammar, then the declared syntax bindings, which carry the raw tree.
  #
  # Internal and for tests and parity replay only; not public API. The
  # public Umath.parse, which returns the typed language model, is
  # built on top of it.
  module RawParser
    # +text+: the grammar input (see Preprocessor::Result), nil when the
    # input has no formula part; +label+/+labeled+: the label split off by
    # preprocessing; +tree+: the raw tree of the normalized grammar (Hashes,
    # Arrays and Parsanol::Slice leaves; scripts/unwrap.rb turns it into the
    # legacy tree), nil when +text+ is nil; +model_data+: the same
    # tree as plain Hashes, Arrays and Strings with String keys (the typed
    # model's construction input); +engine+: the engine that produced it.
    Result = Struct.new(:text, :label, :labeled, :tree, :model_data, :engine, keyword_init: true)

    module_function

    def parse(input, decimal: ".", engine: :ruby)
      entry = entry_for(decimal)
      mode = Engine.resolve(engine)
      pre = Preprocessor.call(normalize_input(input))
      result = Result.new(text: pre.text, label: pre.label, labeled: pre.labeled)
      return result if pre.text.nil?

      loaded = Umath.artifacts
      shape = Engine.run(loaded.parse, entry, pre.text, mode, fallback: engine == :auto)
      bound = loaded.bindings.apply(entry, shape)
      result.tree, result.model_data = [Configuration::TREE_CAPTURE, Configuration::MODEL_BINDING].map do |key|
        bound.fetch(key) { raise ArtifactError, "the declared bindings did not produce #{key}" }
      end
      result.engine = Engine.last_engine
      result
    end

    def entry_for(decimal)
      Configuration::DECIMAL_ENTRIES.fetch(decimal) do
        raise ArgumentError,
              "unsupported decimal marker #{decimal.inspect} " \
              "(supported: #{Configuration::DECIMAL_ENTRIES.keys.map(&:inspect).join(', ')})"
      end
    end

    # +input+ as valid UTF-8, or an ArgumentError.
    def normalize_input(input)
      raise ArgumentError, "input must be a String, got #{input.class}" unless input.is_a?(String)

      text = input.encoding == Encoding::UTF_8 ? input : input.encode(Encoding::UTF_8)
      raise ArgumentError, "input is not valid UTF-8" unless text.valid_encoding?

      text
    rescue EncodingError => e
      raise ArgumentError, "input cannot be converted to UTF-8: #{e.message}"
    end
  end
end
