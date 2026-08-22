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
      --output /absolute/external/misakid-en-us-ctc-v1

The command trains on CPU with deterministic algorithms by default, retains the
best development-set state, exports opset-17 model.onnx, checks ONNX, compares
Torch and ONNX Runtime logits and decoded phonemes, evaluates the held-out test
split, enforces the frozen quality thresholds, and writes:

- model.onnx
- model-manifest.json
- training-report.json
- parity.json

The runtime manifest is the exact schema consumed by misakid_fonix_en. The
report records source hashes/counts, split policy, hyperparameters, Python
closure, metrics, and artifact identities. parity.json contains only bounded
word/phoneme records selected independently of model output.

A shorter plumbing check uses a deterministic subset and one epoch:

    uv run misakid-train-english-g2p \
      --output /absolute/external/smoke \
      --maximum-examples 4096 --epochs 1 --allow-below-threshold

The smoke command validates tooling only and must not be promoted into Kokage's
artifact catalog.
