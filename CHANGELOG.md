# Changelog

## 0.1.0

First release. Unicodemath is the UnicodeMath parser split out of
Plurimath, as planned in plurimath/plurimath#530 and plurimath/plurimath#541.

- `Unicodemath.parse(input, decimal: ".", engine: :ruby)` returns a
  `Unicodemath::Model::Document`, a typed model of the formula declared with
  LutaML Model. Symbols are `Unicodemath::Model::MathSymbol` objects with
  their spelling, Unicode value and kind, read from the symbol catalog in
  `data/unicodemath-symbols.json`.
- Invalid input raises `Unicodemath::ParseError` with the position in the
  caller's input (`char_offset`, `byte_offset`). Every error Unicodemath
  raises on purpose is a `Unicodemath::Error`.
- The grammar is Plurimath's UnicodeMath grammar, compiled with Parsanol
  into a checksummed artifact (`artifacts/unicodemath.json`). It runs on
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
