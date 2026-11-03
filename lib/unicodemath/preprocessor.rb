# frozen_string_literal: true

module Unicodemath
  # The legacy UnicodeMath preprocessing (Plurimath::UnicodeMath::Parser at
  # the pinned oracle commit), step for step. The grammar runs on its
  # result, never on the caller's text. See docs/parser-contract.adoc,
  # "Preprocessing".
  #
  # Internal: the public parser owns this step.
  module Preprocessor
    # +text+ is the grammar input, or nil when the input has no formula part
    # (an empty input, or one made only of label separators; the legacy code
    # raises NoMethodError there). +label+ is the text after the last "#",
    # set only when +labeled+.
    Result = Struct.new(:text, :label, :labeled, keyword_init: true)

    PEN_GROUP = /✎\(.*(\#).*\)/
    PROTECTED_HASH = "\"replacement\""
    # HTMLEntities (xhtml1 flavour) with the :hexadecimal instruction: the
    # basic characters first, then everything outside printable ASCII.
    BASIC = /[<>'"&]/
    EXTENDED = /[^\u{20}-\u{7E}]/
    COMMENT = /&#x2af7;.*&#x2af8;/
    U_ESCAPE = /\\u([\da-fA-F]{1,5})\w{0,5}/

    module_function

    # +input+ must be a valid UTF-8 String.
    def call(input)
      formula, label, labeled = split_label(input)
      return Result.new(text: nil, label: label, labeled: labeled) if formula.nil?

      text = encode(formula)
      text = text.gsub("&#x26;", "&")
      text = text.gsub("&#x22;", "\"")
      text = text.gsub(COMMENT, "")
      text = text.gsub("\\\\", "\\")
      text = text.gsub(U_ESCAPE) { "&#x#{::Regexp.last_match(1)};" }
      Result.new(text: text.strip, label: label, labeled: labeled)
    end

    # A "#" inside a ✎(...) group is protected; the text is then split on
    # "#": the first part is the formula and, if there is more than one
    # part, the last one is the label. Parts in between are dropped.
    def split_label(input)
      text = input.gsub(PEN_GROUP) { |group| group.gsub("#", PROTECTED_HASH) }
      parts = text.split("#")
      return [nil, nil, false] if parts.empty?

      formula = parts.first.gsub(PROTECTED_HASH, "#")
      parts.size > 1 ? [formula, parts.last, true] : [formula, nil, false]
    end

    def encode(text)
      text = text.gsub(BASIC) { |char| hex(char) }
      text.gsub(EXTENDED) { |char| hex(char) }
    end

    def hex(char)
      "&#x#{char.ord.to_s(16)};"
    end

    private_class_method :split_label, :encode, :hex
  end
end
