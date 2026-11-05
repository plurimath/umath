# frozen_string_literal: true

module Umath
  # Runs the grammar on the native or Ruby Parsanol engine, always with
  # Parslet-compatible memo decisions (the legacy grammar's mode), maps
  # failures to Umath errors and records the engine that produced the
  # result per thread.
  #
  # Internal.
  module Engine
    LAST_ENGINE_KEY = :umath_last_engine
    OPENING = "([{".chars.freeze
    CLOSING = ")]}".chars.freeze

    module_function

    def last_engine
      Thread.current[LAST_ENGINE_KEY]
    end

    def native_available?
      Parsanol::Native.available?
    rescue LoadError, StandardError
      false
    end

    # The engine (:native or :ruby) that +engine+ (one of ENGINES) runs.
    def resolve(engine)
      case engine
      when :auto then native_available? ? :native : :ruby
      when :ruby then :ruby
      when :native
        return :native if native_available?

        raise EngineUnavailable,
              "engine: :native requested but the Parsanol native extension " \
              "is not available on this platform (#{RUBY_PLATFORM}, Ruby #{RUBY_VERSION})"
      else
        raise ArgumentError,
              "unknown engine #{engine.inspect} (use #{Configuration::ENGINES.map(&:inspect).join(', ')})"
      end
    end

    # Parses +text+ from +entry+ of the parse artifact +artifact+ on +mode+
    # and returns the parse shape. Under +fallback+ (engine: :auto) input
    # too deep for the native engine is rerun on Ruby.
    def run(artifact, entry, text, mode, fallback:)
      shape, ran = run_with_fallback(artifact, entry, text, mode, fallback: fallback)
      record(ran)
      shape
    end

    def run_with_fallback(artifact, entry, text, mode, fallback:)
      if mode == :native && too_deep_for_native_thread?(text)
        record(:native)
        unless fallback
          raise native_too_deep(text, "nesting depth over #{Configuration::THREAD_NATIVE_DEPTH} off the main thread")
        end

        return [run_mode(artifact, entry, text, :ruby), :ruby]
      end

      [run_mode(artifact, entry, text, mode), mode]
    rescue NativeRecursionLimit => e
      record(:native)
      raise native_too_deep(text, e.message) unless fallback

      [run_mode(artifact, entry, text, :ruby), :ruby]
    rescue NestingTooDeep
      raise unless fallback && mode == :native

      [run_mode(artifact, entry, text, :ruby), :ruby]
    end

    def too_deep_for_native_thread?(text)
      return false if Thread.current.equal?(Thread.main)

      depth = 0
      max = 0
      text.each_char do |char|
        if OPENING.include?(char)
          depth += 1
          max = depth if depth > max
        elsif CLOSING.include?(char)
          depth -= 1 if depth.positive?
        end
      end
      max > Configuration::THREAD_NATIVE_DEPTH
    end

    def native_too_deep(text, detail)
      NestingTooDeep.new(
        "UnicodeMath input nests deeper than the native engine's recursion limit " \
        "(#{detail}); use engine: :ruby or engine: :auto",
        input: text, byte_offset: nil, char_offset: nil,
      )
    end

    def run_mode(artifact, entry, text, mode)
      root = artifact.root_atom(entry)
      if mode == :native
        NativeRecursionGuard.watch do
          Parsanol::Native.parse(root, text, compatibility: :parslet)
        end
      else
        root.parse(text, compatibility: :parslet)
      end
    rescue Parsanol::RecursionLimitExceeded => e
      # parsanol 1.3.134+ raises this for native deep nesting.
      raise NativeRecursionLimit, e.message.lines.first.to_s.strip, cause: nil
    rescue Parsanol::ParseFailed => e
      record(mode)
      raise parse_error(e, root, text, mode)
    rescue SystemStackError
      record(mode)
      raise NestingTooDeep.new(
        "UnicodeMath input nests too deeply for the #{mode} engine (Ruby stack exhausted)",
        input: text, byte_offset: nil, char_offset: nil,
      )
    rescue Parsanol::PARG::Error, Parsanol::GrammarError, Parsanol::Native::UnsupportedGrammar => e
      raise ArtifactError, "the grammar artifact cannot be used: #{e.class}: #{e.message}"
    end

    # The legacy grammar runs on the native engine wherever it is available
    # (Parsanol::Parser picks it for Parslet-compatible parses), so the
    # position it reports is the native engine's deepest failure. The Ruby
    # engine reports the same position through a Deepest reporter.
    def parse_error(error, root, text, mode)
      cause = mode == :ruby ? ruby_cause(root, text) : error.parse_failure_cause
      byte = deepest_position(cause)
      char = byte && text.byteslice(0, byte).force_encoding(Encoding::UTF_8).scrub.length
      where = byte ? " at character #{char} (byte #{byte})" : ""
      ParseError.new("UnicodeMath input rejected#{where}: #{error.message.lines.first.to_s.strip[0, 200]}",
                     input: text, byte_offset: byte, char_offset: char)
    end

    def ruby_cause(root, text)
      root.parse(text, compatibility: :parslet, reporter: Parsanol::ErrorReporter::Deepest.new)
      nil
    rescue Parsanol::ParseFailed => e
      e.parse_failure_cause
    rescue SystemStackError
      nil
    end

    # Iterative: the cause tree of deeply nested input is as deep as the
    # input.
    def deepest_position(cause)
      deepest = nil
      stack = [cause].compact
      until stack.empty?
        node = stack.pop
        deepest = node.position if node.position && (deepest.nil? || node.position > deepest)
        stack.concat(node.children.compact)
      end
      deepest
    end

    def record(mode)
      Thread.current[LAST_ENGINE_KEY] = mode
    end

    private_class_method :run_with_fallback, :native_too_deep, :run_mode, :parse_error,
                         :ruby_cause, :deepest_position, :record, :too_deep_for_native_thread?
  end
end
