#!/usr/bin/env python3
"""Print a deterministic implementation manifest for en_core_web_trf 3.8.0.

This is development-only, read-only inspection tooling. It requires the exact
Python 3.12 transformer oracle environment and an explicit extracted model
root. It never downloads, installs, executes pickle data, writes resources, or
accepts parity fixtures.

The serialized transformer contains an uncompressed PyTorch ZIP archive after
a fixed MessagePack prefix. Because the complete resource and the archive
metadata are pinned by size and SHA-256, tensor byte ranges are inspected
without importing spaCy or Torch and without deserializing
``archive/data.pkl``. The emitted offsets are relative to
``transformer/model`` and are suitable for a future strict Dart loader.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import stat
import struct
import sys
import zipfile


BUFFER_SIZE = 1024 * 1024
SCHEMA_VERSION = 1

EXPECTED_VERSIONS = {
    "curated-tokenizers": "0.0.9",
    "curated-transformers": "0.1.1",
    "numpy": "2.2.4",
    "regex": "2024.11.6",
    "spacy": "3.8.4",
    "spacy-curated-transformers": "0.3.0",
    "srsly": "2.5.1",
    "thinc": "8.3.4",
    "torch": "2.6.0",
}

EXPECTED_RESOURCES = {
    "config.cfg": (
        5683,
        "ec6d73663a9a137377402267eaff233e24aa06ed5079af80caf01566e56e858e",
    ),
    "tagger/cfg": (
        604,
        "e19ed3035f1b1d645b7ddd338120ec88c88d9f9c37bb33fd5ccd67deb044ed25",
    ),
    "tagger/model": (
        151450,
        "a489a41d998a6c042eaa279b6b823cd24b40854faf602e696d280788ed62f84c",
    ),
    "tokenizer": (
        77066,
        "b014e8bba4958b120af2d0c1c63eabb7c00379f2bacaf10df7c5325efd2ea467",
    ),
    "transformer/cfg": (
        4,
        "f8a5a26e3056eb6fb06deeb3dbccfd88ae74900200c98c70b5966bbb7ec9d4de",
    ),
    "transformer/model": (
        497343046,
        "2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a",
    ),
    "vocab/lookups.bin": (
        70040,
        "fce9c883c56165f29573cc938c2a1c9d417ac61bd8f56b671dd5f7996de70682",
    ),
}

# Exact ranges inside transformer/model, established after the whole resource
# identity above is validated. The state ZIP occupies the rest of the file.
BYTE_BPE_RANGE = (
    416,
    1063863,
    "3a937453afcd04229fc5e32d7304c117781d4c48f1e7c87a603194e2077576f0",
)
PYTORCH_SHIM_RANGE = (
    1064426,
    496278620,
    "07450724a139b8b58913993c5a9f0f02641c40eee60d765b2dbb16c92a7bf0e0",
)
TORCH_STATE_RANGE = (
    1064446,
    496278600,
    "b8af7d937d583ed6f12b37bf7c0172bbfa23a7a268cfb2d86200e48bd90d083e",
)

TORCH_METADATA_MEMBERS = {
    "archive/.data/serialization_id": (
        40,
        "bd801ea9ad35363eac1d7c828acad810e3ec1d5198a704a3b1806d7fd1617821",
    ),
    "archive/byteorder": (
        6,
        "180ca01b95f0dfdd36fbb600e51cf6e46c8ef468de56b017847886fefaf7b6f9",
    ),
    "archive/data.pkl": (
        29989,
        "cecece67fd3f3b4f091c2f1b1c26a15bbcd62cfb2c1a42b5c7e13c7381ee1747",
    ),
    "archive/version": (
        2,
        "1121cfccd5913f0a63fec40a6ffd44ea64f9dc135c66634ba001d10bcf4302a2",
    ),
}

TRANSFORMER_GRAPH_NAMES = (
    "transformer_model",
    "with_non_ws_tokens",
    "byte_bpe_encoder>>with_strided_spans>>remove_bos_eos",
    "byte_bpe_encoder",
    "with_strided_spans",
    "remove_bos_eos",
    "pytorch",
)

BYTE_BPE_SPLIT_PATTERN = (
    r"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|"
    r"\s+(?!\S)|\s+"
)

EXPECTED_REGEX_PROPERTY_COUNTS = {
    "letter": (677, 141028),
    "number": (144, 1911),
    "whiteSpace": (10, 25),
}

TAGGER_LABELS = (
    "$",
    "''",
    ",",
    "-LRB-",
    "-RRB-",
    ".",
    ":",
    "ADD",
    "AFX",
    "CC",
    "CD",
    "DT",
    "EX",
    "FW",
    "HYPH",
    "IN",
    "JJ",
    "JJR",
    "JJS",
    "LS",
    "MD",
    "NFP",
    "NN",
    "NNP",
    "NNPS",
    "NNS",
    "PDT",
    "POS",
    "PRP",
    "PRP$",
    "RB",
    "RBR",
    "RBS",
    "RP",
    "SYM",
    "TO",
    "UH",
    "VB",
    "VBD",
    "VBG",
    "VBN",
    "VBP",
    "VBZ",
    "WDT",
    "WP",
    "WP$",
    "WRB",
    "XX",
    "``",
)


class InspectionError(ValueError):
    """A stable transformer inspection or identity failure."""


def expected_transformer_tensors() -> list[tuple[str, tuple[int, ...]]]:
    """Return the exact state-dict order and shapes without importing Torch.

    This whitelist was derived by read-only pickle disassembly. Its storage
    mapping is bound to the exact ``archive/data.pkl`` identity validated by
    :func:`inspect`; the pickle is never loaded or executed here.
    """

    tensors: list[tuple[str, tuple[int, ...]]] = [
        (
            "curated_encoder.embeddings.inner.word_embeddings.weight",
            (50265, 768),
        ),
        (
            "curated_encoder.embeddings.inner.token_type_embeddings.weight",
            (1, 768),
        ),
        (
            "curated_encoder.embeddings.inner.position_embeddings.weight",
            (514, 768),
        ),
        ("curated_encoder.embeddings.inner.layer_norm.weight", (768,)),
        ("curated_encoder.embeddings.inner.layer_norm.bias", (768,)),
    ]
    layer_tensors = (
        ("mha.input.weight", (2304, 768)),
        ("mha.input.bias", (2304,)),
        ("mha.output.weight", (768, 768)),
        ("mha.output.bias", (768,)),
        ("attn_output_layernorm.weight", (768,)),
        ("attn_output_layernorm.bias", (768,)),
        ("ffn.intermediate.weight", (3072, 768)),
        ("ffn.intermediate.bias", (3072,)),
        ("ffn.output.weight", (768, 3072)),
        ("ffn.output.bias", (768,)),
        ("ffn_output_layernorm.weight", (768,)),
        ("ffn_output_layernorm.bias", (768,)),
    )
    for layer in range(12):
        prefix = f"curated_encoder.layers.{layer}."
        tensors.extend((prefix + suffix, shape) for suffix, shape in layer_tensors)
    return tensors


def _product(shape: tuple[int, ...]) -> int:
    result = 1
    for dimension in shape:
        result *= dimension
    return result


def _regex_property_ranges(regex_module, property_name: str, value_name: str):
    properties = regex_module._regex.get_properties()
    property_id, values = properties[property_name]
    encoded = (property_id << 16) | values[value_name]
    ranges: list[list[int]] = []
    start: int | None = None
    for scalar in range(0x110000):
        matches = bool(regex_module._regex.has_property_value(encoded, scalar))
        if matches and start is None:
            start = scalar
        elif not matches and start is not None:
            ranges.append([start, scalar - 1])
            start = None
    if start is not None:
        ranges.append([start, 0x10FFFF])
    return ranges


def _sha256_stream(stream, length: int | None = None) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    while length is None or size < length:
        request = BUFFER_SIZE if length is None else min(BUFFER_SIZE, length - size)
        chunk = stream.read(request)
        if not chunk:
            break
        digest.update(chunk)
        size += len(chunk)
    return digest.hexdigest(), size


def _sha256_range(path: Path, offset: int, length: int) -> str:
    with path.open("rb") as stream:
        stream.seek(offset)
        digest, actual_length = _sha256_stream(stream, length)
    if actual_length != length:
        raise InspectionError(
            f"Could not read the complete byte range at {offset}+{length}"
        )
    return digest


def _validate_model_root(root: Path) -> dict[str, dict[str, object]]:
    if not root.is_absolute():
        raise InspectionError("--model-root must be an absolute path")
    try:
        root_metadata = root.lstat()
        resolved = root.resolve(strict=True)
    except OSError as error:
        raise InspectionError(f"Could not resolve model root: {error}") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or resolved != root:
        raise InspectionError("Model root must be a real canonical directory")

    records: dict[str, dict[str, object]] = {}
    for relative_path, (expected_size, expected_digest) in EXPECTED_RESOURCES.items():
        path = root / relative_path
        try:
            metadata = path.lstat()
        except OSError as error:
            raise InspectionError(f"Could not stat {relative_path}: {error}") from error
        if not stat.S_ISREG(metadata.st_mode) or path.resolve(strict=True) != path:
            raise InspectionError(f"{relative_path} must be a real canonical file")
        if metadata.st_size != expected_size:
            raise InspectionError(
                f"{relative_path} has {metadata.st_size} bytes; expected {expected_size}"
            )
        with path.open("rb") as stream:
            actual_digest, actual_size = _sha256_stream(stream)
        if actual_size != expected_size or actual_digest != expected_digest:
            raise InspectionError(f"{relative_path} failed its pinned identity check")
        records[relative_path] = {
            "sha256": actual_digest,
            "sizeBytes": actual_size,
        }
    return records


def _zip_data_offset(stream, info: zipfile.ZipInfo) -> int:
    stream.seek(info.header_offset)
    header = stream.read(30)
    if len(header) != 30 or header[:4] != b"PK\x03\x04":
        raise InspectionError(f"Malformed local ZIP header for {info.filename}")
    name_length, extra_length = struct.unpack_from("<HH", header, 26)
    return info.header_offset + 30 + name_length + extra_length


def inspect(model_root: Path) -> dict[str, object]:
    resources = _validate_model_root(model_root)
    versions = {
        distribution: importlib.metadata.version(distribution)
        for distribution in EXPECTED_VERSIONS
    }
    if versions != EXPECTED_VERSIONS:
        raise InspectionError(
            f"Oracle runtime versions differ: expected {EXPECTED_VERSIONS}, got {versions}"
        )

    transformer_path = model_root / "transformer/model"
    for label, (offset, length, digest) in {
        "byte-BPE payload": BYTE_BPE_RANGE,
        "PyTorch shim": PYTORCH_SHIM_RANGE,
        "Torch state": TORCH_STATE_RANGE,
    }.items():
        if _sha256_range(transformer_path, offset, length) != digest:
            raise InspectionError(f"The {label} range failed its identity check")

    try:
        from curated_tokenizers import ByteBPEProcessor
        import regex
        import srsly
    except ImportError as error:
        raise InspectionError(
            "The exact Python 3.12 transformer oracle environment is required"
        ) from error

    bpe_offset, bpe_length, bpe_digest = BYTE_BPE_RANGE
    with transformer_path.open("rb") as stream:
        stream.seek(bpe_offset)
        bpe_serialized = stream.read(bpe_length)
    bpe_payload = srsly.msgpack_loads(bpe_serialized)
    if set(bpe_payload) != {"merges", "vocab"}:
        raise InspectionError("The serialized byte-BPE payload has unexpected fields")
    merges = bpe_payload["merges"]
    vocab = bpe_payload["vocab"]
    if (
        not isinstance(merges, list)
        or len(merges) != 50000
        or not isinstance(vocab, dict)
        or len(vocab) != 50265
        or set(vocab.values()) != set(range(50265))
    ):
        raise InspectionError("The serialized byte-BPE vocabulary is malformed")

    expected_tensors = expected_transformer_tensors()

    tensor_records: list[dict[str, object]] = []
    with transformer_path.open("rb") as raw_stream, zipfile.ZipFile(
        transformer_path
    ) as archive:
        infos = {info.filename: info for info in archive.infolist()}
        expected_archive_names = {
            *TORCH_METADATA_MEMBERS,
            *(f"archive/data/{index}" for index in range(len(expected_tensors))),
        }
        if set(infos) != expected_archive_names or any(
            info.compress_type != zipfile.ZIP_STORED for info in infos.values()
        ):
            raise InspectionError("The embedded Torch ZIP member set is malformed")
        for index, (name, shape) in enumerate(expected_tensors):
            storage_path = f"archive/data/{index}"
            info = infos[storage_path]
            byte_length = _product(shape) * 4
            if info.file_size != byte_length:
                raise InspectionError(f"{storage_path} has the wrong byte length")
            data_offset = _zip_data_offset(raw_stream, info)
            stored_digest = _sha256_range(transformer_path, data_offset, byte_length)
            tensor_records.append(
                {
                    "byteLength": byte_length,
                    "byteOffset": data_offset,
                    "dtype": "F32_LE",
                    "name": name,
                    "sha256": stored_digest,
                    "shape": list(shape),
                    "storagePath": storage_path,
                }
            )

        metadata_records = {}
        for name, (expected_size, expected_digest) in TORCH_METADATA_MEMBERS.items():
            data = archive.read(name)
            actual_digest = hashlib.sha256(data).hexdigest()
            if len(data) != expected_size or actual_digest != expected_digest:
                raise InspectionError(f"{name} failed its pinned identity check")
            metadata_records[name] = {
                "sha256": actual_digest,
                "sizeBytes": len(data),
            }

    processor = ByteBPEProcessor(vocab, [tuple(pair) for pair in merges])
    if processor.vocab != vocab or processor.merges != [
        tuple(pair) for pair in merges
    ]:
        raise InspectionError("Constructed and serialized byte-BPE assets differ")

    regex_properties = {
        "letter": _regex_property_ranges(regex, "GENERALCATEGORY", "LETTER"),
        "number": _regex_property_ranges(regex, "GENERALCATEGORY", "NUMBER"),
        "whiteSpace": _regex_property_ranges(regex, "WHITESPACE", "YES"),
    }
    for name, ranges in regex_properties.items():
        expected_range_count, expected_scalar_count = EXPECTED_REGEX_PROPERTY_COUNTS[
            name
        ]
        scalar_count = sum(end - start + 1 for start, end in ranges)
        if len(ranges) != expected_range_count or scalar_count != expected_scalar_count:
            raise InspectionError(f"The regex {name} property table is malformed")

    tagger_path = model_root / "tagger/model"
    tagger_payload = srsly.msgpack_loads(tagger_path.read_bytes())
    if (
        not isinstance(tagger_payload, dict)
        or set(tagger_payload) != {"nodes", "attrs", "params", "shims"}
        or any(len(tagger_payload[field]) != 6 for field in tagger_payload)
    ):
        raise InspectionError("The serialized transformer tagger is malformed")
    tagger_nodes = tagger_payload["nodes"]
    expected_tagger_names = (
        "last_transformer_layer_listener>>with_array(softmax)",
        "last_transformer_layer_listener",
        "with_array(softmax)",
        "with_ragged_last_layer",
        "softmax",
        "reduce_mean",
    )
    if tuple(node.get("name") for node in tagger_nodes) != expected_tagger_names:
        raise InspectionError("The serialized transformer tagger graph is malformed")
    tagger_config = json.loads((model_root / "tagger/cfg").read_text("utf-8"))
    if tuple(tagger_config.get("labels", ())) != TAGGER_LABELS:
        raise InspectionError("The transformer tagger labels are malformed")
    softmax_attrs = tagger_payload["attrs"][4]
    normalize_scores = srsly.msgpack_loads(softmax_attrs["softmax_normalize"])
    if normalize_scores is not False:
        raise InspectionError("The transformer tagger unexpectedly normalizes scores")
    output_parameters = tagger_payload["params"][4]
    if set(output_parameters) != {"W", "b"}:
        raise InspectionError("The transformer tagger head fields are malformed")
    tagger_tensors = []
    for name, shape in (("W", (49, 768)), ("b", (49,))):
        tensor = output_parameters[name]
        if (
            tuple(int(value) for value in tensor.shape) != shape
            or str(tensor.dtype) != "float32"
            or not tensor.flags.c_contiguous
        ):
            raise InspectionError(f"Tagger parameter {name} is malformed")
        tagger_tensors.append(
            {
                "byteLength": int(tensor.nbytes),
                "dtype": "F32_LE",
                "name": name,
                "sha256": hashlib.sha256(
                    memoryview(tensor).cast("B")
                ).hexdigest(),
                "shape": list(shape),
            }
        )

    return {
        "artifact": {
            "distribution": "en-core-web-trf",
            "resources": resources,
            "version": "3.8.0",
        },
        "pieceEncoder": {
            "bosId": vocab["<s>"],
            "byteBpePayload": {
                "byteLength": bpe_length,
                "byteOffset": bpe_offset,
                "sha256": bpe_digest,
            },
            "eosId": vocab["</s>"],
            "mergeCount": len(merges),
            "regexPropertyRangesInclusive": regex_properties,
            "samples": [
                {
                    "ids": processor.encode_as_ids(text),
                    "pieces": processor.encode_as_pieces(text),
                    "text": text,
                }
                for text in ("Hello world!", " café", " 😀")
            ],
            "unknownId": vocab["<unk>"],
            "splitPattern": BYTE_BPE_SPLIT_PATTERN,
            "vocabularySize": len(vocab),
        },
        "runtimeVersions": versions,
        "schemaVersion": SCHEMA_VERSION,
        "tagger": {
            "graph": tagger_nodes,
            "labels": list(TAGGER_LABELS),
            "normalizeScores": normalize_scores,
            "pooling": "mean over each spaCy token's final-layer pieces",
            "tensors": tagger_tensors,
        },
        "transformer": {
            "attentionHeads": 12,
            "batchSizeSpans": 384,
            "elementCount": sum(
                _product(shape) for _, shape in expected_tensors
            ),
            "feedForwardWidth": 3072,
            "graphNames": list(TRANSFORMER_GRAPH_NAMES),
            "hiddenWidth": 768,
            "layerCount": 12,
            "layerNormEpsilon": 0.00001,
            "maximumModelPieces": 512,
            "positionEmbeddingCount": 514,
            "stateArchive": {
                "byteLength": TORCH_STATE_RANGE[1],
                "byteOffset": TORCH_STATE_RANGE[0],
                "metadataMembers": metadata_records,
                "sha256": TORCH_STATE_RANGE[2],
            },
            "stride": 104,
            "tensorByteCount": sum(record["byteLength"] for record in tensor_records),
            "tensorCount": len(tensor_records),
            "tensors": tensor_records,
            "vocabularySize": 50265,
            "window": 144,
        },
    }


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model-root",
        required=True,
        type=Path,
        help="absolute extracted en_core_web_trf-3.8.0 model directory",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        manifest = inspect(arguments.model_root)
    except (InspectionError, OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"transformer inspection failed: {error}", file=sys.stderr)
        return 1
    json.dump(
        manifest,
        sys.stdout,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
