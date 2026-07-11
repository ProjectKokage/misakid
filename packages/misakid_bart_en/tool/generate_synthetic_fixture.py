#!/usr/bin/env python3
"""Generate license-clean BART resources and a real Transformers oracle.

Resource bytes are derived only from this script's deterministic formulas. The
expected activations, logits, and greedy IDs are emitted by pinned
``BartForConditionalGeneration`` on CPU. No third-party model is read.

Run with the versions in ``requirements-synthetic-oracle.txt`` and pass
``--accept`` to make fixture replacement explicit.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import pathlib
import platform
import struct
import tempfile
from typing import Iterable

SCHEMA_VERSION = 3
D_MODEL = 4
HEADS = 2
FFN = 6
MAX_POSITIONS = 8
VOCAB = 8

Shape = tuple[int, ...]
Tensor = tuple[Shape, list[float]]


def f32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


def deterministic_values(name: str, count: int, scale: float) -> list[float]:
    result: list[float] = []
    for index in range(count):
        digest = hashlib.sha256(
            f"misakid-bart-synthetic-v1:{name}:{index}".encode()
        ).digest()
        unit = int.from_bytes(digest[:4], "little") / 0xFFFFFFFF
        result.append(f32((unit * 2 - 1) * scale))
    return result


def product(shape: Shape) -> int:
    result = 1
    for dimension in shape:
        result *= dimension
    return result


def make_tensor(name: str, shape: Shape) -> Tensor:
    count = product(shape)
    if name.endswith("layer_norm.weight") or name.endswith(
        "layernorm_embedding.weight"
    ):
        values = [f32(1.0 + value) for value in deterministic_values(name, count, 0.04)]
    elif name.endswith(".bias"):
        values = deterministic_values(name, count, 0.02)
    else:
        values = deterministic_values(name, count, 0.12)
    return shape, values


def tensor_shapes() -> dict[str, Shape]:
    result: dict[str, Shape] = {
        "model.shared.weight": (VOCAB, D_MODEL),
        "model.encoder.embed_positions.weight": (MAX_POSITIONS + 2, D_MODEL),
        "model.decoder.embed_positions.weight": (MAX_POSITIONS + 2, D_MODEL),
        "model.encoder.layernorm_embedding.weight": (D_MODEL,),
        "model.encoder.layernorm_embedding.bias": (D_MODEL,),
        "model.decoder.layernorm_embedding.weight": (D_MODEL,),
        "model.decoder.layernorm_embedding.bias": (D_MODEL,),
        "final_logits_bias": (1, VOCAB),
    }
    add_attention(result, "model.encoder.layers.0.self_attn")
    add_norm(result, "model.encoder.layers.0.self_attn_layer_norm")
    add_ffn(result, "model.encoder.layers.0")
    add_norm(result, "model.encoder.layers.0.final_layer_norm")
    add_attention(result, "model.decoder.layers.0.self_attn")
    add_norm(result, "model.decoder.layers.0.self_attn_layer_norm")
    add_attention(result, "model.decoder.layers.0.encoder_attn")
    add_norm(result, "model.decoder.layers.0.encoder_attn_layer_norm")
    add_ffn(result, "model.decoder.layers.0")
    add_norm(result, "model.decoder.layers.0.final_layer_norm")
    return result


def add_attention(result: dict[str, Shape], prefix: str) -> None:
    for projection in ("q_proj", "k_proj", "v_proj", "out_proj"):
        result[f"{prefix}.{projection}.weight"] = (D_MODEL, D_MODEL)
        result[f"{prefix}.{projection}.bias"] = (D_MODEL,)


def add_norm(result: dict[str, Shape], prefix: str) -> None:
    result[f"{prefix}.weight"] = (D_MODEL,)
    result[f"{prefix}.bias"] = (D_MODEL,)


def add_ffn(result: dict[str, Shape], prefix: str) -> None:
    result[f"{prefix}.fc1.weight"] = (FFN, D_MODEL)
    result[f"{prefix}.fc1.bias"] = (FFN,)
    result[f"{prefix}.fc2.weight"] = (D_MODEL, FFN)
    result[f"{prefix}.fc2.bias"] = (D_MODEL,)


def make_tensors(*, early_eos: bool = False) -> dict[str, Tensor]:
    tensors = {
        name: make_tensor(name, shape) for name, shape in tensor_shapes().items()
    }
    shape, bias = tensors["final_logits_bias"]
    bias[4] = f32(bias[4] + 2.0)
    if early_eos:
        bias[2] = f32(bias[2] + 4.0)
    tensors["final_logits_bias"] = shape, bias
    return tensors


def encode_safetensors(tensors: dict[str, Tensor]) -> bytes:
    header: dict[str, object] = {
        "__metadata__": {
            "fixture": "misakid-bart-synthetic-v1",
            "format": "pt",
        }
    }
    data = bytearray()
    for name in sorted(tensors):
        shape, values = tensors[name]
        start = len(data)
        data.extend(struct.pack(f"<{len(values)}f", *values))
        header[name] = {
            "dtype": "F32",
            "shape": list(shape),
            "data_offsets": [start, len(data)],
        }
    encoded = json.dumps(
        header, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode()
    encoded += b" " * ((8 - len(encoded) % 8) % 8)
    return struct.pack("<Q", len(encoded)) + encoded + data


def configuration() -> dict[str, object]:
    return {
        "activation_dropout": 0.0,
        "activation_function": "gelu",
        "architectures": ["BartForConditionalGeneration"],
        "attention_dropout": 0.0,
        "bos_token_id": 1,
        "classifier_dropout": 0.0,
        "d_model": D_MODEL,
        "decoder_attention_heads": HEADS,
        "decoder_ffn_dim": FFN,
        "decoder_layerdrop": 0.0,
        "decoder_layers": 1,
        "decoder_start_token_id": 1,
        "dropout": 0.1,
        "encoder_attention_heads": HEADS,
        "encoder_ffn_dim": FFN,
        "encoder_layerdrop": 0.0,
        "encoder_layers": 1,
        "eos_token_id": 2,
        "forced_eos_token_id": 2,
        "grapheme_chars": "____abc?",
        "id2label": {
            "0": "LABEL_0",
            "1": "LABEL_1",
            "2": "LABEL_2",
        },
        "init_std": 0.02,
        "is_encoder_decoder": True,
        "label2id": {
            "LABEL_0": 0,
            "LABEL_1": 1,
            "LABEL_2": 2,
        },
        "max_position_embeddings": MAX_POSITIONS,
        "model_type": "bart",
        "num_hidden_layers": 1,
        "pad_token_id": 0,
        "phoneme_chars": "____ABC?",
        "scale_embedding": False,
        "torch_dtype": "float32",
        "transformers_version": "4.51.3",
        "use_cache": True,
        "vocab_size": VOCAB,
    }


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(64 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def real_transformers_oracle(
    output: pathlib.Path,
    early_eos_weights: bytes,
) -> tuple[dict[str, object], dict[str, str]]:
    import safetensors
    import torch
    import transformers
    from transformers import BartForConditionalGeneration

    if torch.__version__ != "2.6.0" or transformers.__version__ != "4.51.3":
        raise RuntimeError(
            "synthetic oracle requires torch 2.6.0 and transformers 4.51.3"
        )
    if safetensors.__version__ != "0.5.3":
        raise RuntimeError("synthetic oracle requires safetensors 0.5.3")
    if (
        platform.python_implementation() != "CPython"
        or platform.python_version() != "3.12.11"
        or platform.system() != "Darwin"
        or platform.machine() != "arm64"
    ):
        raise RuntimeError(
            "synthetic oracle requires CPython 3.12.11 on Darwin arm64"
        )
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
    torch.use_deterministic_algorithms(True)
    model = BartForConditionalGeneration.from_pretrained(
        output,
        local_files_only=True,
    ).to("cpu")
    model.eval()
    if model.config._attn_implementation != "sdpa":
        raise RuntimeError("synthetic oracle requires Transformers SDPA attention")
    input_ids = torch.tensor([[1, 4, 5, 2]], dtype=torch.long, device="cpu")
    attention_mask = torch.ones_like(input_ids)
    with torch.no_grad():
        encoder = model.model.encoder(
            input_ids=input_ids,
            attention_mask=attention_mask,
            return_dict=True,
        ).last_hidden_state
        decoder_cases = []
        for decoder_ids in ([1], [1, 4], [1, 4, 5], [1, 4, 5, 6]):
            logits = model(
                input_ids=input_ids,
                attention_mask=attention_mask,
                decoder_input_ids=torch.tensor([decoder_ids], dtype=torch.long),
                use_cache=False,
                return_dict=True,
            ).logits[0]
            decoder_cases.append(
                {
                    "decoderIds": decoder_ids,
                    "logitsShape": list(logits.shape),
                    "logitsValues": [
                        float(value) for value in logits.flatten().tolist()
                    ],
                }
            )

    phoneme_table = "____ABC?"
    generation_cases = []
    for text, ids, maximum_length in (
        ("ab", [1, 4, 5, 2], 5),
        ("😀", [1, 3, 2], 5),
        ("", [1, 2], 4),
        ("?", [1, 7, 2], 5),
    ):
        with torch.no_grad():
            generated = model.generate(
                input_ids=torch.tensor([ids], dtype=torch.long),
                max_length=maximum_length,
            )
        generated_ids = [int(value) for value in generated[0].tolist()]
        generation_cases.append(
            {
                "input": text,
                "inputIds": ids,
                "maximumGenerationLength": maximum_length,
                "generatedIds": generated_ids,
                "phonemes": "".join(
                    phoneme_table[token] for token in generated_ids if token > 3
                ),
            }
        )

    with tempfile.TemporaryDirectory(prefix="misakid-bart-early-eos-") as directory:
        early_directory = pathlib.Path(directory)
        (early_directory / "config.json").write_bytes(
            (output / "config.json").read_bytes()
        )
        (early_directory / "model.safetensors").write_bytes(early_eos_weights)
        early_model = BartForConditionalGeneration.from_pretrained(
            early_directory,
            local_files_only=True,
        ).to("cpu")
        early_model.eval()
        if early_model.config._attn_implementation != "sdpa":
            raise RuntimeError("early-EOS oracle did not select SDPA attention")
        with torch.no_grad():
            early_generated = early_model.generate(input_ids=input_ids, max_length=5)
    early_generated_ids = [int(value) for value in early_generated[0].tolist()]
    oracle = {
        "schemaVersion": SCHEMA_VERSION,
        "generator": "tool/generate_synthetic_fixture.py",
        "oracle": "transformers.BartForConditionalGeneration",
        "model": "misakid-bart-synthetic-v1",
        "input": "ab",
        "inputIds": [1, 4, 5, 2],
        "encoderShape": list(encoder.shape[1:]),
        "encoderValues": [float(value) for value in encoder[0].flatten().tolist()],
        "decoderCases": decoder_cases,
        "generationCases": generation_cases,
        "earlyEosCase": {
            "weightsFile": "model-early-eos.safetensors",
            "input": "ab",
            "inputIds": [1, 4, 5, 2],
            "maximumGenerationLength": 5,
            "generatedIds": early_generated_ids,
            "phonemes": "".join(
                phoneme_table[token]
                for token in early_generated_ids
                if token > 3
            ),
        },
    }
    versions = {
        "attentionImplementation": model.config._attn_implementation,
        "device": "cpu",
        "machine": platform.machine(),
        "pythonImplementation": platform.python_implementation(),
        "python": platform.python_version(),
        "safetensors": safetensors.__version__,
        "system": platform.system(),
        "torch": torch.__version__,
        "transformers": transformers.__version__,
    }
    return oracle, versions


def generate(output: pathlib.Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    config_bytes = (
        json.dumps(configuration(), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode()
    weights_bytes = encode_safetensors(make_tensors())
    early_eos_weights = encode_safetensors(make_tensors(early_eos=True))
    (output / "config.json").write_bytes(config_bytes)
    (output / "model.safetensors").write_bytes(weights_bytes)
    (output / "model-early-eos.safetensors").write_bytes(early_eos_weights)

    expected, versions = real_transformers_oracle(output, early_eos_weights)
    expected["backendVersions"] = versions
    expected_bytes = (
        json.dumps(expected, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode()
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generator": "tool/generate_synthetic_fixture.py",
        "source": (
            "deterministic standard-library synthetic data; no third-party weights"
        ),
        "oracle": "transformers.BartForConditionalGeneration on CPU",
        "requirements": "tool/reference/requirements-en-espeak-py312.txt",
        "backendVersions": versions,
        "files": {
            "config.json": {
                "bytes": len(config_bytes),
                "sha256": sha256(config_bytes),
            },
            "expected.json": {
                "bytes": len(expected_bytes),
                "sha256": sha256(expected_bytes),
            },
            "model.safetensors": {
                "bytes": len(weights_bytes),
                "sha256": sha256(weights_bytes),
            },
            "model-early-eos.safetensors": {
                "bytes": len(early_eos_weights),
                "sha256": sha256(early_eos_weights),
            },
        },
    }
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    (output / "expected.json").write_bytes(expected_bytes)
    (output / "manifest.json").write_bytes(manifest_bytes)


def compare_artifacts(
    generated: pathlib.Path,
    target: pathlib.Path,
) -> list[tuple[str, str, str | None, str | None]]:
    generated_files = {
        path.name: path
        for path in generated.iterdir()
        if path.is_file()
    }
    target_files = (
        {path.name: path for path in target.iterdir() if path.is_file()}
        if target.is_dir()
        else {}
    )
    result: list[tuple[str, str, str | None, str | None]] = []
    for name in sorted(generated_files.keys() | target_files.keys()):
        generated_path = generated_files.get(name)
        target_path = target_files.get(name)
        generated_digest = (
            sha256_file(generated_path) if generated_path is not None else None
        )
        target_digest = sha256_file(target_path) if target_path is not None else None
        if generated_path is None:
            status = "unexpected"
        elif target_path is None:
            status = "added"
        elif generated_digest == target_digest:
            status = "unchanged"
        else:
            status = "changed"
        result.append((name, status, target_digest, generated_digest))
    return result


def print_summary(
    comparisons: list[tuple[str, str, str | None, str | None]],
    generated: pathlib.Path,
    target: pathlib.Path,
) -> None:
    for name, status, old_digest, new_digest in comparisons:
        old_path = target / name
        new_path = generated / name
        old_size = old_path.stat().st_size if old_path.is_file() else None
        new_size = new_path.stat().st_size if new_path.is_file() else None
        if status == "changed":
            detail = (
                f"{old_size} B {old_digest[:12]} -> "
                f"{new_size} B {new_digest[:12]}"
            )
        elif status == "unexpected":
            detail = f"existing {old_size} B {old_digest[:12]}"
        else:
            digest = new_digest if new_digest is not None else old_digest
            size = new_size if new_size is not None else old_size
            detail = f"{size} B {digest[:12]}"
        print(f"{status:10} {name:32} {detail}")


def print_text_diffs(
    comparisons: list[tuple[str, str, str | None, str | None]],
    generated: pathlib.Path,
    target: pathlib.Path,
) -> None:
    text_names = {"config.json", "expected.json", "manifest.json"}
    for name, status, _, _ in comparisons:
        if name not in text_names or status not in {"added", "changed"}:
            continue
        old_path = target / name
        new_path = generated / name
        old_lines = (
            old_path.read_text(encoding="utf-8").splitlines(keepends=True)
            if old_path.is_file()
            else []
        )
        new_lines = new_path.read_text(encoding="utf-8").splitlines(keepends=True)
        print(f"\nunified text diff: {name}")
        for line in difflib.unified_diff(
            old_lines,
            new_lines,
            fromfile=f"committed/{name}" if old_lines else "/dev/null",
            tofile=f"generated/{name}",
        ):
            print(line, end="")


def main(arguments: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="read-only byte comparison (the default)",
    )
    mode.add_argument(
        "--accept",
        action="store_true",
        help="print a diff summary and explicitly replace fixture bytes",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=(
            pathlib.Path(__file__).resolve().parents[1]
            / "test"
            / "fixtures"
            / "synthetic"
        ),
    )
    options = parser.parse_args(arguments)
    with tempfile.TemporaryDirectory(prefix="misakid-bart-generated-") as directory:
        generated = pathlib.Path(directory)
        generate(generated)
        comparisons = compare_artifacts(generated, options.output)
        print_summary(comparisons, generated, options.output)
        print_text_diffs(comparisons, generated, options.output)
        if not options.accept:
            if any(status != "unchanged" for _, status, _, _ in comparisons):
                print("check failed: committed synthetic fixtures differ")
                return 1
            print("check passed: all synthetic fixture bytes are unchanged")
            return 0
        if any(status == "unexpected" for _, status, _, _ in comparisons):
            print("accept refused: target contains unexpected files")
            return 2
        options.output.mkdir(parents=True, exist_ok=True)
        for source in generated.iterdir():
            if source.is_file():
                (options.output / source.name).write_bytes(source.read_bytes())
        after = compare_artifacts(generated, options.output)
        if any(status != "unchanged" for _, status, _, _ in after):
            raise RuntimeError("accepted fixture bytes failed post-write verification")
        counts = {
            status: sum(1 for _, candidate, _, _ in comparisons if candidate == status)
            for status in ("added", "changed", "unchanged")
        }
        print(
            "accepted synthetic fixtures: "
            f"{counts['added']} added, {counts['changed']} changed, "
            f"{counts['unchanged']} unchanged"
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
