# frozen_string_literal: true

require "open3"
require "rbconfig"

# `require "umath"` in a fresh process: the parser and model load on
# their own, without Plurimath.
RSpec.describe "require \"umath\"" do
  root = File.expand_path("../..", __dir__)

  def run_ruby(root, script)
    Open3.capture3(RbConfig.ruby, "-I", File.join(root, "lib"), "-rumath", "-e", script, chdir: root)
  end

  it "parses into the typed model without loading Plurimath" do
    out, err, status = run_ruby(root, <<~RUBY)
      d = Umath.parse("a/b", engine: :ruby)
      raise "Plurimath is loaded" if defined?(Plurimath)
      raise "Plurimath files are loaded" unless $LOADED_FEATURES.grep(%r{/plurimath[/.]}).empty?
      frac = d.expression.frac
      puts [d.class, frac.numerator.atom.alphanumeric.spelling, Umath::VERSION].join(" ")
    RUBY
    expect(status).to be_success, err
    expect(out).to eq("Umath::Model::Document a 0.1.0\n")
  end

  it "raises ParseError with offsets into the caller's input" do
    out, err, status = run_ruby(root, <<~RUBY)
      begin
        Umath.parse("α)", engine: :ruby)
      rescue Umath::ParseError => e
        puts [e.class.ancestors.include?(Umath::Error), e.char_offset, e.byte_offset].inspect
      end
    RUBY
    expect(status).to be_success, err
    expect(out).to eq("[true, 1, 2]\n")
  end
end
