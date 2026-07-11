# Third-party notices

This package contains an original Dart implementation of the one-layer BART
inference operations needed by the Misaki English fallback boundary.

Its behavior and compatibility boundary were studied against:

- pinned Misaki `misaki/en.py:497-519`, commit
  `fba1236595f2d2bf21d414ba6e57d25256afada3`, Apache-2.0;
- Hugging Face Transformers BART 4.51.3, Apache-2.0;
- Hugging Face safetensors 0.5.3 format/tooling, Apache-2.0;
- MisakiSwift BART source, Apache-2.0, commit
  `b7477b15fc46cf8e20b32c008126611b38ec6b79`.

The GELU helper uses the error-function approximation in Abramowitz and
Stegun, *Handbook of Mathematical Functions*, formula 7.1.26, a United States
Government work.

The runtime depends on Dart `crypto` 3.0.7 for SHA-256 resource validation:
copyright 2015 the Dart project authors, BSD-3-Clause.

No third-party model weights, configurations, tokenizer assets, or training
data are copied or distributed by this package. The committed test resources
are formula-generated synthetic data. A model's code license does not establish
the provenance or redistribution rights of separately published weights.
