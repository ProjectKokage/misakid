# Misakid en-US G2P V1

This directory contains the exact promoted `v1-5ce8863c502d` runtime pair for
Misakid's app-owned neural unknown-word fallback. It is repository download
content, excluded from every Dart Pub package. It contains no inference runtime,
Kokoro voice/model, spaCy data, source corpus, or generated speech.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `model.onnx` | 4,708,739 | `5ce8863c502da27ad043e91bec1a6d8ff2b6b654d1e645d68645b1818e6230b9` |
| `model-manifest.json` | 1,812 | `bde94fe0156136166aee774a3759d4a6cc74f0788f8060d52047bee0b3cf58ff` |

Preserve both files byte for byte, including the manifest's UTF-8 serialization.
The manifest owns the closed model/input/output vocabulary contract. The ONNX
graph has 1,173,871 parameters, IR version 8 and opset 17. It accepts one en-US
word at a time, up to 64 supported Unicode scalars, with eight CTC slots per
grapheme. Unsupported input fails explicitly; this is not upstream BART parity.

Use a full published Git commit for both downloads:

```text
https://raw.githubusercontent.com/ProjectKokage/misakid/<published-commit>/models/en-us-g2p/v1-5ce8863c502d/model-manifest.json
https://raw.githubusercontent.com/ProjectKokage/misakid/<published-commit>/models/en-us-g2p/v1-5ce8863c502d/model.onnx
```

Replace `<published-commit>` with the same reviewed, reachable 40-character
commit for both URLs. Consumers stage downloads, enforce the exact sizes and
SHA-256 values above, and atomically promote complete verified bytes before
opening the adapter. Use neither a mutable branch nor an unverified local
substitute for a pinned application download. Retain the published commit so
installed applications can repair a lost cache. The library does not download
these files automatically.

[LICENSE](LICENSE) contains the Apache License 2.0. [NOTICE.md](NOTICE.md)
records the exact Apache-2.0 training sources and separate dependency boundary.
Retain both notices when redistributing these artifacts.

The 2026-08-22 qualification used only the exact pinned American Misaki
lexicons, a deterministic case-folded split, and CPU training. Its 2,187-word
held-out set measured 1,561 exact words (71.3763%) and 1,066 phone edits over
20,069 reference phones (5.3117%). Warm raw ONNX Runtime p95 was 896 µs on the
qualifying macOS arm64 host. Torch/ONNX decoded parity and the provisioned Fonix
adapter each passed 32 exported cases. These are dated model-contract results,
not a new publication verification, subjective pronunciation assessment,
physical-device result, or application/package distribution approval.

Training/promotion tooling remains in
[`tool/english_g2p_training`](../../../tool/english_g2p_training/README.md).
Training reports, parity words, candidate weights and source inputs remain
external to this publication directory. No model retraining or re-export is
required to publish the exact pair above.
