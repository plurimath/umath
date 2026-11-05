# frozen_string_literal: true

# Writes data/umath-symbols.json, the symbol catalog the typed model's
# symbol resolution reads (Umath::Symbols).
#
# Usage (the one-time provenance step, like generate_grammar.rb --export):
#
#   BUNDLE_GEMFILE=scripts/oracle/Gemfile BUNDLE_PATH=vendor/oracle-bundle \
#     bundle exec ruby scripts/export_symbols.rb ORACLE_CHECKOUT
#
# ORACLE_CHECKOUT is a clean Plurimath checkout at ORACLE_COMMIT. The script
# loads it, reads the catalog the legacy transform resolves symbols with
# (Plurimath::Utility.all_symbols_classes(:unicodemath): every UnicodeMath
# spelling of every Math::Symbols::Symbol and Math::Symbols::Paren class) and
# records, per spelling, the Unicode text the class writes as UnicodeMath and
# whether it is a symbol or a paren. Neither the build nor the gem loads
# Plurimath; they read only the exported file.

require "digest"
require "json"

ROOT = File.expand_path("..", __dir__)
OUT = File.join(ROOT, "data/umath-symbols.json")
FORMAT = "umath-symbol-catalog/1"
ORACLE_REPOSITORY = "https://github.com/plurimath/plurimath"
ORACLE_COMMIT = "e7ab4a5186c9be96f62d670574bc2c72f9365ad4"
SOURCE_FILES = %w[
  lib/plurimath/utility.rb
  lib/plurimath/math/symbols/symbol.rb
  lib/plurimath/math/symbols/paren.rb
].freeze

checkout = File.expand_path(ARGV.fetch(0) { abort "usage: ruby scripts/export_symbols.rb ORACLE_CHECKOUT" })
head = IO.popen(["git", "-C", checkout, "rev-parse", "HEAD"], &:read).strip
abort "#{checkout} is at #{head}, expected #{ORACLE_COMMIT}" unless head == ORACLE_COMMIT
dirty = IO.popen(["git", "-C", checkout, "status", "--porcelain", "--untracked-files=no"], &:read)
abort "#{checkout} has local changes" unless dirty.strip.empty?

$LOAD_PATH.unshift(File.join(checkout, "lib"))
require "plurimath"
require "plurimath/version"
loaded = $LOADED_FEATURES.grep(%r{/lib/plurimath\.rb\z}).first
abort "plurimath was loaded from #{loaded}, not #{checkout}" unless loaded&.start_with?(checkout)

utility = Plurimath::Utility
parens = utility.parens_hash(:unicodemath)
# The lookup the transform uses: symbols merged with parens (a paren wins).
catalog = utility.all_symbols_classes(:unicodemath)
entries = catalog.keys.sort.to_h do |spelling|
  klass = catalog.fetch(spelling)
  kind = parens[spelling].equal?(klass) ? "paren" : "symbol"
  [spelling, { "value" => klass.new.to_unicodemath.to_s, "kind" => kind }]
end

doc = {
  "format" => FORMAT,
  "oracle" => {
    "repository" => ORACLE_REPOSITORY,
    "commit" => ORACLE_COMMIT,
    "plurimath" => Plurimath::VERSION,
    "ruby" => RUBY_VERSION,
    "files" => SOURCE_FILES.to_h { |f| [f, "sha256:#{Digest::SHA256.file(File.join(checkout, f)).hexdigest}"] },
  },
  "source" => "Plurimath::Utility.all_symbols_classes(:unicodemath); value is the " \
              "class's to_unicodemath, kind is paren for Math::Symbols::Paren classes",
  "symbols" => entries,
}
File.binwrite(OUT, "#{JSON.pretty_generate(doc)}\n")
puts "symbols #{entries.size} (#{entries.count { |_, v| v['kind'] == 'paren' }} parens)"
puts "wrote #{OUT} sha256:#{Digest::SHA256.file(OUT).hexdigest}"
