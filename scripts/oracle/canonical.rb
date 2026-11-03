# frozen_string_literal: true

module UnicodemathOracle
  # Converts Ruby values into a tagged, JSON-safe form that keeps every
  # distinction the parity comparison needs (see docs/parser-contract.adoc,
  # "Canonical tagged form"):
  #
  # * hash vs array, with hash entries in insertion order;
  # * symbol vs string, for keys and values;
  # * nil vs a missing key (a missing key is simply absent from "entries");
  # * empty string vs empty array;
  # * parser slices with their text, character offset and byte offset;
  # * the class of every other object, with its instance variables in
  #   definition order.
  #
  # Strings keep their exact bytes: valid UTF-8 is stored as text, anything
  # else as base64. Numbers are stored as their Ruby string form and are never
  # converted to floats.
  module Canonical
    module_function

    SLICE_CLASSES = %w[Parsanol::Slice Parslet::Slice].freeze

    def dump(value)
      encode(value, {})
    end

    def string(value)
      bytes = value.b
      utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
      if utf8.valid_encoding?
        { "t" => "str", "v" => utf8 }
      else
        { "t" => "bytes", "b64" => [bytes].pack("m0") }
      end
    end

    def encode(value, seen)
      case value
      when nil then { "t" => "nil" }
      when true then { "t" => "true" }
      when false then { "t" => "false" }
      when String then string(value)
      when Symbol then { "t" => "sym", "v" => value.to_s }
      when Integer then { "t" => "int", "v" => value.to_s }
      when Float then { "t" => "float", "v" => value.to_s }
      when Hash then hash(value, seen)
      when Array then array(value, seen)
      else
        return slice(value) if SLICE_CLASSES.include?(value.class.name)

        object(value, seen)
      end
    end

    def hash(value, seen)
      guard(value, seen) do
        entries = value.map { |k, v| [encode(k, seen), encode(v, seen)] }
        { "t" => "hash", "entries" => entries }
      end
    end

    def array(value, seen)
      guard(value, seen) do
        { "t" => "array", "items" => value.map { |v| encode(v, seen) } }
      end
    end

    def slice(value)
      out = { "t" => "slice", "class" => value.class.name }
      out.merge!(string(value.to_s).transform_keys { |k| k == "t" ? "text_kind" : k })
      out["charpos"] = value.charpos if value.respond_to?(:charpos)
      out["bytepos"] = value.bytepos if value.respond_to?(:bytepos)
      out["offset"] = value.offset if value.respond_to?(:offset)
      out
    end

    def object(value, seen)
      guard(value, seen) do
        ivars = value.instance_variables.map do |name|
          [name.to_s, encode(value.instance_variable_get(name), seen)]
        end
        out = { "t" => "obj", "class" => value.class.name || value.class.to_s,
                "ivars" => ivars }
        if ivars.empty? && !value.class.name.nil?
          # Value objects such as BigDecimal or Rational carry no ivars.
          out["to_s"] = string(value.to_s)
        end
        out
      end
    end

    # Records a back-reference instead of recursing forever on cycles.
    def guard(value, seen)
      id = value.object_id
      return { "t" => "cycle", "class" => value.class.name } if seen[id]

      seen[id] = true
      begin
        yield
      ensure
        seen.delete(id)
      end
    end

    # Hex object addresses in exception messages change on every run.
    def scrub_message(message)
      message.to_s.gsub(/0x[0-9a-f]{6,}/, "0xADDR")
    end
  end
end
