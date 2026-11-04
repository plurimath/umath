# frozen_string_literal: true

module Unicodemath
  # The public parser behind Unicodemath.parse: preprocessing, grammar and
  # bindings (RawParser), typed model construction by lutaml-model from the
  # declared attribute types, then symbol resolution (Symbols.resolve).
  module Parser
    module_function

    def parse(input, decimal: ".", engine: :ruby)
      text = RawParser.normalize_input(input)
      raw = begin
        RawParser.parse(text, decimal: decimal, engine: engine)
      rescue NestingTooDeep => e
        raise NestingTooDeep.new(e.message, input: text, byte_offset: nil, char_offset: nil)
      rescue ParseError => e
        raise relocate(e, text)
      end
      # Input without a formula part (empty, or only "#" label separators):
      # an empty Document. The legacy facade fails there with NoMethodError,
      # so there is no legacy result to keep; amath returns an empty result
      # for empty input too.
      return Model::Document.new(label: raw.label, decimal: decimal) if raw.text.nil?

      build(raw, decimal, text)
    end

    def build(raw, decimal, text)
      document = Model::Document.new(expression: raw.model_data, label: raw.label, decimal: decimal)
      Symbols.resolve(document)
    rescue SystemStackError
      raise NestingTooDeep.new("UnicodeMath input nests too deeply to build its model (Ruby stack exhausted)",
                               input: text, byte_offset: nil, char_offset: nil)
    end

    # The grammar's error, with its offsets moved from the grammar input to
    # the caller's text.
    def relocate(error, text)
      char = byte = nil
      if error.char_offset
        char, byte = SourceMap.build(text).caller_position(error.char_offset)
      end
      where = char ? " at character #{char} (byte #{byte})" : ""
      detail = error.message.sub(/\AUnicodeMath input rejected( at character \d+ \(byte \d+\))?: /, "")
      ParseError.new("UnicodeMath input rejected#{where}: #{detail}", input: text, byte_offset: byte, char_offset: char)
    end

    private_class_method :build, :relocate
  end
end
