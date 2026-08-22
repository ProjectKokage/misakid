"""Deterministic training, export, parity, and held-out evaluation pipeline."""

from __future__ import annotations

import hashlib
import importlib.metadata
import json
import os
import platform
import random
import shutil
import sys
import tempfile
import time
from collections import defaultdict
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import onnx
import onnxruntime as ort
import torch
from numpy.typing import NDArray
from torch import Tensor, nn

from .constants import (
    ARCHITECTURE,
    BASELINE_PHONE_ERROR_RATE,
    BASELINE_WORD_ACCURACY,
    CLASSIFIER_CHANNELS,
    CONVOLUTION_CHANNELS,
    CONVOLUTION_DILATIONS,
    DIALECT,
    DROPOUT,
    EMBEDDING_CHANNELS,
    GRU_HIDDEN_SIZE,
    GRU_LAYERS,
    INPUT_NAME,
    MAXIMUM_BATCH_SIZE,
    MAXIMUM_GRAPHEMES,
    MAXIMUM_PHONE_ERROR_RATE,
    MAXIMUM_PROMOTED_MODEL_BYTES,
    MAXIMUM_WARM_P95_MICROSECONDS,
    MINIMUM_WORD_ACCURACY,
    MODEL_FILE,
    NORMALIZATION,
    ONNX_OPSET,
    OUTPUT_NAME,
    SEED,
    SLOT_EMBEDDING_CHANNELS,
    SLOTS_PER_GRAPHEME,
    UPSTREAM_COMMIT,
    UPSTREAM_VERSION,
)
from .data import Example, PreparedData, prepare_data
from .metrics import (
    QualityMetrics,
    encode_phonemes,
    encode_word,
    greedy_decode,
    measure_quality,
)
from .model import EnglishG2pModel

_MODEL_ID = "misakid-en-us-g2p"
_PARITY_CASES = 32
_PARITY_MAXIMUM_ABSOLUTE_ERROR = 2.0e-4
_MAXIMUM_MODEL_BYTES = 32 * 1024 * 1024
_BENCHMARK_CASES = 128
_BENCHMARK_WARMUPS = 64
_BENCHMARK_SAMPLES = 1024


@dataclass(frozen=True)
class TrainingConfiguration:
    """User-selectable values that remain part of the evidence report."""

    epochs: int = 30
    batch_size: int = 512
    learning_rate: float = 0.001
    weight_decay: float = 0.0001
    maximum_examples: int | None = None
    threads: int = 4

    def validate(self) -> None:
        if not 1 <= self.epochs <= 100:
            raise ValueError("epochs must be in 1..100.")
        if not 1 <= self.batch_size <= 4096:
            raise ValueError("batch_size must be in 1..4096.")
        if not 0.0 < self.learning_rate <= 0.1:
            raise ValueError("learning_rate must be in (0, 0.1].")
        if not 0.0 <= self.weight_decay <= 0.1:
            raise ValueError("weight_decay must be in [0, 0.1].")
        if self.maximum_examples is not None and self.maximum_examples < 1024:
            raise ValueError("maximum_examples must be at least 1024.")
        if not 1 <= self.threads <= 32:
            raise ValueError("threads must be in 1..32.")


@dataclass(frozen=True)
class TrainingResult:
    """Candidate identity and its independent held-out training-gate result."""

    output: Path
    model_sha256: str
    model_size_bytes: int
    version: str
    best_epoch: int
    test_metrics: QualityMetrics
    training_gates_passed: bool


@dataclass(frozen=True)
class _Batch:
    inputs: Tensor
    input_lengths: Tensor
    targets: Tensor
    target_lengths: Tensor


def run_training(
    *,
    repo_root: Path,
    output: Path,
    configuration: TrainingConfiguration,
    allow_below_threshold: bool,
) -> TrainingResult:
    """Run the complete pipeline and atomically publish a new output directory."""

    configuration.validate()
    repo_root = repo_root.resolve(strict=True)
    output = _validate_output(repo_root, output)
    prepared = prepare_data(repo_root, configuration.maximum_examples)
    _configure_determinism(configuration.threads)

    grapheme_ids = {symbol: index for index, symbol in enumerate(prepared.graphemes)}
    phoneme_ids = {symbol: index for index, symbol in enumerate(prepared.phonemes)}
    model = EnglishG2pModel(
        len(prepared.graphemes),
        len(prepared.phonemes),
    )
    history, best_epoch = _train(
        model,
        prepared,
        grapheme_ids,
        phoneme_ids,
        configuration,
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent)
    )
    try:
        model_path = staging / MODEL_FILE
        _export_onnx(model, model_path)
        onnx_model = onnx.load(model_path)
        onnx.checker.check_model(onnx_model)
        opset = _default_opset(onnx_model)
        if opset != ONNX_OPSET:
            raise RuntimeError(f"Exported ONNX opset {opset} is not {ONNX_OPSET}.")

        model_size = model_path.stat().st_size
        if not 1 <= model_size <= _MAXIMUM_MODEL_BYTES:
            raise RuntimeError("The exported model exceeds the runtime byte bound.")
        model_sha256 = _sha256(model_path)

        session_start = time.perf_counter_ns()
        session = _open_ort_session(model_path, configuration.threads)
        session_create_microseconds = _elapsed_microseconds(session_start)
        parity = _measure_parity(
            model,
            session,
            prepared,
            grapheme_ids,
        )
        test_predictions = _predict_ort(
            session,
            prepared.test,
            grapheme_ids,
            prepared.phonemes,
            configuration.batch_size,
        )
        test_metrics = measure_quality(prepared.test, test_predictions)
        performance = _measure_performance(
            session,
            prepared,
            grapheme_ids,
            session_create_microseconds=session_create_microseconds,
            threads=configuration.threads,
        )
        training_gates_passed = (
            test_metrics.word_accuracy >= MINIMUM_WORD_ACCURACY
            and test_metrics.phone_error_rate <= MAXIMUM_PHONE_ERROR_RATE
            and model_size <= MAXIMUM_PROMOTED_MODEL_BYTES
            and performance["warmInferenceMicroseconds"]["p95"]
            <= MAXIMUM_WARM_P95_MICROSECONDS
        )
        version = f"candidate-{model_sha256[:12]}"

        manifest = _runtime_manifest(
            prepared=prepared,
            model_sha256=model_sha256,
            model_size=model_size,
            onnx_ir_version=onnx_model.ir_version,
            version=version,
        )
        report = _training_report(
            prepared=prepared,
            configuration=configuration,
            history=history,
            best_epoch=best_epoch,
            test_metrics=test_metrics,
            training_gates_passed=training_gates_passed,
            model_sha256=model_sha256,
            model_size=model_size,
            onnx_ir_version=onnx_model.ir_version,
            version=version,
            parameter_count=sum(parameter.numel() for parameter in model.parameters()),
            performance=performance,
        )
        parity["modelSha256"] = model_sha256
        _write_json(staging / "model-manifest.json", manifest)
        _write_json(staging / "training-report.json", report)
        _write_json(staging / "parity.json", parity)

        if not training_gates_passed and not allow_below_threshold:
            raise RuntimeError(
                "Held-out quality contract failed: "
                f"word_accuracy={test_metrics.word_accuracy:.6f}, "
                f"phone_error_rate={test_metrics.phone_error_rate:.6f}, "
                f"model_size_bytes={model_size}, "
                "warm_p95_microseconds="
                f"{performance['warmInferenceMicroseconds']['p95']}."
            )
        staging.rename(output)
    except BaseException:
        shutil.rmtree(staging)
        raise

    return TrainingResult(
        output=output,
        model_sha256=model_sha256,
        model_size_bytes=model_size,
        version=version,
        best_epoch=best_epoch,
        test_metrics=test_metrics,
        training_gates_passed=training_gates_passed,
    )


def _configure_determinism(threads: int) -> None:
    os.environ["CUBLAS_WORKSPACE_CONFIG"] = ":4096:8"
    random.seed(SEED)
    np.random.seed(SEED)
    torch.manual_seed(SEED)
    torch.set_num_threads(threads)
    torch.set_num_interop_threads(1)
    torch.use_deterministic_algorithms(True)


def _train(
    model: EnglishG2pModel,
    prepared: PreparedData,
    grapheme_ids: dict[str, int],
    phoneme_ids: dict[str, int],
    configuration: TrainingConfiguration,
) -> tuple[list[dict[str, Any]], int]:
    criterion = nn.CTCLoss(blank=0, reduction="mean", zero_infinity=False)
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=configuration.learning_rate,
        weight_decay=configuration.weight_decay,
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer,
        T_max=configuration.epochs,
        eta_min=configuration.learning_rate * 0.05,
    )
    history: list[dict[str, Any]] = []
    best_state: dict[str, Tensor] | None = None
    best_epoch = 0
    best_phone_error_rate = float("inf")

    for epoch in range(1, configuration.epochs + 1):
        model.train()
        total_loss = 0.0
        batches = 0
        epoch_learning_rate = optimizer.param_groups[0]["lr"]
        for batch in _batches(
            prepared.train,
            grapheme_ids,
            phoneme_ids,
            configuration.batch_size,
            shuffle_seed=SEED + epoch,
        ):
            optimizer.zero_grad(set_to_none=True)
            logits = model(batch.inputs)
            log_probabilities = logits.log_softmax(dim=-1).transpose(0, 1)
            loss = criterion(
                log_probabilities,
                batch.targets,
                batch.input_lengths,
                batch.target_lengths,
            )
            if not bool(torch.isfinite(loss)):
                raise RuntimeError("Training produced a non-finite loss.")
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
            optimizer.step()
            total_loss += float(loss.detach())
            batches += 1

        scheduler.step()

        development_predictions = _predict_torch(
            model,
            prepared.development,
            grapheme_ids,
            prepared.phonemes,
            configuration.batch_size,
        )
        development_metrics = measure_quality(
            prepared.development,
            development_predictions,
        )
        history.append(
            {
                "epoch": epoch,
                "learningRate": epoch_learning_rate,
                "meanTrainingLoss": total_loss / batches,
                "development": development_metrics.to_json(),
            }
        )
        print(
            f"epoch={epoch} mean_training_loss={total_loss / batches:.6f} "
            f"development_word_accuracy={development_metrics.word_accuracy:.6f} "
            "development_phone_error_rate="
            f"{development_metrics.phone_error_rate:.6f}",
            file=sys.stderr,
            flush=True,
        )
        if development_metrics.phone_error_rate < best_phone_error_rate:
            best_phone_error_rate = development_metrics.phone_error_rate
            best_epoch = epoch
            best_state = {
                name: value.detach().cpu().clone()
                for name, value in model.state_dict().items()
            }

    if best_state is None:
        raise RuntimeError("Training did not produce a candidate state.")
    model.load_state_dict(best_state)
    model.eval()
    return history, best_epoch


def _batches(
    examples: tuple[Example, ...],
    grapheme_ids: dict[str, int],
    phoneme_ids: dict[str, int],
    batch_size: int,
    *,
    shuffle_seed: int | None,
) -> Iterator[_Batch]:
    for indices in _length_grouped_indices(
        examples,
        batch_size,
        shuffle_seed=shuffle_seed,
    ):
        selected = [examples[index] for index in indices]
        words = [encode_word(example.word, grapheme_ids) for example in selected]
        targets = [
            encode_phonemes(example.phonemes, phoneme_ids) for example in selected
        ]
        inputs = torch.tensor(words, dtype=torch.int64)
        yield _Batch(
            inputs=inputs,
            input_lengths=torch.tensor(
                [len(word) * SLOTS_PER_GRAPHEME for word in words],
                dtype=torch.int64,
            ),
            targets=torch.tensor(
                [value for target in targets for value in target],
                dtype=torch.int64,
            ),
            target_lengths=torch.tensor(
                [len(target) for target in targets],
                dtype=torch.int64,
            ),
        )


def _predict_torch(
    model: EnglishG2pModel,
    examples: tuple[Example, ...],
    grapheme_ids: dict[str, int],
    phonemes: tuple[str, ...],
    batch_size: int,
) -> tuple[str, ...]:
    predictions: list[str | None] = [None] * len(examples)
    model.eval()
    with torch.inference_mode():
        for inputs, indices in _inference_batches(
            examples,
            grapheme_ids,
            batch_size,
        ):
            logits = model(inputs).cpu().numpy()
            for row, index in zip(logits, indices, strict=True):
                predictions[index] = greedy_decode(row, phonemes)
    if any(prediction is None for prediction in predictions):
        raise RuntimeError("Torch prediction did not cover every example.")
    return tuple(prediction for prediction in predictions if prediction is not None)


def _predict_ort(
    session: ort.InferenceSession,
    examples: tuple[Example, ...],
    grapheme_ids: dict[str, int],
    phonemes: tuple[str, ...],
    batch_size: int,
) -> tuple[str, ...]:
    predictions: list[str | None] = [None] * len(examples)
    for inputs, indices in _inference_batches(examples, grapheme_ids, batch_size):
        logits = _run_ort_logits(session, inputs.numpy())
        for row, index in zip(logits, indices, strict=True):
            predictions[index] = greedy_decode(row, phonemes)
    if any(prediction is None for prediction in predictions):
        raise RuntimeError("ONNX Runtime prediction did not cover every example.")
    return tuple(prediction for prediction in predictions if prediction is not None)


def _inference_batches(
    examples: tuple[Example, ...],
    grapheme_ids: dict[str, int],
    batch_size: int,
) -> Iterator[tuple[Tensor, tuple[int, ...]]]:
    for indices in _length_grouped_indices(examples, batch_size, shuffle_seed=None):
        encoded = [encode_word(examples[index].word, grapheme_ids) for index in indices]
        yield torch.tensor(encoded, dtype=torch.int64), indices


def _length_grouped_indices(
    examples: tuple[Example, ...],
    batch_size: int,
    *,
    shuffle_seed: int | None,
) -> Iterator[tuple[int, ...]]:
    """Yield batches with no right padding for the bidirectional encoder."""

    buckets: dict[int, list[int]] = defaultdict(list)
    for index, example in enumerate(examples):
        buckets[len(example.word)].append(index)

    randomizer = random.Random(shuffle_seed)
    batches: list[tuple[int, ...]] = []
    for length in sorted(buckets):
        indices = buckets[length]
        if shuffle_seed is not None:
            randomizer.shuffle(indices)
        batches.extend(
            tuple(indices[offset : offset + batch_size])
            for offset in range(0, len(indices), batch_size)
        )
    if shuffle_seed is not None:
        randomizer.shuffle(batches)
    yield from batches


def _export_onnx(model: EnglishG2pModel, path: Path) -> None:
    model.eval()
    sample = torch.ones((1, 8), dtype=torch.int64)
    with torch.inference_mode():
        torch.onnx.export(
            model,
            (sample,),
            path,
            input_names=[INPUT_NAME],
            output_names=[OUTPUT_NAME],
            dynamic_axes={
                INPUT_NAME: {0: "batch", 1: "graphemes"},
                OUTPUT_NAME: {0: "batch", 1: "time"},
            },
            opset_version=ONNX_OPSET,
            do_constant_folding=True,
            dynamo=False,
        )


def _open_ort_session(path: Path, threads: int) -> ort.InferenceSession:
    options = ort.SessionOptions()
    options.intra_op_num_threads = threads
    options.inter_op_num_threads = 1
    return ort.InferenceSession(
        path,
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )


def _run_ort_logits(
    session: ort.InferenceSession,
    inputs: NDArray[np.int64],
) -> NDArray[np.float32]:
    value = session.run([OUTPUT_NAME], {INPUT_NAME: inputs})[0]
    if not isinstance(value, np.ndarray) or value.dtype != np.float32:
        raise RuntimeError("ONNX Runtime returned a non-float32 dense tensor.")
    return value


def _measure_parity(
    model: EnglishG2pModel,
    session: ort.InferenceSession,
    prepared: PreparedData,
    grapheme_ids: dict[str, int],
) -> dict[str, Any]:
    selected = sorted(
        prepared.test,
        key=lambda example: hashlib.sha256(
            b"parity\0" + example.word.encode("utf-8")
        ).digest(),
    )[:_PARITY_CASES]
    maximum_error = 0.0
    cases: list[dict[str, str]] = []
    model.eval()
    with torch.inference_mode():
        for example in selected:
            encoded = np.asarray(
                [encode_word(example.word, grapheme_ids)],
                dtype=np.int64,
            )
            torch_logits = model(torch.from_numpy(encoded)).cpu().numpy()
            ort_logits = _run_ort_logits(session, encoded)
            if torch_logits.shape != ort_logits.shape:
                raise RuntimeError("Torch and ONNX Runtime output shapes differ.")
            error = float(np.max(np.abs(torch_logits - ort_logits)))
            maximum_error = max(maximum_error, error)
            torch_result = greedy_decode(torch_logits[0], prepared.phonemes)
            ort_result = greedy_decode(ort_logits[0], prepared.phonemes)
            if torch_result != ort_result:
                raise RuntimeError("Torch and ONNX Runtime decoded outputs differ.")
            cases.append(
                {
                    "word": example.word,
                    "reference": example.phonemes,
                    "prediction": ort_result,
                }
            )
    if maximum_error > _PARITY_MAXIMUM_ABSOLUTE_ERROR:
        raise RuntimeError(
            "Torch/ONNX Runtime logit parity failed: "
            f"maximum_absolute_error={maximum_error:.9g}."
        )
    return {
        "schemaVersion": 1,
        "selection": "lowest sha256('parity\\0' + utf8(word)) from held-out test",
        "maximumCases": _PARITY_CASES,
        "maximumAbsoluteErrorLimit": _PARITY_MAXIMUM_ABSOLUTE_ERROR,
        "maximumAbsoluteError": maximum_error,
        "decodedParity": True,
        "cases": cases,
    }


def _measure_performance(
    session: ort.InferenceSession,
    prepared: PreparedData,
    grapheme_ids: dict[str, int],
    *,
    session_create_microseconds: int,
    threads: int,
) -> dict[str, Any]:
    selected = sorted(
        prepared.test,
        key=lambda example: hashlib.sha256(
            b"benchmark\0" + example.word.encode("utf-8")
        ).digest(),
    )[:_BENCHMARK_CASES]
    encoded = [
        np.asarray([encode_word(example.word, grapheme_ids)], dtype=np.int64)
        for example in selected
    ]
    if not encoded:
        raise RuntimeError("The benchmark selection is empty.")

    for index in range(_BENCHMARK_WARMUPS):
        _run_ort_logits(session, encoded[index % len(encoded)])

    durations: list[int] = []
    for index in range(_BENCHMARK_SAMPLES):
        started = time.perf_counter_ns()
        _run_ort_logits(session, encoded[index % len(encoded)])
        durations.append(_elapsed_microseconds(started))
    durations.sort()

    return {
        "selection": ("lowest sha256('benchmark\\0' + utf8(word)) from held-out test"),
        "maximumCases": _BENCHMARK_CASES,
        "selectedCases": len(encoded),
        "warmups": _BENCHMARK_WARMUPS,
        "samples": _BENCHMARK_SAMPLES,
        "batchSize": 1,
        "threads": threads,
        "provider": "CPUExecutionProvider",
        "clock": "time.perf_counter_ns",
        "sessionCreateMicroseconds": session_create_microseconds,
        "warmInferenceMicroseconds": {
            "p50": _nearest_rank(durations, 0.50),
            "p95": _nearest_rank(durations, 0.95),
            "p99": _nearest_rank(durations, 0.99),
            "maximum": durations[-1],
        },
    }


def _nearest_rank(sorted_values: list[int], quantile: float) -> int:
    if not sorted_values:
        raise ValueError("sorted_values must not be empty.")
    rank = max(1, int(np.ceil(quantile * len(sorted_values))))
    return sorted_values[rank - 1]


def _elapsed_microseconds(started_nanoseconds: int) -> int:
    return max(1, (time.perf_counter_ns() - started_nanoseconds + 999) // 1_000)


def _runtime_manifest(
    *,
    prepared: PreparedData,
    model_sha256: str,
    model_size: int,
    onnx_ir_version: int,
    version: str,
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "modelId": _MODEL_ID,
        "version": version,
        "dialect": DIALECT,
        "architecture": ARCHITECTURE,
        "normalization": NORMALIZATION,
        "model": {
            "file": MODEL_FILE,
            "sizeBytes": model_size,
            "sha256": model_sha256,
            "onnxIrVersion": onnx_ir_version,
            "opset": ONNX_OPSET,
        },
        "contract": {
            "inputName": INPUT_NAME,
            "outputName": OUTPUT_NAME,
            "maximumGraphemeCodePoints": MAXIMUM_GRAPHEMES,
            "slotsPerGrapheme": SLOTS_PER_GRAPHEME,
            "maximumBatchSize": MAXIMUM_BATCH_SIZE,
        },
        "vocabularies": {
            "graphemes": list(prepared.graphemes),
            "phonemes": list(prepared.phonemes),
        },
    }


def _training_report(
    *,
    prepared: PreparedData,
    configuration: TrainingConfiguration,
    history: list[dict[str, Any]],
    best_epoch: int,
    test_metrics: QualityMetrics,
    training_gates_passed: bool,
    model_sha256: str,
    model_size: int,
    onnx_ir_version: int,
    version: str,
    parameter_count: int,
    performance: dict[str, Any],
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "modelId": _MODEL_ID,
        "version": version,
        "candidateAccepted": False,
        "trainingGatesPassed": training_gates_passed,
        "source": {
            "upstreamRepository": "hexgrad/misaki",
            "upstreamCommit": UPSTREAM_COMMIT,
            "upstreamVersion": UPSTREAM_VERSION,
            "license": "Apache-2.0",
            "files": [
                {
                    "path": source.path,
                    "sizeBytes": source.size_bytes,
                    "sha256": source.sha256,
                    "declaredEntries": source.declared_entries,
                }
                for source in prepared.sources
            ],
        },
        "dataset": {
            "rawEntries": prepared.raw_entries,
            "mergedEntries": prepared.merged_entries,
            "eligibleEntries": prepared.eligible_entries,
            "selectedEntries": prepared.selected_entries,
            "excludedEntries": prepared.excluded_entries,
            "trainExamples": len(prepared.train),
            "developmentExamples": len(prepared.development),
            "testExamples": len(prepared.test),
            "splitPolicy": prepared.split_policy,
        },
        "architecture": {
            "name": ARCHITECTURE,
            "parameterCount": parameter_count,
            "embeddingChannels": EMBEDDING_CHANNELS,
            "convolutionChannels": CONVOLUTION_CHANNELS,
            "convolutionDilations": list(CONVOLUTION_DILATIONS),
            "gruHiddenSize": GRU_HIDDEN_SIZE,
            "gruLayers": GRU_LAYERS,
            "bidirectional": True,
            "slotEmbeddingChannels": SLOT_EMBEDDING_CHANNELS,
            "classifierChannels": CLASSIFIER_CHANNELS,
            "dropout": DROPOUT,
            "slotsPerGrapheme": SLOTS_PER_GRAPHEME,
            "maximumGraphemeCodePoints": MAXIMUM_GRAPHEMES,
        },
        "training": {
            "epochs": configuration.epochs,
            "batchSize": configuration.batch_size,
            "learningRate": configuration.learning_rate,
            "learningRateSchedule": {
                "name": "cosineAnnealing",
                "minimumLearningRate": configuration.learning_rate * 0.05,
                "periodEpochs": configuration.epochs,
            },
            "weightDecay": configuration.weight_decay,
            "maximumExamples": configuration.maximum_examples,
            "threads": configuration.threads,
            "seed": SEED,
            "deterministicAlgorithms": True,
            "device": "cpu",
            "bestEpoch": best_epoch,
            "history": history,
        },
        "promotionContract": {
            "prototypeBaseline": {
                "wordAccuracy": BASELINE_WORD_ACCURACY,
                "phoneErrorRate": BASELINE_PHONE_ERROR_RATE,
            },
            "minimumWordAccuracy": MINIMUM_WORD_ACCURACY,
            "maximumPhoneErrorRate": MAXIMUM_PHONE_ERROR_RATE,
            "maximumModelSizeBytes": MAXIMUM_PROMOTED_MODEL_BYTES,
            "maximumWarmP95Microseconds": MAXIMUM_WARM_P95_MICROSECONDS,
            "heldOutTest": test_metrics.to_json(),
            "performance": performance,
            "trainingGatesPassed": training_gates_passed,
            "fonixParityRequiredForV1": True,
            "passed": False,
        },
        "artifact": {
            "file": MODEL_FILE,
            "sizeBytes": model_size,
            "sha256": model_sha256,
            "onnxIrVersion": onnx_ir_version,
            "opset": ONNX_OPSET,
        },
        "environment": {
            "python": platform.python_version(),
            "implementation": platform.python_implementation(),
            "system": platform.system(),
            "machine": platform.machine(),
            "numpy": importlib.metadata.version("numpy"),
            "onnx": importlib.metadata.version("onnx"),
            "onnxruntime": importlib.metadata.version("onnxruntime"),
            "torch": importlib.metadata.version("torch"),
        },
    }


def _validate_output(repo_root: Path, output: Path) -> Path:
    if not output.is_absolute():
        raise ValueError("output must be an absolute path.")
    resolved = output.resolve()
    if resolved == repo_root or resolved.is_relative_to(repo_root):
        raise ValueError("output must remain outside the Misakid checkout.")
    if resolved.exists():
        raise ValueError("output must not already exist.")
    return resolved


def _default_opset(model: onnx.ModelProto) -> int:
    for import_record in model.opset_import:
        if import_record.domain in ("", "ai.onnx"):
            return import_record.version
    raise RuntimeError("The ONNX graph has no default-domain opset.")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, value: dict[str, Any]) -> None:
    payload = json.dumps(
        value,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
    path.write_text(payload + "\n", encoding="utf-8")
