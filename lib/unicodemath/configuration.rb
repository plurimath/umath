# frozen_string_literal: true

module Unicodemath
  # Fixed settings: the artifact entries, the engine names and where the
  # bundled artifacts live.
  module Configuration
    # Decimal marker => artifact entry name.
    DECIMAL_ENTRIES = {
      "." => "dot",
      "," => "comma",
      "٫" => "arabic", # ARABIC DECIMAL SEPARATOR
    }.freeze

    ENGINES = %i[auto native ruby].freeze

    ARTIFACT_DIR = File.expand_path("../../artifacts", __dir__)
    DEFAULT_ARTIFACT_PATH = File.join(ARTIFACT_DIR, "unicodemath.json")
    DEFAULT_BINDINGS_PATH = File.join(ARTIFACT_DIR, "unicodemath.bindings.ruby.json")

    # The capture under which the declared bindings carry the legacy tree.
    TREE_CAPTURE = :unicodemath_tree

    # Deepest bracket nesting sent to the native engine off the main thread,
    # where the machine stack is small.
    THREAD_NATIVE_DEPTH = 25
  end
end
