# frozen_string_literal: true

require "parsanol"

# UnicodeMath parser backed by a compiled Parsanol (PARG) grammar artifact.
#
# Umath.parse returns the typed language model (Umath::Model,
# declared with LutaML Model). The raw parse tree (Umath::RawParser)
# is an internal boundary for parity replay with the legacy Plurimath
# parser. See docs/parser-contract.adoc and docs/model-contract.adoc.
module Umath
  autoload :VERSION, "umath/version"
  autoload :Error, "umath/errors"
  autoload :ParseError, "umath/errors"
  autoload :NestingTooDeep, "umath/errors"
  autoload :ArtifactError, "umath/errors"
  autoload :EngineUnavailable, "umath/errors"
  autoload :Artifact, "umath/artifact"
  autoload :Configuration, "umath/configuration"
  autoload :Engine, "umath/engine"
  autoload :Preprocessor, "umath/preprocessor"
  autoload :RawParser, "umath/raw_parser"
  autoload :Parser, "umath/parser"
  autoload :Model, "umath/model"
  autoload :SourceMap, "umath/source_map"
  autoload :Symbols, "umath/symbols"

  @artifacts = Artifact.new(Configuration::DEFAULT_ARTIFACT_PATH,
                            Configuration::DEFAULT_BINDINGS_PATH)

  class << self
    # Parses +input+ (a String) and returns its Umath::Model::Document.
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

    # Points Umath at other artifacts (for tests). The next parse
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
require_relative "umath/errors"
require_relative "umath/native_recursion_guard"
