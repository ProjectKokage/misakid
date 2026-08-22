"""Checksum-pinned lexicon loading and deterministic split preparation."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path
from typing import Any

from .constants import MAXIMUM_GRAPHEMES, SLOTS_PER_GRAPHEME, UPSTREAM_COMMIT


@dataclass(frozen=True)
class Example:
    """One exact spelling and Misaki phoneme sequence."""

    word: str
    phonemes: str


@dataclass(frozen=True)
class SourceIdentity:
    """One verified source lexicon."""

    path: str
    size_bytes: int
    sha256: str
    declared_entries: int


@dataclass(frozen=True)
class PreparedData:
    """Frozen examples, vocabularies, and source accounting."""

    train: tuple[Example, ...]
    development: tuple[Example, ...]
    test: tuple[Example, ...]
    graphemes: tuple[str, ...]
    phonemes: tuple[str, ...]
    sources: tuple[SourceIdentity, ...]
    raw_entries: int
    merged_entries: int
    eligible_entries: int
    selected_entries: int
    excluded_entries: int
    split_policy: str


def prepare_data(repo_root: Path, maximum_examples: int | None = None) -> PreparedData:
    """Load, verify, canonicalize, and deterministically split en-US data."""

    source_root = (
        repo_root / "tool" / "upstream_data" / UPSTREAM_COMMIT / "misaki" / "data"
    )
    manifest_path = source_root.parents[1] / "manifest.json"
    manifest = _read_json_object(manifest_path)
    if (
        manifest.get("schemaVersion") != 1
        or manifest.get("upstreamCommit") != UPSTREAM_COMMIT
        or manifest.get("license") != "Apache-2.0"
    ):
        raise ValueError("The Misakid upstream-data manifest is incompatible.")

    file_records = manifest.get("files")
    if not isinstance(file_records, list):
        raise ValueError("The Misakid upstream-data file list is malformed.")
    declared: dict[str, dict[str, Any]] = {}
    for raw_record in file_records:
        if not isinstance(raw_record, dict):
            raise ValueError("The Misakid upstream-data file record is malformed.")
        path = raw_record.get("path")
        if isinstance(path, str):
            declared[path] = raw_record

    source_names = ("us_silver.json", "us_gold.json")
    sources: list[SourceIdentity] = []
    dictionaries: dict[str, dict[str, Any]] = {}
    raw_entries = 0
    for name in source_names:
        relative_path = f"misaki/data/{name}"
        record = declared.get(relative_path)
        if record is None:
            raise ValueError(f"Missing source identity for {relative_path}.")
        path = source_root / name
        payload = path.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        entry_count = record.get("entries")
        if (
            digest != record.get("sha256")
            or not isinstance(entry_count, int)
            or entry_count <= 0
        ):
            raise ValueError(f"Source identity mismatch for {relative_path}.")
        decoded = json.loads(payload)
        if not isinstance(decoded, dict) or len(decoded) != entry_count:
            raise ValueError(f"Source entry mismatch for {relative_path}.")
        dictionaries[name] = decoded
        raw_entries += len(decoded)
        sources.append(
            SourceIdentity(
                path=relative_path,
                size_bytes=len(payload),
                sha256=digest,
                declared_entries=entry_count,
            )
        )

    canonical: dict[str, str] = {}
    for word, value in dictionaries["us_silver.json"].items():
        if isinstance(word, str) and isinstance(value, str):
            canonical[word] = value
    for word, value in dictionaries["us_gold.json"].items():
        if not isinstance(word, str):
            continue
        pronunciation: str | None
        if isinstance(value, str):
            pronunciation = value
        elif isinstance(value, dict):
            default = value.get("DEFAULT")
            pronunciation = default if isinstance(default, str) else None
        else:
            pronunciation = None
        if pronunciation is not None:
            canonical[word] = pronunciation

    merged_entries = len(canonical)
    examples: list[Example] = []
    for word, phonemes in canonical.items():
        if not _valid_example(word, phonemes):
            continue
        examples.append(Example(word=word, phonemes=phonemes))
    examples.sort(key=_selection_key)
    eligible_entries = len(examples)
    if maximum_examples is not None:
        if maximum_examples < 1024:
            raise ValueError("maximum_examples must be at least 1024.")
        examples = examples[:maximum_examples]

    train: list[Example] = []
    development: list[Example] = []
    test: list[Example] = []
    for example in examples:
        bucket = hashlib.sha256(example.word.casefold().encode("utf-8")).digest()[0]
        if bucket < 3:
            test.append(example)
        elif bucket < 6:
            development.append(example)
        else:
            train.append(example)
    for split in (train, development, test):
        split.sort(key=lambda example: example.word.encode("utf-8"))
        if not split:
            raise ValueError("A deterministic data split is empty.")

    grapheme_symbols = sorted({symbol for item in examples for symbol in item.word})
    phoneme_symbols = sorted({symbol for item in examples for symbol in item.phonemes})
    return PreparedData(
        train=tuple(train),
        development=tuple(development),
        test=tuple(test),
        graphemes=("<pad>", "<unk>", *grapheme_symbols),
        phonemes=("<blank>", *phoneme_symbols),
        sources=tuple(sources),
        raw_entries=raw_entries,
        merged_entries=merged_entries,
        eligible_entries=eligible_entries,
        selected_entries=len(examples),
        excluded_entries=merged_entries - eligible_entries,
        split_policy=(
            "sha256(casefold(word)).byte0: test=0..2, development=3..5, train=6..255"
        ),
    )


def _valid_example(word: str, phonemes: str) -> bool:
    if (
        not word
        or not phonemes
        or len(word) > MAXIMUM_GRAPHEMES
        or any(ord(symbol) < 0x20 or ord(symbol) == 0x7F for symbol in word)
    ):
        return False
    repeated_targets = sum(left == right for left, right in pairwise(phonemes))
    return len(phonemes) + repeated_targets <= len(word) * SLOTS_PER_GRAPHEME


def _selection_key(example: Example) -> tuple[bytes, bytes]:
    identity = hashlib.sha256(
        example.word.encode("utf-8") + b"\0" + example.phonemes.encode("utf-8")
    ).digest()
    return identity, example.word.encode("utf-8")


def _read_json_object(path: Path) -> dict[str, Any]:
    decoded = json.loads(path.read_bytes())
    if not isinstance(decoded, dict):
        raise ValueError(f"Expected a JSON object at {path}.")
    return decoded
