## 0.1.0-dev.1

- Add the exact pure-Dart `en_core_web_sm==3.8.0` tokenizer and tagger
  resource adapter with explicit four-file checksum validation.
- Port spaCy 3.8.4 tokenization, lexical norms, StringStore hashing, inline
  alignment, and host-independent CPython 3.12 / Unicode 15 properties.
- Port the pinned Thinc 8.3.4 six-feature hash embeddings, maxout/layer-norm
  projection, four residual window layers, and 50-tag output model.
- Cover all 146 accepted small-model streams, 744 raw tokens, both dialects,
  controls, metadata, and exact no-fallback/eSpeak-call-replay results.
- Expose a narrow pure-Dart tokenizer-only boundary over the byte-identical
  small/transformer tokenizer resources, including validated tagged-token and
  inline-control assembly for sibling adapters.
