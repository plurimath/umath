# frozen_string_literal: true

require "open3"
require "rbconfig"

# `require "unicodemath"` in a fresh process: the parser and model load on
# their own, without Plurimath.
RSpec.describe "require \"unicodemath\"" do
  root = File.expand_path("../..", __dir__)

  def run_ruby(root, script)
    Open3.capture3(RbConfig.ruby, "-I", File.join(root, "lib"), "-runicodemath", "-e", script, chdir: root)
  end

  it "parses into the typed model without loading Plurimath" do
    out, err, status = run_ruby(root, <<~RUBY)
      d = Unicodemath.parse("a/b", engine: :ruby)
      raise "Plurimath is loaded" if defined?(Plurimath)
      raise "Plurimath files are loaded" unless $LOADED_FEATURES.grep(%r{/plurimath[/.]}).empty?
      frac = d.expression.frac
      puts [d.class, frac.numerator.atom.alphanumeric.spelling, Unicodemath::VERSION].join(" ")
    RUBY
    expect(status).to be_success, err
    expect(out).to eq("Unicodemath::Model::Document a 0.1.0\n")
  end

  it "raises ParseError with offsets into the caller's input" do
    out, err, status = run_ruby(root, <<~RUBY)
      begin
        Unicodemath.parse("α)", engine: :ruby)
      rescue Unicodemath::ParseError => e
        puts [e.class.ancestors.include?(Unicodemath::Error), e.char_offset, e.byte_offset].inspect
      end
    RUBY
    expect(status).to be_success, err
    expect(out).to eq("[true, 1, 2]\n")
  end
end
