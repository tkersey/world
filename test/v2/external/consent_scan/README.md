# Prefix consent after kernel freeze

This public Boundary package was authored after freezing the candidate World
kernel. A new internal operation computes whether every input seen so far gives
consent. Its shallow handler carries that Boolean state between resumptions.
An outer deep handler reverses and negates the completed answer to report which
prefixes contain a refusal, from longest to shortest.

The verifier checks all 16 Boolean input combinations against independent
expectations and source semantics, including one authored yield, full-record
transfer between embeddings, and equality of run with repeated advance.

The performance kernel freeze adds `sum_squares.zig`, authored afterward using
the same unchanged public compiler. It yields, then recursively computes the
sum of squares from 1 through its input. The verifier checks 0 through 16 against
the closed-form sum, plus authored arithmetic overflow at 2^32, and crosses
every finite advance state among native, JavaScript and Wasmtime. The original
consent source and its complete checks remain in place. The September 9 freeze
is retained separately as historical evidence.
