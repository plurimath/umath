# Changelog

## 0.1.0

First release. Umath is the UnicodeMath parser split out of
Plurimath, as planned in plurimath/plurimath#530 and plurimath/plurimath#541.

- `Umath.parse(input, decimal: ".", engine: :ruby)` returns a
  `Umath::Model::Document`, a typed model of the formula declared with
  LutaML Model. Symbols are `Umath::Model::MathSymbol` objects with
  their spelling, Unicode value and kind, read from the symbol catalog in
  `data/umath-symbols.json`.
- Invalid input raises `Umath::ParseError` with the position in the
  caller's input (`char_offset`, `byte_offset`). Every error Umath
  raises on purpose is a `Umath::Error`.
- The grammar is Plurimath's UnicodeMath grammar, compiled with Parsanol
  into a checksummed artifact (`artifacts/umath.json`). It runs on
  Parsanol's Ruby engine by default. Parsanol's native engine is an opt-in
  with `engine: :native` (or `engine: :auto`, which uses native where it is
  available): for 18 inputs of the testsuite's UnicodeMath fixtures it gives
  a different tree from the Ruby engine and legacy Plurimath; see the
  README's section on engines.
- CI replays the unicode generation of plurimath-testsuite pinned in
  `spec/fixtures/testsuite-pin.yml`, and compares the parse tree with the
  pinned Plurimath commit for every UnicodeMath case of the testsuite.
- Requires Ruby 3.2 or later. The runtime dependencies are Parsanol and
  LutaML Model.
