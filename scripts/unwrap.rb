# frozen_string_literal: true

require "json"
require "parsanol"

# Test-only inverse of the grammar's capture-shape normalization
# (scripts/normalize_shapes.rb): turns the gem's raw tree back into the tree
# the legacy grammar gives, for parity with the legacy oracle. Used by
# spec/parser/oracle_parity_spec.rb, scripts/replay_corpus.rb and
# scripts/stage_cases.rb. Not part of the gem.
#
# The normalization only ADDS captures, listed in
# grammars/unicodemath.wrappers.json as {name => kind}. The unwrap replaces
# each wrapper by the value legacy produced there and re-runs Parslet's own
# flattening (Parsanol::Atoms::CanFlatten#merge_fold and
# #flatten_repetition) over the parts, bottom-up:
#
#   hash   entries are split, in order, into runs of ordinary keys (one hash
#          part each) and wrapper keys (one part each, by kind):
#            text    -> the wrapped value (nil or [] -> "", legacy unnamed)
#            empty   -> "" (String)
#            list    -> the list ([] -> "")
#            nil     -> nil
#          then folded with merge_fold, as legacy folded the sequence.
#          A hash of nil-kind wrappers only is nil.
#   array  elements are unwrapped, then flatten_repetition (named).
#
# One run stands for one legacy hash part. That is exact because the
# generator refuses a grammar where a sequence can have more than one hash
# part after a list wrapper (ShapeNormalizer#list_tails).
module UnicodemathUnwrap
  extend Parsanol::Atoms::CanFlatten

  WRAPPERS_PATH = File.expand_path("../grammars/unicodemath.wrappers.json", __dir__)

  module_function

  # The committed wrapper table: capture name => kind.
  def wrappers
    @wrappers ||= JSON.parse(File.read(WRAPPERS_PATH, encoding: "UTF-8")).fetch("wrappers").freeze
  end

  # The legacy tree for +value+, a raw tree of the normalized grammar.
  def call(value, table = wrappers)
    case value
    when Hash then unwrap_hash(value, table)
    when Array then UnicodemathUnwrap.send(:flatten_repetition, value.map { |v| call(v, table) }, true)
    else value
    end
  end

  def unwrap_hash(value, table)
    return value.to_h { |k, v| [k, call(v, table)] } if value.keys.none? { |k| table.key?(k.to_s) }

    parts = []
    run = nil
    only_nil = true
    value.each do |k, v|
      kind = table[k.to_s]
      if kind
        parts << run if run
        run = nil
        only_nil &&= kind == "nil"
        parts << part(kind, call(v, table))
      else
        only_nil = false
        (run ||= {})[k] = call(v, table)
      end
    end
    parts << run if run
    return nil if only_nil

    UnicodemathUnwrap.send(:foldl, parts) { |l, r| UnicodemathUnwrap.send(:merge_fold, l, r) }
  end

  def part(kind, value)
    case kind
    when "text" then value.nil? || value == [] ? +"" : value
    when "empty" then +""
    when "list" then value == [] ? +"" : value
    when "nil" then nil
    else raise ArgumentError, "unknown wrapper kind #{kind}"
    end
  end

  private_class_method :unwrap_hash, :part
end
