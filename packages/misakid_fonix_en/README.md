# misakid_fonix_en

Optional CPU-first neural English fallback for Misakid. The package validates a
closed runtime manifest and exact ONNX bytes, creates one isolate-owned Fonix
session, and exposes it through AsyncEnglishFallbackBackend.

The caller supplies immutable manifest/model bytes and an explicit Fonix
runtime source. The adapter discovers, downloads, persists, or bundles nothing.
It accepts only the `misakid-medium-conv-bigru-ctc` en-US contract, one active
request, 64 input Unicode scalars, a fixed eight-or-fewer CTC slots per
grapheme, and a 2 MiB copied worker-message bound. Unsupported input scalars
and empty, non-finite, malformed, or out-of-inventory model output fail
explicitly.

    final fallback = await FonixEnglishG2pBackend.open(
      manifestBytes: manifestBytes,
      modelBytes: modelBytes,
      runtimeSource: runtimeSource,
    );
    try {
      final engine = AsyncEnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: const PinnedEnglishLexicon(),
        fallback: fallback,
        unknownMarker: '',
      );
      final chunks = await KokoroAsyncEnglishG2pFrontend(
        engine: engine,
      ).convert('Hello from Kokage.');
      // Supply each chunk's phonemes to Kokoro.
    } finally {
      await fallback.close();
    }

cancelActive() requests native ORT termination and waits for the authoritative
fallback call to settle. close() invalidates ownership first, cancels and
drains active work, closes the worker session, and is idempotent. The same
backend remains usable after a settled cancellation until it is closed.

Normal tests use copied fake logits and no native runtime. The provisioned test
is opt-in and requires paths supplied by the training tool:

    MISAKID_FONIX_EN_MANIFEST=/absolute/model-manifest.json \
    MISAKID_FONIX_EN_MODEL=/absolute/model.onnx \
    MISAKID_FONIX_EN_PARITY=/absolute/parity.json \
    MISAKID_FONIX_EN_RUNTIME=/absolute/libonnxruntime.dylib \
    MISAKID_FONIX_EN_RECEIPT=/absolute/unused-receipt.json \
    dart test test/provisioned_model_test.dart

The provisioned desktop test uses an explicit trusted runtime file so the
adapter package remains neutral about application packaging. A consuming app
normally supplies `bundled` on macOS/Linux/Windows, `linked` on iOS, or
`process` where sherpa owns the single process runtime, according to Fonix's
target contract. A successful complete 32-case run can atomically write the
identity-bound receipt required by the training tool's V1 promotion command.

Training, deterministic data splitting, ONNX export, Torch/ORT parity, metrics,
and artifact generation live in ../../tool/english_g2p_training. Model bytes
stay external to Git.
