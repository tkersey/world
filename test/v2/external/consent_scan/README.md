# Prefix consent after kernel freeze

This public Boundary package was authored after freezing the candidate World
kernel. A new internal operation computes whether every input seen so far gives
consent. Its shallow handler carries that Boolean state between resumptions.
An outer deep handler reverses and negates the completed answer to report which
prefixes contain a refusal, from longest to shortest.

The verifier checks all 16 Boolean input combinations against independent
expectations and source semantics, including one authored yield, full-record
transfer between embeddings, and equality of run with repeated advance.
