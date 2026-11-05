# frozen_string_literal: true

# Test-only construction check: is the typed model lossless with respect to
# the bound tree it was built from? lutaml-model ignores keys a class does
# not declare, so a missing declaration would otherwise lose data silently.
# Used by spec/model and scripts/replay_corpus.rb. Not part of the gem.
module UmathModelTree
  # Filled by the symbol pass, not by construction.
  DERIVED = %i[value kind].freeze

  module_function

  # The plain data of a model: String keys, the non-nil attributes, Arrays
  # and Strings. Raises TypeError when an attribute holds a value that is not
  # of its declared type.
  def dump(value)
    case value
    when Array then value.map { |v| dump(v) }
    when Lutaml::Model::Serializable
      attributes = value.class.attributes
      names = attributes.keys
      names -= DERIVED if names.include?(:spelling)
      names.each_with_object({}) do |name, out|
        held = value.public_send(name)
        next if held.nil?

        check_type(value.class, name, attributes.fetch(name), held)
        out[name.to_s] = dump(held)
      end
    else value
    end
  end

  # +value+ (bound data or a dump) with String keys sorted at every level and
  # String leaves, so that two trees compare by content.
  def plain(value)
    case value
    when Hash then value.map { |k, v| [k.to_s, plain(v)] }.sort_by(&:first).to_h
    when Array then value.map { |v| plain(v) }
    when nil then nil
    else value.to_s
    end
  end

  # True when the model +node+ holds exactly the bound +data+.
  def lossless?(node, data)
    plain(dump(node)) == plain(data)
  end

  def check_type(klass, name, attribute, held)
    type = attribute.type
    expected = type.is_a?(Class) && type <= Lutaml::Model::Serializable ? type : ::String
    items = attribute.collection? ? held : [held]
    return if items.is_a?(::Array) && items.all? { |item| item.is_a?(expected) }

    raise TypeError, "#{klass.name}##{name} holds #{held.inspect[0, 80]}, not #{expected.name}"
  end

  private_class_method :check_type
end
