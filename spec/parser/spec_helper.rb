# frozen_string_literal: true

require "json"
require "yaml"
require "umath"
require_relative "../../scripts/oracle/canonical"
require_relative "../../scripts/unwrap"

module ParserSpecHelpers
  ROOT = File.expand_path("../..", __dir__)
  FIXTURES = File.join(__dir__, "fixtures", "oracle")

  # The decimal marker Plurimath.configuration.decimal gives for each
  # locale used by an oracle inventory (Plurimath::Formatter::SupportedLocales
  # at the pinned oracle commit), so a row's locale option selects the same
  # grammar entry here.
  LOCALE_DECIMALS = {
    nil => ".", "en" => ".", "fr" => ",", "de" => ",", "ar" => "٫", "fa" => "٫",
  }.freeze

  def canonical(value)
    UmathOracle::Canonical.dump(value)
  end

  # The legacy tree for a raw tree of the normalized grammar.
  def legacy(tree)
    UmathUnwrap.call(tree)
  end

  def canonical_string(value)
    UmathOracle::Canonical.string(value)
  end

  def native_required?
    ENV["UNICODEMATH_REQUIRE_NATIVE"] == "1"
  end
end

RSpec.configure do |config|
  config.include ParserSpecHelpers
end
