# Prefix parity after kernel freeze

This package was authored after freezing the candidate World kernel. Its new
internal operation updates Boolean parity through a shallow handler, so each
response says whether the inputs seen so far contain an odd number of true
values. An outer deep handler reverses the completed four-field answer.

The only dependency is the public Boundary compiler. The verifier checks all
16 Boolean input combinations against independent parity expectations and
source semantics, including one authored yield, full-record transfer between
embeddings, and equality of run with repeated advance.
