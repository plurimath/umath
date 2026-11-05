# frozen_string_literal: true

require "json"

module Umath
  # Symbol resolution: the separate pass after model construction that
  # gives every Model::MathSymbol its Unicode value and kind from the
  # exported symbol catalog (data/umath-symbols.json, written by
  # scripts/export_symbols.rb from the pinned Plurimath commit).
  #
  # Lookup is the legacy one: the spelling with surrounding whitespace
  # removed, exactly as the grammar matched it.
  module Symbols
    FORMAT = "umath-symbol-catalog/1"
    CHARACTER_REFERENCE = /&#(?:x(\h{1,6})|(\d{1,7}));/

    @catalog = nil
    @lock = Mutex.new

    module_function

    # The catalog: spelling => [value, kind].
    def catalog
      @lock.synchronize { @catalog ||= load(Configuration::SYMBOLS_PATH) }
    end

    def load(path)
      doc = JSON.parse(File.read(path, encoding: "UTF-8"))
      raise ArtifactError, "symbol catalog #{path} has format #{doc['format'].inspect}, not #{FORMAT}" unless doc["format"] == FORMAT

      doc.fetch("symbols").transform_values { |entry| [entry.fetch("value").freeze, entry.fetch("kind").freeze].freeze }.freeze
    rescue SystemCallError, JSON::ParserError, KeyError, TypeError, NoMethodError => e
      raise ArtifactError, "symbol catalog #{path} cannot be used: #{e.class}: #{e.message.lines.first&.strip}"
    end

    # [value, kind] for +spelling+.
    def lookup(spelling)
      catalog.fetch(spelling.strip) { [decode(spelling), "unlisted"] }
    end

    # Fills value and kind of every node under +node+ (a model instance)
    # that holds a spelling: each Model::MathSymbol, and the symbol nodes
    # (SymbolNode, OpenParen, ...) whose text the grammar captured as
    # spelling. Iterative over the declared attributes; returns +node+.
    def resolve(node)
      stack = [node]
      until stack.empty?
        current = stack.pop
        attributes = current.class.attributes
        current.value, current.kind = lookup(current.spelling) if attributes.key?(:spelling) && current.spelling
        attributes.each_key do |name|
          value = current.public_send(name)
          case value
          when Lutaml::Model::Serializable then stack << value
          when ::Array then value.each { |v| stack << v if v.is_a?(Lutaml::Model::Serializable) }
          end
        end
      end
      node
    end

    # +text+ with its numeric character references decoded.
    def decode(text)
      text.gsub(CHARACTER_REFERENCE) do
        code = ::Regexp.last_match(1) ? ::Regexp.last_match(1).to_i(16) : ::Regexp.last_match(2).to_i
        valid = code <= 0x10FFFF && !(0xD800..0xDFFF).cover?(code)
        valid ? [code].pack("U") : ::Regexp.last_match(0)
      end
    end
  end
end
