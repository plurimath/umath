# frozen_string_literal: true

# The capture-aligned node classes of the UnicodeMath model. Each class is
# the value of one grammar capture (Expression: of every capture that holds
# a whole expression) and declares one attribute per capture that can occur
# directly inside it; an attribute has the same name and type wherever it
# occurs. See docs/model-contract.adoc. spec/model/model_shape_spec.rb
# checks these declarations against the grammar.
module Unicodemath
  module Model
    # Capture +accents+.
    class Accents < Node
      attribute :accent_symbols, "Unicodemath::Model::MathSymbol"
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :prime_accent_symbols, "Unicodemath::Model::PrimeAccentSymbols", collection: true
    end

    # Capture +accents_subsup+.
    class AccentsSubsup < Node
      attribute :base, "Unicodemath::Model::Expression"
      attribute :sub, "Unicodemath::Model::Expression"
      attribute :sup, "Unicodemath::Model::Expression"
    end

    # Capture +arg_arguments+.
    class ArgArguments < Node
      attribute :symbol, "Unicodemath::Model::SymbolNode"
    end

    # Capture +array+.
    class ArrayNode < Node
      attribute :tr, "Unicodemath::Model::Tr"
      attribute :trs, "Unicodemath::Model::Trs"
    end

    # Capture +atom+.
    class Atom < Node
      attribute :alphanumeric, "Unicodemath::Model::MathSymbol"
      attribute :char, "Unicodemath::Model::Char"
      attribute :diacritics, "Unicodemath::Model::Diacritics"
      attribute :number, :string
      attribute :literal, :string
    end

    # Capture +atoms+.
    class Atoms < Node
      attribute :atom, "Unicodemath::Model::Atom"
      attribute :atoms, "Unicodemath::Model::Atoms"
    end

    # Capture +backcolor+.
    class Backcolor < Node
      attribute :backcolor_value, :string
      attribute :first_value, "Unicodemath::Model::Expression"
    end

    # Capture +below_after+.
    class BelowAfter < Node
      attribute :diacritic_belows, "Unicodemath::Model::MathSymbol"
    end

    # Capture +below_before+.
    class BelowBefore < Node
      attribute :diacritic_belows, "Unicodemath::Model::MathSymbol"
    end

    # Capture +char+.
    class Char < Node
      attribute :unicode_symbols, "Unicodemath::Model::MathSymbol"
    end

    # Capture +close_paren+.
    class CloseParen < Node
      attribute :close_paren, "Unicodemath::Model::CloseParen"
      attribute :close_paren_mask, "Unicodemath::Model::CloseParenMask"
      attribute :open_paren, "Unicodemath::Model::OpenParen"
      attribute :open_paren_mask, "Unicodemath::Model::OpenParenMask"
      attribute :paren_close_prefix, "Unicodemath::Model::MathSymbol"
      attribute :paren_open_prefix, "Unicodemath::Model::MathSymbol"
      attribute :literal, "Unicodemath::Model::MathSymbol"
    end

    # Capture +close_paren_mask+.
    class CloseParenMask < Node
      attribute :number, :string
    end

    # Capture +closer+.
    class Closer < Node
      attribute :close_paren, "Unicodemath::Model::CloseParen"
      attribute :close_paren_mask, "Unicodemath::Model::CloseParenMask"
      attribute :paren_close_prefix, "Unicodemath::Model::MathSymbol"
    end

    # Capture +color+.
    class Color < Node
      attribute :color_value, :string
      attribute :first_value, "Unicodemath::Model::Expression"
    end

    # Capture +decimal_number+.
    class DecimalNumber < Node
      attribute :decimal, :string
      attribute :fractional, "Unicodemath::Model::Fractional"
      attribute :whole, "Unicodemath::Model::Whole"
    end

    # Capture +diacritics+.
    class Diacritics < Node
      attribute :char, "Unicodemath::Model::Char"
      attribute :diacritics, "Unicodemath::Model::Diacritics"
    end

    # Capture +diacritics_accents+.
    class DiacriticsAccents < Node
      attribute :below_after, "Unicodemath::Model::BelowAfter"
      attribute :below_before, "Unicodemath::Model::BelowBefore"
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :overlay_after, "Unicodemath::Model::OverlayAfter"
      attribute :overlay_before, "Unicodemath::Model::OverlayBefore"
    end

    # Capture +digit+.
    class Digit < Node
      attribute :number, :string
    end

    # Capture +exp_iteration+.
    class ExpIteration < Node
      attribute :exp_iteration, "Unicodemath::Model::ExpIteration"
      attribute :mini_sub, "Unicodemath::Model::MiniSub"
      attribute :mini_sub_sup, "Unicodemath::Model::MiniSubSup"
      attribute :mini_sup, "Unicodemath::Model::MiniSup"
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion, "Unicodemath::Model::Expression"
    end

    # Captures +base+, +denominator+, +exp+, +expr+, +expression+,
    # +factor+, +first_value+, +intent_expr+, +intermediate_exp+,
    # +monospace_value+, +naryand+, +naryand_recursion+, +numerator+,
    # +override_subsup+, +pre_script+, +pre_subscript+, +pre_supscript+,
    # +recursive_denominator+, +recursive_numerator+,
    # +scripted_first_value+, +sub+, +sub_recursion+, +sub_script+, +sup+,
    # +sup_recursion+, +sup_script+.
    class Expression < Node
      attribute :accents, "Unicodemath::Model::Accents", collection: true
      attribute :accents_subsup, "Unicodemath::Model::AccentsSubsup"
      attribute :alphanumeric, "Unicodemath::Model::MathSymbol"
      attribute :arg, :string
      attribute :arg_arguments, "Unicodemath::Model::ArgArguments"
      attribute :atom, "Unicodemath::Model::Atom"
      attribute :atoms, "Unicodemath::Model::Atoms"
      attribute :backcolor, "Unicodemath::Model::Backcolor"
      attribute :base, "Unicodemath::Model::Expression"
      attribute :binary_negated_operator, "Unicodemath::Model::MathSymbol"
      attribute :binary_number, :string
      attribute :binary_symbols, "Unicodemath::Model::MathSymbol"
      attribute :char, "Unicodemath::Model::Char"
      attribute :close_paren, "Unicodemath::Model::CloseParen"
      attribute :close_paren_mask, "Unicodemath::Model::CloseParenMask"
      attribute :color, "Unicodemath::Model::Color"
      attribute :combined_symbols, "Unicodemath::Model::MathSymbol"
      attribute :comma, "Unicodemath::Model::MathSymbol"
      attribute :decimal_number, "Unicodemath::Model::DecimalNumber"
      attribute :diacritics, "Unicodemath::Model::Diacritics"
      attribute :diacritics_accents, "Unicodemath::Model::DiacriticsAccents"
      attribute :digit, "Unicodemath::Model::Digit"
      attribute :exclamation_symbol, "Unicodemath::Model::MathSymbol"
      attribute :exp, "Unicodemath::Model::Expression"
      attribute :exp_iteration, "Unicodemath::Model::ExpIteration"
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :expression, "Unicodemath::Model::Expression"
      attribute :factor, "Unicodemath::Model::Expression"
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :fonts, "Unicodemath::Model::Fonts"
      attribute :frac, "Unicodemath::Model::Frac"
      attribute :func_expr, "Unicodemath::Model::FuncExpr"
      attribute :hbrack, "Unicodemath::Model::Hbrack"
      attribute :hbracket_class, :string
      attribute :hex_number, :string
      attribute :infty, "Unicodemath::Model::MathSymbol"
      attribute :int_exp, "Unicodemath::Model::IntExp"
      attribute :intent, :string
      attribute :intent_arguments, "Unicodemath::Model::IntentArguments"
      attribute :intent_expr, "Unicodemath::Model::Expression"
      attribute :intermediate_exp, "Unicodemath::Model::Expression"
      attribute :left_value, "Unicodemath::Model::LeftValue", collection: true
      attribute :mask, "Unicodemath::Model::Mask"
      attribute :mid_symbol, "Unicodemath::Model::MathSymbol"
      attribute :mini_base, "Unicodemath::Model::MiniBase"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :mini_sub, "Unicodemath::Model::MiniSub"
      attribute :mini_sub_sup, "Unicodemath::Model::MiniSubSup"
      attribute :mini_sup, "Unicodemath::Model::MiniSup"
      attribute :monospace, "Unicodemath::Model::Monospace"
      attribute :nary, "Unicodemath::Model::Nary"
      attribute :nary_class, "Unicodemath::Model::MathSymbol"
      attribute :naryand_recursion, "Unicodemath::Model::Expression"
      attribute :negated_operator, "Unicodemath::Model::MathSymbol"
      attribute :number, :string
      attribute :octal_number, :string
      attribute :open_paren, "Unicodemath::Model::OpenParen"
      attribute :open_paren_mask, "Unicodemath::Model::OpenParenMask"
      attribute :operand, "Unicodemath::Model::Operand"
      attribute :operator, "Unicodemath::Model::MathSymbol"
      attribute :ordinary_negated_operator, "Unicodemath::Model::MathSymbol"
      attribute :ordinary_symbols, "Unicodemath::Model::MathSymbol"
      attribute :other, "Unicodemath::Model::Other"
      attribute :over, :string
      attribute :override_subsup, "Unicodemath::Model::Expression"
      attribute :paren_close_prefix, "Unicodemath::Model::MathSymbol"
      attribute :paren_open_prefix, "Unicodemath::Model::MathSymbol"
      attribute :phantom, "Unicodemath::Model::Phantom"
      attribute :pre_override_subsup, "Unicodemath::Model::PreOverrideSubsup"
      attribute :pre_script, "Unicodemath::Model::Expression"
      attribute :pre_subscript, "Unicodemath::Model::Expression"
      attribute :pre_supscript, "Unicodemath::Model::Expression"
      attribute :rect, "Unicodemath::Model::Rect"
      attribute :recursive_denominator, "Unicodemath::Model::Expression"
      attribute :recursive_numerator, "Unicodemath::Model::Expression"
      attribute :relational_symbols, "Unicodemath::Model::MathSymbol"
      attribute :right_value, "Unicodemath::Model::RightValue", collection: true
      attribute :root, "Unicodemath::Model::Root"
      attribute :root_first_value, "Unicodemath::Model::RootFirstValue"
      attribute :root_second_value, "Unicodemath::Model::RootSecondValue"
      attribute :size_overrides, :string
      attribute :slashed_value, "Unicodemath::Model::SlashedValue", collection: true
      attribute :spaces, "Unicodemath::Model::MathSymbol"
      attribute :sub, "Unicodemath::Model::Expression"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_exp, "Unicodemath::Model::SubExp"
      attribute :sub_operators, :string
      attribute :sub_paren, "Unicodemath::Model::SubParen"
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
      attribute :sub_script, "Unicodemath::Model::Expression"
      attribute :subsup_exp, "Unicodemath::Model::SubsupExp"
      attribute :sup, "Unicodemath::Model::Expression"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_exp, "Unicodemath::Model::SupExp"
      attribute :sup_operators, :string
      attribute :sup_paren, "Unicodemath::Model::SupParen"
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
      attribute :sup_script, "Unicodemath::Model::Expression"
      attribute :symbol, "Unicodemath::Model::SymbolNode"
      attribute :table, "Unicodemath::Model::Table"
      attribute :text, :string
      attribute :unary_function, "Unicodemath::Model::UnaryFunction"
      attribute :unary_functions, :string
      attribute :unary_subsup, "Unicodemath::Model::UnarySubsup"
      attribute :under, :string
      attribute :unicode_fractions, :string
      attribute :unicode_symbols, "Unicodemath::Model::MathSymbol"
      attribute :literal, :string
    end

    # Capture +fonts+.
    class Fonts < Node
      attribute :font_class, :string
      attribute :number, :string
      attribute :symbol, "Unicodemath::Model::SymbolNode"
      attribute :text, :string
      attribute :unicoded_font_class, "Unicodemath::Model::UnicodedFontClass"
      attribute :literal, :string
    end

    # Capture +frac+.
    class Frac < Node
      attribute :atop, :string
      attribute :bevelled, :string
      attribute :choose, :string
      attribute :denominator, "Unicodemath::Model::Expression"
      attribute :ldiv, :string
      attribute :mini_denominator, "Unicodemath::Model::MiniDenominator"
      attribute :mini_numerator, "Unicodemath::Model::MiniNumerator"
      attribute :no_display_style, :string
      attribute :numerator, "Unicodemath::Model::Expression"
    end

    # Capture +fractional+.
    class Fractional < Node
      attribute :number, :string
    end

    # Capture +func_expr+.
    class FuncExpr < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :func_expr, "Unicodemath::Model::FuncExpr"
    end

    # Capture +hbrack+.
    class Hbrack < Node
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :hbracket_class, :string
      attribute :scripted_first_value, "Unicodemath::Model::Expression"
    end

    # Capture +int_exp+.
    class IntExp < Node
      attribute :closer, "Unicodemath::Model::Closer"
      attribute :opener, "Unicodemath::Model::Opener"
      attribute :operand, "Unicodemath::Model::Operand"
    end

    # Capture +intent_arguments+.
    class IntentArguments < Node
      attribute :text, :string
    end

    # Capture +left_value+.
    class LeftValue < Node
      attribute :infty, "Unicodemath::Model::MathSymbol"
      attribute :negative, "Unicodemath::Model::MathSymbol"
      attribute :number, :string
      attribute :positive, "Unicodemath::Model::MathSymbol"
      attribute :symbol, "Unicodemath::Model::SymbolNode"
    end

    # Capture +mask+.
    class Mask < Node
      attribute :binary_number, :string
      attribute :decimal_number, "Unicodemath::Model::DecimalNumber"
      attribute :digit, "Unicodemath::Model::Digit"
      attribute :hex_number, :string
      attribute :octal_number, :string
    end

    # Capture +mini_base+.
    class MiniBase < Node
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
    end

    # Capture +mini_denominator+.
    class MiniDenominator < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
    end

    # Capture +mini_expr+.
    class MiniExpr < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
    end

    # Capture +mini_intermediate_exp+.
    class MiniIntermediateExp < Node
      attribute :mini_expr, "Unicodemath::Model::MiniExpr"
      attribute :sub_close_paren, :string
      attribute :sub_open_paren, :string
      attribute :sup_close_paren, :string
      attribute :sup_open_paren, :string
    end

    # Capture +mini_numerator+.
    class MiniNumerator < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
    end

    # Capture +mini_sub+.
    class MiniSub < Node
      attribute :base, "Unicodemath::Model::Expression"
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sub, "Unicodemath::Model::Expression"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
    end

    # Capture +mini_sub_sup+.
    class MiniSubSup < Node
      attribute :base, "Unicodemath::Model::Expression"
      attribute :sub, "Unicodemath::Model::Expression"
      attribute :sup, "Unicodemath::Model::Expression"
    end

    # Capture +mini_sup+.
    class MiniSup < Node
      attribute :base, "Unicodemath::Model::Expression"
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sup, "Unicodemath::Model::Expression"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
    end

    # Capture +monospace+.
    class Monospace < Node
      attribute :monospace_value, "Unicodemath::Model::Expression"
    end

    # Capture +nary+.
    class Nary < Node
      attribute :nary_class, "Unicodemath::Model::MathSymbol"
      attribute :nary_sub_sup, "Unicodemath::Model::NarySubSup"
      attribute :naryand, "Unicodemath::Model::Expression"
    end

    # Capture +nary_sub_sup+.
    class NarySubSup < Node
      attribute :sub_exp, "Unicodemath::Model::SubExp"
      attribute :subsup_exp, "Unicodemath::Model::SubsupExp"
      attribute :sup_exp, "Unicodemath::Model::SupExp"
    end

    # Capture +open_paren+.
    class OpenParen < Node
      attribute :close_paren, "Unicodemath::Model::CloseParen"
      attribute :close_paren_mask, "Unicodemath::Model::CloseParenMask"
      attribute :open_paren, "Unicodemath::Model::OpenParen"
      attribute :open_paren_mask, "Unicodemath::Model::OpenParenMask"
      attribute :paren_close_prefix, "Unicodemath::Model::MathSymbol"
      attribute :paren_open_prefix, "Unicodemath::Model::MathSymbol"
      attribute :literal, "Unicodemath::Model::MathSymbol"
    end

    # Capture +open_paren_mask+.
    class OpenParenMask < Node
      attribute :number, :string
    end

    # Capture +opener+.
    class Opener < Node
      attribute :open_paren, "Unicodemath::Model::OpenParen"
      attribute :open_paren_mask, "Unicodemath::Model::OpenParenMask"
      attribute :paren_open_prefix, "Unicodemath::Model::MathSymbol"
    end

    # Capture +operand+.
    class Operand < Node
      attribute :accents, "Unicodemath::Model::Accents", collection: true
      attribute :binary_negated_operator, "Unicodemath::Model::MathSymbol"
      attribute :factor, "Unicodemath::Model::Expression"
      attribute :fonts, "Unicodemath::Model::Fonts"
      attribute :infty, "Unicodemath::Model::MathSymbol"
      attribute :negated_operator, "Unicodemath::Model::MathSymbol"
      attribute :operand, "Unicodemath::Model::Operand"
      attribute :operator, "Unicodemath::Model::MathSymbol"
      attribute :ordinary_negated_operator, "Unicodemath::Model::MathSymbol"
      attribute :phantom, "Unicodemath::Model::Phantom"
      attribute :rect, "Unicodemath::Model::Rect"
      attribute :symbol, "Unicodemath::Model::SymbolNode"
      attribute :text, :string
    end

    # Capture +other+.
    class Other < Node
      attribute :symbol, "Unicodemath::Model::SymbolNode"
    end

    # Capture +overlay_after+.
    class OverlayAfter < Node
      attribute :diacritic_overlays, "Unicodemath::Model::MathSymbol"
    end

    # Capture +overlay_before+.
    class OverlayBefore < Node
      attribute :diacritic_overlays, "Unicodemath::Model::MathSymbol"
    end

    # Capture +phantom+.
    class Phantom < Node
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :phantom_value, :string
    end

    # Capture +pre_override_subsup+.
    class PreOverrideSubsup < Node
      attribute :over, :string
      attribute :pre_subscript, "Unicodemath::Model::Expression"
      attribute :pre_supscript, "Unicodemath::Model::Expression"
      attribute :size_overrides, :string
      attribute :under, :string
    end

    # Capture +prime_accent_symbols+.
    class PrimeAccentSymbols < Node
      attribute :prefixed_prime, "Unicodemath::Model::MathSymbol"
      attribute :literal, "Unicodemath::Model::MathSymbol"
    end

    # Capture +rect+.
    class Rect < Node
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :rect_value, :string
    end

    # Capture +right_value+.
    class RightValue < Node
      attribute :infty, "Unicodemath::Model::MathSymbol"
      attribute :negative, "Unicodemath::Model::MathSymbol"
      attribute :number, :string
      attribute :positive, "Unicodemath::Model::MathSymbol"
      attribute :symbol, "Unicodemath::Model::SymbolNode"
    end

    # Capture +root+.
    class Root < Node
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :root_symbol, "Unicodemath::Model::MathSymbol"
      attribute :second_value, "Unicodemath::Model::SecondValue"
    end

    # Capture +root_first_value+.
    class RootFirstValue < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :func_expr, "Unicodemath::Model::FuncExpr"
    end

    # Capture +root_second_value+.
    class RootSecondValue < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :func_expr, "Unicodemath::Model::FuncExpr"
    end

    # Capture +second_value+.
    class SecondValue < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :func_expr, "Unicodemath::Model::FuncExpr"
    end

    # Capture +slashed_value+.
    class SlashedValue < Node
      attribute :number, :string
      attribute :symbol, "Unicodemath::Model::SymbolNode"
      attribute :literal, :string
    end

    # Capture +sub_exp+.
    class SubExp < Node
      attribute :base, "Unicodemath::Model::Expression"
      attribute :exp_iteration, "Unicodemath::Model::ExpIteration"
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mask, "Unicodemath::Model::Mask"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :mini_sub, "Unicodemath::Model::MiniSub"
      attribute :mini_sub_sup, "Unicodemath::Model::MiniSubSup"
      attribute :mini_sup, "Unicodemath::Model::MiniSup"
      attribute :nary_class, "Unicodemath::Model::MathSymbol"
      attribute :sub, "Unicodemath::Model::Expression"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
    end

    # Capture +sub_paren+.
    class SubParen < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
    end

    # Capture +sub_recursion_expr+.
    class SubRecursionExpr < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
    end

    # Capture +sub_recursions+.
    class SubRecursions < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sub_alpha, :string
      attribute :sub_digits, :string
      attribute :sub_operators, :string
      attribute :sub_recursion, "Unicodemath::Model::Expression"
      attribute :sub_recursion_expr, "Unicodemath::Model::SubRecursionExpr"
      attribute :sub_recursions, "Unicodemath::Model::SubRecursions"
    end

    # Capture +subsup_exp+.
    class SubsupExp < Node
      attribute :base, "Unicodemath::Model::Expression"
      attribute :mask, "Unicodemath::Model::Mask"
      attribute :nary_class, "Unicodemath::Model::MathSymbol"
      attribute :sub, "Unicodemath::Model::Expression"
      attribute :sup, "Unicodemath::Model::Expression"
    end

    # Capture +sup_exp+.
    class SupExp < Node
      attribute :base, "Unicodemath::Model::Expression"
      attribute :exp_iteration, "Unicodemath::Model::ExpIteration"
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mask, "Unicodemath::Model::Mask"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :mini_sub, "Unicodemath::Model::MiniSub"
      attribute :mini_sub_sup, "Unicodemath::Model::MiniSubSup"
      attribute :mini_sup, "Unicodemath::Model::MiniSup"
      attribute :nary_class, "Unicodemath::Model::MathSymbol"
      attribute :sup, "Unicodemath::Model::Expression"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
    end

    # Capture +sup_paren+.
    class SupParen < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
    end

    # Capture +sup_recursion_expr+.
    class SupRecursionExpr < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
    end

    # Capture +sup_recursions+.
    class SupRecursions < Node
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :mini_intermediate_exp, "Unicodemath::Model::MiniIntermediateExp"
      attribute :sup_alpha, :string
      attribute :sup_digits, :string
      attribute :sup_operators, :string
      attribute :sup_recursion, "Unicodemath::Model::Expression"
      attribute :sup_recursion_expr, "Unicodemath::Model::SupRecursionExpr"
      attribute :sup_recursions, "Unicodemath::Model::SupRecursions"
    end

    # Capture +symbol+.
    class SymbolNode < Node
      attribute :ldots, "Unicodemath::Model::MathSymbol"
      attribute :literal, "Unicodemath::Model::MathSymbol"
    end

    # Capture +table+.
    class Table < Node
      attribute :array, "Unicodemath::Model::ArrayNode"
      attribute :identity_matrix_number, :string
      attribute :matrixs, :string
    end

    # Capture +td+.
    class Td < Node
      attribute :exp, "Unicodemath::Model::Expression"
      attribute :expr, "Unicodemath::Model::Expression"
      attribute :literal, :string
    end

    # Capture +tds+.
    class Tds < Node
      attribute :td, "Unicodemath::Model::Td"
      attribute :tds, "Unicodemath::Model::Tds"
    end

    # Capture +tr+.
    class Tr < Node
      attribute :td, "Unicodemath::Model::Td"
      attribute :tds, "Unicodemath::Model::Tds"
      attribute :literal, :string
    end

    # Capture +trs+.
    class Trs < Node
      attribute :tr, "Unicodemath::Model::Tr"
      attribute :trs, "Unicodemath::Model::Trs"
    end

    # Capture +unary_function+.
    class UnaryFunction < Node
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :unary_arg_functions, :string
      attribute :unary_functions, :string
      attribute :unary_symbols, "Unicodemath::Model::MathSymbol"
    end

    # Capture +unary_sub_sup+.
    class UnarySubSup < Node
      attribute :mini_sub, "Unicodemath::Model::MiniSub"
      attribute :mini_sub_sup, "Unicodemath::Model::MiniSubSup"
      attribute :mini_sup, "Unicodemath::Model::MiniSup"
      attribute :sub_exp, "Unicodemath::Model::SubExp"
      attribute :subsup_exp, "Unicodemath::Model::SubsupExp"
      attribute :sup_exp, "Unicodemath::Model::SupExp"
    end

    # Capture +unary_subsup+.
    class UnarySubsup < Node
      attribute :first_value, "Unicodemath::Model::Expression"
      attribute :unary_functions, :string
      attribute :unary_sub_sup, "Unicodemath::Model::UnarySubSup"
    end

    # Capture +unicoded_font_class+.
    class UnicodedFontClass < Node
      attribute :mitBbb, :string
      attribute :literal, :string
    end

    # Capture +whole+.
    class Whole < Node
      attribute :number, :string
    end
  end
end
