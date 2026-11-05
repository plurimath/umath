# frozen_string_literal: true

require "json"
require "tmpdir"
require "yaml"
require "umath"
require_relative "support/capture_shapes"
require_relative "../../scripts/model_tree"
require_relative "../../scripts/unwrap"

module ModelSpecHelpers
  ROOT = File.expand_path("../..", __dir__)
  NORMALIZED_RULES = File.join(ROOT, "grammars", "umath.normalized-rules.json")

  def self.shapes
    @shapes ||= Umath::Spec::CaptureShapes.new(NORMALIZED_RULES)
  end

  def model_classes
    Umath::Model.constants.sort.map { |c| Umath::Model.const_get(c) }
                      .select { |k| k.is_a?(Class) && k < Lutaml::Model::Serializable }
  end

  def parse(input, **options)
    Umath.parse(input, engine: :ruby, **options)
  end

  # True when the document of +input+ holds exactly the bound tree.
  def lossless?(input, **options)
    raw = Umath::RawParser.parse(input, engine: :ruby, **options)
    UmathModelTree.lossless?(parse(input, **options).expression, raw.model_data)
  end
end

RSpec.configure do |config|
  config.include ModelSpecHelpers, file_path: %r{/spec/model/}
end
