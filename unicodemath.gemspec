# frozen_string_literal: true

require_relative "lib/unicodemath/version"

Gem::Specification.new do |spec|
  spec.name = "unicodemath"
  spec.version = Unicodemath::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "UnicodeMath parser by Plurimath."
  spec.description = <<~DESCRIPTION
    UnicodeMath parser being extracted from Plurimath: a compiled Parsanol
    grammar artifact with declared syntax bindings. The public parser API
    is not usable yet.
  DESCRIPTION

  spec.homepage = "https://github.com/plurimath/unicodemath"
  spec.license = "BSD-2-Clause"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "artifacts/**/*", "docs/**/*", "README.adoc", "LICENSE.md"]
      .select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "parsanol", "~> 1.3", ">= 1.3.131"

  spec.metadata["rubygems_mfa_required"] = "true"
end
