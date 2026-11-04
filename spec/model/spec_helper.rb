# frozen_string_literal: true

require "json"
require "tmpdir"
require "yaml"
require "unicodemath"
require_relative "support/capture_shapes"
require_relative "../../scripts/model_tree"
require_relative "../../scripts/unwrap"

module ModelSpecHelpers
  ROOT = File.expand_path("../..", __dir__)
  NORMALIZED_RULES = File.join(ROOT, "grammars", "unicodemath.normalized-rules.json")

  def self.shapes
    @shapes ||= Unicodemath::Spec::CaptureShapes.new(NORMALIZED_RULES)
  end

  def model_classes
    Unicodemath::Model.constants.sort.map { |c| Unicodemath::Model.const_get(c) }
                      .select { |k| k.is_a?(Class) && k < Lutaml::Model::Serializable }
  end

  def parse(input, **options)
    Unicodemath.parse(input, engine: :ruby, **options)
  end

  # True when the document of +input+ holds exactly the bound tree.
  def lossless?(input, **options)
    raw = Unicodemath::RawParser.parse(input, engine: :ruby, **options)
    UnicodemathModelTree.lossless?(parse(input, **options).expression, raw.model_data)
  end
end

RSpec.configure do |config|
  config.include ModelSpecHelpers, file_path: %r{/spec/model/}
end
