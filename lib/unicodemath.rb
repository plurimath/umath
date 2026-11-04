# frozen_string_literal: true

require "parsanol"

# UnicodeMath parser backed by a compiled Parsanol (PARG) grammar artifact.
#
# Unicodemath.parse returns the typed language model (Unicodemath::Model,
# declared with LutaML Model). The raw parse tree (Unicodemath::RawParser)
# is an internal boundary for parity replay with the legacy Plurimath
# parser. See docs/parser-contract.adoc and docs/model-contract.adoc.
module Unicodemath
  autoload :VERSION, "unicodemath/version"
  autoload :Error, "unicodemath/errors"
  autoload :ParseError, "unicodemath/errors"
  autoload :NestingTooDeep, "unicodemath/errors"
  autoload :ArtifactError, "unicodemath/errors"
  autoload :EngineUnavailable, "unicodemath/errors"
  autoload :Artifact, "unicodemath/artifact"
  autoload :Configuration, "unicodemath/configuration"
  autoload :Engine, "unicodemath/engine"
  autoload :Preprocessor, "unicodemath/preprocessor"
  autoload :RawParser, "unicodemath/raw_parser"
  autoload :Parser, "unicodemath/parser"
  autoload :Model, "unicodemath/model"
  autoload :SourceMap, "unicodemath/source_map"
  autoload :Symbols, "unicodemath/symbols"

  @artifacts = Artifact.new(Configuration::DEFAULT_ARTIFACT_PATH,
                            Configuration::DEFAULT_BINDINGS_PATH)

  class << self
    # Parses +input+ (a String) and returns its Unicodemath::Model::Document.
    #
    # +decimal+: the decimal marker, "." (default), "," or "٫" (U+066B).
    # +engine+: :ruby (default), :native, or :auto (native where available,
    # else Ruby).
    #
    # Raises ParseError (with offsets into +input+) when the input is
    # refused, NestingTooDeep when the selected engine cannot handle its
    # depth, EngineUnavailable for an unavailable engine: :native,
    # ArtifactError for unusable bundled artifacts and ArgumentError for
    # invalid arguments.
    def parse(input, decimal: ".", engine: :ruby)
      Parser.parse(input, decimal: decimal, engine: engine)
    end

    # The engine (:native or :ruby) of this thread's last parse or
    # rejection, nil before any.
    def last_engine
      Engine.last_engine
    end

    # The verified, paired parse and Ruby bindings artifacts (internal).
    def artifacts
      @artifacts.fetch
    end

    # Points Unicodemath at other artifacts (for tests). The next parse
    # loads and verifies them.
    def use_artifacts(path, bindings_path)
      @artifacts.use(path, bindings_path)
    end

    def artifact_paths
      [@artifacts.path, @artifacts.bindings_path]
    end
  end
end

# Installs a hook into Parsanol at load time, so it is required, not
# autoloaded.
require_relative "unicodemath/errors"
require_relative "unicodemath/native_recursion_guard"
