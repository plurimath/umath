# frozen_string_literal: true

require "json"
require "tmpdir"
require "yaml"
require "unicodemath"
require_relative "support/capture_shapes"

module ModelSpecHelpers
  ROOT = File.expand_path("../..", __dir__)
  EXPORT = File.join(ROOT, "data", "unicodemath-grammar.json")

  def self.shapes
    @shapes ||= Unicodemath::Spec::CaptureShapes.new(EXPORT)
  end

  def model_classes
    Unicodemath::Model.constants.sort.map { |c| Unicodemath::Model.const_get(c) }
                      .select { |k| k.is_a?(Class) && k < Unicodemath::Model::Node }
  end

  def parse(input, **options)
    Unicodemath.parse(input, engine: :ruby, **options)
  end

  def capture_tree_equal?(input, **options)
    raw = Unicodemath::RawParser.parse(input, engine: :ruby, **options)
    document = parse(input, **options)
    Unicodemath::Model::CaptureTree.dump(document.expression) ==
      Unicodemath::Model::CaptureTree.normalize(raw.model_data)
  end
end

RSpec.configure do |config|
  config.include ModelSpecHelpers, file_path: %r{/spec/model/}
end
