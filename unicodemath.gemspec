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

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/plurimath/unicodemath"
  spec.metadata["changelog_uri"] = "https://github.com/plurimath/unicodemath/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Only what the gem reads at run time (the code, the parse and Ruby
  # bindings artifacts and the symbol catalog), plus its documentation.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "artifacts/unicodemath.json", "artifacts/unicodemath.bindings.ruby.json",
        "data/unicodemath-symbols.json", "docs/*.adoc", "README.adoc", "CHANGELOG.md", "LICENSE.md"]
      .select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "lutaml-model", "~> 0.8", ">= 0.8.162"
  spec.add_dependency "parsanol", "~> 1.3", ">= 1.3.134"
end
