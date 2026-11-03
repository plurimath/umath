# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "the grammar build inputs" do
  let(:export) { JSON.parse(File.binread(ArtifactSpecHelpers::EXPORT)) }

  it "is generated from the committed export (generate_grammar.rb --check)" do
    out, status = Open3.capture2e(RbConfig.ruby, File.join(ArtifactSpecHelpers::ROOT, "scripts", "generate_grammar.rb"),
                                  "--check")
    expect(status).to be_success, out
  end

  it "records the pinned oracle and its source files" do
    expect(export["format"]).to eq("unicodemath-grammar-export/1")
    expect(export["oracle"]).to include("repository" => "https://github.com/plurimath/plurimath",
                                        "commit" => "e7ab4a5186c9be96f62d670574bc2c72f9365ad4")
    expect(export.dig("oracle", "files").keys).to include("lib/plurimath/unicode_math/parse.rb",
                                                          "lib/plurimath/unicode_math/constants.rb")
    expect(export.dig("oracle", "files").values).to all(match(/\Asha256:\h{64}\z/))
  end

  it "carries the Plurimath inputs the legacy grammar reads when it loads" do
    wrappers = export.dig("inputs", "wrapper_symbols", "values")
    expect(wrappers).not_to be_empty
    expect(wrappers).to all(match(/\A"P\{[^}]+\}"\z/))
    markers = export.dig("inputs", "decimal_markers", "values")
    expect(markers.to_h { |m| [m["marker"], [m["entry"], m["grammar_literal"]]] })
      .to eq("," => %w[comma ,], "." => %w[dot .], "٫" => ["arabic", "&#x66b;"])
  end

  it "names the export checksum in the generated grammar's header" do
    header = File.foreach(ArtifactSpecHelpers::GRAMMAR).first(5).join
    expect(header).to include("data/unicodemath-grammar.json sha256:#{Digest::SHA256.file(ArtifactSpecHelpers::EXPORT).hexdigest}")
  end

  it "is pure ASCII" do
    expect(File.binread(ArtifactSpecHelpers::GRAMMAR)).to be_ascii_only
  end
end
