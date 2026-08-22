# Misakid en-US neural G2P tooling

This UV project owns the deterministic data preparation, training, ONNX export,
Torch/ONNX Runtime parity, held-out evaluation, and runtime-manifest generation
for the app-owned en-US fallback.

Its only training inputs are the exact Apache-2.0 us_gold.json and
us_silver.json files already pinned by Misakid's upstream-data manifest. Gold
DEFAULT pronunciations override silver entries with the same exact spelling.
Case variants share a split, and train/dev/test assignment is a stable SHA-256
function of the case-folded word. No corpus or model is downloaded at runtime.

The output directory must be absolute and outside the Misakid checkout. Model
weights are never written into Git:

    uv sync --frozen --group dev
    uv run misakid-train-english-g2p \
      --output /absolute/external/misakid-en-us-medium-candidate

The command trains the medium convolutional/BiGRU CTC candidate on CPU with
deterministic algorithms by default, retains the best development-set state,
exports opset-17 model.onnx, checks ONNX, compares Torch and ONNX Runtime logits
and decoded phonemes, evaluates the held-out test split, benchmarks warm batch-1
ONNX Runtime inference, and writes:

- model.onnx
- model-manifest.json
- training-report.json
- parity.json

The runtime manifest is the exact schema consumed by misakid_fonix_en. The
report records source hashes/counts, split policy, hyperparameters, Python
closure, metrics, performance, and artifact identities. parity.json contains
only bounded word/phoneme records selected independently of model output.

Training always emits a `candidate-<model hash>` version. Its fixed training
gates are at least 67% exact-word accuracy, at most 7% phone error rate, at most
6 MiB, exact Torch/ONNX decoded parity, and less than 2 ms warm raw ONNX Runtime
p95 on the qualifying macOS arm64 host. Passing those gates is necessary but
does not mint V1.

Run the provisioned real-Fonix test with an unused absolute receipt path:

    MISAKID_FONIX_EN_MANIFEST=/absolute/candidate/model-manifest.json \
    MISAKID_FONIX_EN_MODEL=/absolute/candidate/model.onnx \
    MISAKID_FONIX_EN_PARITY=/absolute/candidate/parity.json \
    MISAKID_FONIX_EN_RUNTIME=/absolute/libonnxruntime.dylib \
    MISAKID_FONIX_EN_RECEIPT=/absolute/fonix-parity-receipt.json \
      dart test packages/misakid_fonix_en/test/provisioned_model_test.dart

Only that successful test can issue the identity-bound receipt used by the
promotion command:

    uv run misakid-promote-english-g2p \
      --candidate /absolute/candidate \
      --fonix-receipt /absolute/fonix-parity-receipt.json \
      --output /absolute/misakid-en-us-g2p-v1

Promotion verifies every candidate and receipt hash, copies the exact ONNX and
parity bytes, and changes only the manifest/report status to
`v1-<model hash>`. A failed gate leaves only a candidate and cannot be promoted.

A shorter plumbing check uses a deterministic subset and one epoch:

    uv run misakid-train-english-g2p \
      --output /absolute/external/smoke \
      --maximum-examples 4096 --epochs 1 --allow-below-threshold

The smoke command validates tooling only and must not be promoted into Kokage's
artifact catalog.
