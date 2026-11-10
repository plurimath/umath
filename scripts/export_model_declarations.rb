# frozen_string_literal: true

# Export data declarations with explicit identity JSON mappings. This is a
# portable data projection; it does not change the Ruby model runtime or claim
# byte identity with every Ruby serializer configuration.
require "digest"
require "fileutils"
require "json"
require "open3"
require "lutaml/model"
require "lutaml/model/lml"
require_relative "../lib/umath/model"

unless Lutaml::Model::Lml.respond_to?(:export_bundle)
  abort "The LML declaration exporter is required (lutaml-model#1116)."
end

root = File.expand_path("..", __dir__)
output = File.expand_path(ARGV.fetch(0, "schema/umath.bundle.json"), root)
classes = Umath::Model.constants(false).filter_map do |name|
  value = Umath::Model.const_get(name)
  value if value.is_a?(Class) && value < Lutaml::Model::Serializable
end.uniq
classes.each do |klass|
  next if klass.mappings.key?(:json)

  names = klass.attributes.keys
  klass.json do
    names.each { |name| map name.to_s, to: name }
  end
end

bundle = Lutaml::Model::Lml.export_bundle(Umath::Model::Document).to_h
bytes = JSON.pretty_generate(bundle) + "\n"
FileUtils.mkdir_p(File.dirname(output))
File.binwrite(output, bytes)
source_file = Lutaml::Model::Lml.method(:export_bundle).source_location.first
revision, _error, status = Open3.capture3("git", "-C", File.dirname(source_file), "rev-parse", "HEAD")
manifest = {
  "projection" => "implicit-json-attribute-mappings-v1",
  "definition_repository" => "https://github.com/plurimath/umath",
  "definition_files_sha256" => Dir[File.join(root, "lib/umath/model{,/**}/*.rb"),
                                  File.join(root, "lib/umath/model.rb")].uniq.sort.to_h do |file|
    [file.delete_prefix(root + "/"), Digest::SHA256.file(file).hexdigest]
  end,
  "producer_script_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "exporter_revision" => status.success? ? revision.strip : nil,
  "model_count" => bundle.fetch("models").length,
  "files" => {File.basename(output) => Digest::SHA256.hexdigest(bytes)},
}
File.write(File.join(File.dirname(output), "manifest.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate(models: manifest.fetch("model_count"), sha256: manifest.fetch("files").values.first)
