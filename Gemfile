# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"

# The artifact job in CI recompiles with the compiler the committed artifact
# records (artifacts/unicodemath.checksums.txt, compiler_version).
gem "parsanol", ENV["PARSANOL_VERSION"] if ENV["PARSANOL_VERSION"]
