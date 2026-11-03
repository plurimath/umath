# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "unicodemath"
  # Placeholder until the parser and lib/unicodemath/version.rb land.
  spec.version = "0.0.0"
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "UnicodeMath parser by Plurimath."
  spec.description = <<~DESCRIPTION
    UnicodeMath parser being extracted from Plurimath. Not usable yet.
  DESCRIPTION

  spec.homepage = "https://github.com/plurimath/unicodemath"
  spec.license = "BSD-2-Clause"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "docs/**/*", "README.adoc", "LICENSE.md"]
      .select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]

  spec.metadata["rubygems_mfa_required"] = "true"
end
