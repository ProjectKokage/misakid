#!/usr/bin/env python3
"""Compare CPython 3.11.13 NFC behavior with committed Python 3.12 tables.

This diagnostic is standard-library-only. It uses the exact scalar and 21,111
cross-scalar corpora defined by export_python312_nfkc.py, then reports the
canonical-decomposition, combining-class, and composition table deltas that
explain any NFC digest difference.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import platform
import struct
import sys
import unicodedata
from typing import Any


EXPECTED_PYTHON = (3, 11, 13)
EXPECTED_UNICODE = "14.0.0"
TABLES = Path("tool/upstream_data/python-3.12.11-unicode-15.0.0/nfkc_tables.json")
S_BASE = 0xAC00
S_COUNT = 11172


def _is_surrogate(code_point: int) -> bool:
    return 0xD800 <= code_point <= 0xDFFF


def _hex_sequence(text: str) -> str:
    return " ".join(f"{ord(character):X}" for character in text)


def _record_digest(sources: list[tuple[int, ...]]) -> str:
    digest = hashlib.sha256()
    for source in sources:
        text = "".join(chr(code_point) for code_point in source)
        normalized = tuple(
            ord(character) for character in unicodedata.normalize("NFC", text)
        )
        digest.update(struct.pack(">I", len(source)))
        for code_point in source:
            digest.update(struct.pack(">I", code_point))
        digest.update(struct.pack(">I", len(normalized)))
        for code_point in normalized:
            digest.update(struct.pack(">I", code_point))
    return digest.hexdigest()


def _python311_tables() -> dict[str, dict[str, Any]]:
    decompositions: dict[str, str] = {}
    combining_classes: dict[str, int] = {}
    compositions: dict[str, str] = {}
    for code_point in range(0x110000):
        if _is_surrogate(code_point):
            continue
        character = chr(code_point)
        combining_class = unicodedata.combining(character)
        if combining_class:
            combining_classes[f"{code_point:X}"] = combining_class

        canonical = unicodedata.normalize("NFD", character)
        if canonical != character and not S_BASE <= code_point < S_BASE + S_COUNT:
            decompositions[f"{code_point:X}"] = _hex_sequence(canonical)

        raw = unicodedata.decomposition(character)
        if not raw or raw.startswith("<"):
            continue
        parts = raw.split()
        if len(parts) != 2:
            continue
        first, second = (int(part, 16) for part in parts)
        if unicodedata.normalize("NFC", chr(first) + chr(second)) == character:
            compositions[f"{first:X} {second:X}"] = f"{code_point:X}"
    return {
        "canonicalDecompositions": decompositions,
        "combiningClasses": combining_classes,
        "compositions": compositions,
    }


def _delta(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    return {
        "onlyPython311": {key: left[key] for key in sorted(left.keys() - right)},
        "onlyPython312": {key: right[key] for key in sorted(right.keys() - left)},
        "changed": {
            key: {"python311": left[key], "python312": right[key]}
            for key in sorted(left.keys() & right)
            if left[key] != right[key]
        },
    }


def main() -> int:
    if sys.version_info[:3] != EXPECTED_PYTHON:
        raise SystemExit(
            "requires CPython {}.{}.{}; got {}".format(
                *EXPECTED_PYTHON, platform.python_version()
            )
        )
    if unicodedata.unidata_version != EXPECTED_UNICODE:
        raise SystemExit(
            f"requires Unicode {EXPECTED_UNICODE}; got {unicodedata.unidata_version}"
        )

    root = json.loads(TABLES.read_text(encoding="utf-8"))
    scalar_sources = [
        (code_point,)
        for code_point in range(0x110000)
        if not _is_surrogate(code_point)
    ]
    relevant = {int(value, 16) for value in root["decompositions"]}
    relevant.update(int(value, 16) for value in root["combiningClasses"])
    for pair, composite in root["compositions"].items():
        relevant.update(int(value, 16) for value in pair.split())
        relevant.add(int(composite, 16))
    sequence_sources = [
        source
        for code_point in sorted(relevant)
        for source in (
            (0x41, code_point, 0x301),
            (0x1100, code_point, 0x1161),
            (code_point, 0x323, 0x301),
        )
    ]
    python311 = _python311_tables()
    comparisons = {
        name: _delta(python311[name], root[name])
        for name in (
            "canonicalDecompositions",
            "combiningClasses",
            "compositions",
        )
    }
    payload = {
        "pythonVersion": platform.python_version(),
        "unicodeVersion": unicodedata.unidata_version,
        "scalarNfc": {
            "records": len(scalar_sources),
            "python311Sha256": _record_digest(scalar_sources),
            "python312Sha256": root["digests"]["scalarNfcSha256"],
        },
        "sequenceNfc": {
            "records": len(sequence_sources),
            "python311Sha256": _record_digest(sequence_sources),
            "python312Sha256": root["digests"]["sequenceNfcSha256"],
        },
        "tableDeltas": comparisons,
    }
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
