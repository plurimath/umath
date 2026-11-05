# frozen_string_literal: true

module Umath
  # Maps positions in the grammar input back to the caller's text.
  #
  # The grammar runs on the preprocessed text (Preprocessor), which differs
  # from the caller's: non-ASCII characters become character references, a
  # comment and the label are removed, escapes are folded. SourceMap repeats
  # each Preprocessor step on the caller's text while recording, for every
  # character it produces, the caller character it came from. A step that
  # replaces a match gives every produced character the position of the
  # match's first character.
  #
  # Internal: the public parser uses it to report ParseError offsets in the
  # caller's text.
  class SourceMap
    attr_reader :text

    # +input+: the caller's text as valid UTF-8.
    def self.build(input)
      new(input)
    end

    def initialize(input)
      @input = input
      chars, origins = formula(input)
      chars, origins = encode(chars, origins)
      text = chars.join
      text, origins = replace(text, origins, "&#x26;") { "&" }
      text, origins = replace(text, origins, "&#x22;") { "\"" }
      text, origins = remove_comment(text, origins)
      text, origins = replace(text, origins, "\\\\") { "\\" }
      text, origins = replace(text, origins, Preprocessor::U_ESCAPE) { |m| "&#x#{m[1]};" }
      @text, @origins = strip(text, origins)
    end

    # The caller position, as [char_offset, byte_offset], of grammar input
    # character +char_offset+ (the end of the grammar input maps to the end
    # of the formula part of the caller's text).
    def caller_position(char_offset)
      char = if char_offset < @origins.size
               @origins[char_offset]
             elsif @origins.empty?
               @text_end || 0
             else
               @origins.last + 1
             end
      [char, @input[0, char].bytesize]
    end

    private

    # The formula part as characters with their caller positions:
    # Preprocessor.split_label with the protection of "#" inside ✎(...)
    # undone by position.
    def formula(input)
      chars = []
      origins = []
      position = 0
      input.split("\n", -1).each_with_index do |line, index|
        unless index.zero?
          chars << "\n"
          origins << (position - 1)
        end
        protected_line = protect(line)
        protected_line.each { |c, offset| chars << c; origins << (position + offset) }
        position += line.length + 1
      end
      text = chars.join
      cut = text.index("#") || text.length
      chars = chars.first(cut)
      origins = origins.first(cut)
      @text_end = cut.zero? ? 0 : nil
      text, origins = replace(chars.join, origins, Preprocessor::PROTECTED_HASH) { "#" }
      [text.chars, origins]
    end

    # The line's characters with their offsets in it; a protected "#"
    # becomes Preprocessor::PROTECTED_HASH, every character of which keeps
    # the "#"'s offset.
    def protect(line)
      chars = line.chars.each_with_index.to_a
      protected_text = Preprocessor.send(:protect_pen_group, line)
      return chars if protected_text == line

      start = line.index(Preprocessor::PEN_OPEN)
      close = line.rindex(")")
      chars.flat_map do |c, offset|
        if c == "#" && offset > start && offset < close
          Preprocessor::PROTECTED_HASH.chars.map { |p| [p, offset] }
        else
          [[c, offset]]
        end
      end
    end

    def encode(chars, origins)
      out = []
      out_origins = []
      chars.each_with_index do |c, i|
        piece = c.match?(Preprocessor::BASIC) || c.match?(Preprocessor::EXTENDED) ? "&#x#{c.ord.to_s(16)};" : c
        piece.each_char { |p| out << p; out_origins << origins[i] }
      end
      [out, out_origins]
    end

    def replace(text, origins, pattern)
      regexp = pattern.is_a?(Regexp) ? pattern : Regexp.new(Regexp.escape(pattern))
      out = +""
      out_origins = []
      last = 0
      text.scan(regexp) do
        match = Regexp.last_match
        from, to = match.offset(0)
        out << text[last...from]
        out_origins.concat(origins[last...from])
        piece = yield(match)
        out << piece
        out_origins.concat([origins[from]] * piece.length)
        last = to
      end
      out << text[last..]
      out_origins.concat(origins[last..])
      [out, out_origins]
    end

    def remove_comment(text, origins)
      start = text.index(Preprocessor::COMMENT_OPEN) or return [text, origins]
      close = text.rindex(Preprocessor::COMMENT_CLOSE)
      return [text, origins] unless close && close >= start + Preprocessor::COMMENT_OPEN.length

      stop = close + Preprocessor::COMMENT_CLOSE.length
      [text[0...start] + text[stop..], origins[0...start] + origins[stop..]]
    end

    # String#strip: leading whitespace, trailing whitespace and NULs.
    def strip(text, origins)
      stripped = text.strip
      return [text, origins] if stripped.length == text.length

      lead = text.length - text.lstrip.length
      @text_end ||= origins[lead] if stripped.empty?
      [stripped, origins[lead, stripped.length]]
    end
  end
end
