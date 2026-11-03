# frozen_string_literal: true

require "parsanol"

# UnicodeMath parser backed by a compiled Parsanol (PARG) grammar artifact.
#
# The public entry point, Unicodemath.parse returning the typed language
# model, is not part of this version. What is here is the grammar artifact,
# its declared syntax bindings and the internal raw-tree boundary
# (Unicodemath::RawParser) that parity replay compares with the legacy
# Plurimath parser. See docs/parser-contract.adoc.
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

  @artifacts = Artifact.new(Configuration::DEFAULT_ARTIFACT_PATH,
                            Configuration::DEFAULT_BINDINGS_PATH)

  class << self
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
