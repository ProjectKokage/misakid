# Native source manifest

`libmisakid_spacy_trf_en` is compiled only from these package-owned
Apache-2.0 files:

- `native/include/misakid_spacy_trf_en.h`
- `native/src/misakid_spacy_trf_en.cpp`
- `native/src/generated_tensor_manifest.h`
- `native/CMakeLists.txt`

The generated header comes deterministically from
`tool/native_tensor_manifest.json` through
`tool/generate_native_tensor_manifest.dart`. The canonical manifest records
the exact external `en_core_web_trf==3.8.0` model identity and all 149 reviewed
F32 tensor byte ranges. No model, Python, Torch, spaCy, tokenizer, tagger,
dictionary, or compiled native artifact is distributed or linked into the
shim.

The shim links only Apple Accelerate and system C/C++ libraries. It supports
macOS arm64, requires caller-provided absolute resource paths, performs no
discovery or download, and copies the exact external tensors into one aligned
immutable allocation. Contexts for the same canonical model path share that
allocation through native reference counting while any context remains live.
