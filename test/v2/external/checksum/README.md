# Byte checksum consumer

Authored after the kernel freeze in `../freeze.json`. This independent package
imports Boundary's public compiler module. A new handler widens each raw byte
and XORs it with its clause-owned salt. The caller folds these values into a
checksum, yielding after each byte so its saved State can move between native,
JavaScript and Wasmtime embeddings. The empty byte string preserves the seed.
No checksum operation or application code is part of the kernel build.
