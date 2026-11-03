# frozen_string_literal: true

require_relative "lib/unicodemath/version"

Gem::Specification.new do |spec|
  spec.name = "unicodemath"
  spec.version = Unicodemath::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "UnicodeMath parser by Plurimath."
  spec.description = <<~DESCRIPTION
    UnicodeMath parser extracted from Plurimath: a compiled Parsanol grammar
    whose parse result is a typed UnicodeMath model declared with LutaML
    Model.
  DESCRIPTION

  spec.homepage = "https://github.com/plurimath/unicodemath"
  spec.license = "BSD-2-Clause"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "artifacts/**/*", "data/unicodemath-symbols.json", "model/**/*", "docs/**/*",
        "README.adoc", "LICENSE.md"]
      .select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "lutaml-model", "~> 0.8", ">= 0.8.162"
  spec.add_dependency "parsanol", "~> 1.3", ">= 1.3.131"

  spec.metadata["rubygems_mfa_required"] = "true"
end
