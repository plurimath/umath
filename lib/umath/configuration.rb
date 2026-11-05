# frozen_string_literal: true

module Umath
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
    DEFAULT_ARTIFACT_PATH = File.join(ARTIFACT_DIR, "umath.json")
    DEFAULT_BINDINGS_PATH = File.join(ARTIFACT_DIR, "umath.bindings.ruby.json")
    DATA_DIR = File.expand_path("../../data", __dir__)
    SYMBOLS_PATH = File.join(DATA_DIR, "umath-symbols.json")

    # The capture under which the declared bindings carry the raw tree.
    TREE_CAPTURE = :umath_tree
    # The binding path under which they carry the same tree as plain data,
    # the input of the typed model's construction.
    MODEL_BINDING = :model

    # Deepest bracket nesting sent to the native engine off the main thread,
    # where the machine stack is small.
    THREAD_NATIVE_DEPTH = 25
  end
end
