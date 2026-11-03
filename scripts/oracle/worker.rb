# frozen_string_literal: true

# Legacy oracle worker. Runs in its own process, inside the isolated oracle
# bundle (scripts/oracle/Gemfile), with the pinned Plurimath checkout on the
# load path. Reads one request from stdin and writes one JSON result to file
# descriptor 3. See docs/parser-contract.adoc for the four boundaries.
#
# Every boundary records its own outcome. Exceptions raised by the oracle are
# data; only a missing or unreadable result is treated as a crash by the
# supervisor.

require "json"
require_relative "harness"

C = UnicodemathOracle::Canonical
WRITERS = %w[asciimath latex mathml unicodemath omml html].freeze
REFUSAL_CLASSES = %w[Parsanol::ParseFailed Parslet::ParseFailed].freeze

def error_data(error)
  data = { "class" => error.class.name, "message" => C.scrub_message(error.message) }
  data["cause_class"] = error.cause.class.name if error.cause
  data
end

def decode_input(tagged)
  case tagged["t"]
  when "str" then tagged["v"].dup.force_encoding(Encoding::UTF_8)
  when "bytes" then tagged["b64"].unpack1("m0").force_encoding(Encoding::UTF_8)
  else raise ArgumentError, "unknown input tag #{tagged['t'].inspect}"
  end
end

def facade_options(options)
  options.to_h { |k, v| [k.to_sym, v] }
end

# Same scoping as Plurimath::Math.parse_with_configuration, so the grammar
# and preprocessing boundaries see the decimal marker the facade would.
def with_locale(options)
  return yield unless options.key?("locale")

  Plurimath.with_configuration do |config|
    config.locale = Plurimath::Formatter::SupportedLocales.key_for!(options["locale"])
    yield
  end
end

def capture_preprocess(input, options)
  parser = with_locale(options) { Plurimath::UnicodeMath::Parser.new(input) }
  label_defined = parser.instance_variable_defined?(:@splitted)
  boundary = { "status" => "ok", "text" => C.string(parser.text),
               "label_defined" => label_defined }
  boundary["label"] = C.dump(parser.instance_variable_get(:@splitted)) if label_defined
  [boundary, parser.text]
rescue StandardError, SystemStackError => e
  [{ "status" => "error", "error" => error_data(e) }, nil]
end

def capture_raw(text, options)
  tree = with_locale(options) { Plurimath::UnicodeMath::Parse.new.parse(text) }
  { "status" => "ok", "tree" => C.dump(tree) }
rescue StandardError, SystemStackError => e
  status = REFUSAL_CLASSES.include?(e.class.name) ? "refused" : "error"
  { "status" => status, "error" => error_data(e) }
end

def parse_formula(input, options)
  Plurimath::Math.parse(input, :unicode, **facade_options(options))
end

def capture_model(input, options)
  formula = parse_formula(input, options)
  pristine = Marshal.load(Marshal.dump(formula)) rescue nil # rubocop:disable Style/RescueModifier
  [{ "status" => "ok", "formula" => C.dump(formula) }, pristine || formula]
rescue StandardError, SystemStackError => e
  [{ "status" => "error", "error" => error_data(e) }, nil]
end

# Each writer gets its own copy of the formula, so one writer cannot change
# what the next one sees. The copy is a Marshal deep copy of the model
# boundary's formula; if a formula cannot be marshalled, it is parsed again.
def fresh_formula(formula, input, options)
  Marshal.load(Marshal.dump(formula))
rescue TypeError
  parse_formula(input, options)
end

def capture_writers(formula, input, options)
  WRITERS.to_h do |writer|
    output = fresh_formula(formula, input, options).public_send("to_#{writer}")
    [writer, { "status" => "ok", "output" => C.string(output.to_s) }]
  rescue StandardError, SystemStackError => e
    [writer, { "status" => "error", "error" => error_data(e) }]
  end
end

def environment
  {
    "ruby" => RUBY_VERSION,
    "plurimath" => Plurimath::VERSION,
    "parsanol" => (defined?(Parsanol::VERSION) ? Parsanol::VERSION : nil),
    "parslet" => Gem.loaded_specs["parslet"]&.version&.to_s,
    "htmlentities" => Gem.loaded_specs["htmlentities"]&.version&.to_s,
  }
end

def outcome_for(preprocess, raw)
  return "errored" unless preprocess["status"] == "ok"

  case raw["status"]
  when "ok" then "succeeded"
  when "refused" then "refused"
  else "errored"
  end
end

result_io = IO.for_fd(3, "wb")
request = JSON.parse($stdin.read)
require "plurimath"
require "plurimath/version"

input = decode_input(request.fetch("input"))
options = request.fetch("options")
preprocess, text = capture_preprocess(input, options)
raw = text.nil? ? { "status" => "skipped" } : capture_raw(text, options)
model, formula = capture_model(input, options)
writers = formula ? capture_writers(formula, input, options) : {}

result = {
  "protocol" => UnicodemathOracle::PROTOCOL,
  "id" => request.fetch("id"),
  "outcome" => outcome_for(preprocess, raw),
  "environment" => environment,
  "boundaries" => {
    "input" => { "text" => request.fetch("input"), "options" => options },
    "preprocess" => preprocess,
    "raw" => raw,
    "model" => model,
    "writers" => writers,
  },
}
result_io.write(JSON.generate(result))
result_io.close
