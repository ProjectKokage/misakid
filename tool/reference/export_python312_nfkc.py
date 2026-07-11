#!/usr/bin/env python3
"""Export deterministic Python 3.12 / Unicode 15.0 NFKC tables.

This is an explicit development-time data export. It never runs during
package use or normal Dart tests. The output is accepted only with --accept.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import struct
import sys
import unicodedata


EXPECTED_PYTHON = (3, 12, 11)
EXPECTED_UNICODE = "15.0.0"
SCHEMA_VERSION = 1
S_BASE = 0xAC00
S_COUNT = 11172


def _scalars() -> range:
    return range(0x110000)


def _is_surrogate(code_point: int) -> bool:
    return 0xD800 <= code_point <= 0xDFFF


def _hex_sequence(text: str) -> str:
    return " ".join(f"{ord(character):X}" for character in text)


def _record_digest(records: list[tuple[tuple[int, ...], tuple[int, ...]]]) -> str:
    digest = hashlib.sha256()
    for source, normalized in records:
        digest.update(struct.pack(">I", len(source)))
        for code_point in source:
            digest.update(struct.pack(">I", code_point))
        digest.update(struct.pack(">I", len(normalized)))
        for code_point in normalized:
            digest.update(struct.pack(">I", code_point))
    return digest.hexdigest()


def _normalization_records(
    sources: list[tuple[int, ...]], form: str
) -> list[tuple[tuple[int, ...], tuple[int, ...]]]:
    records: list[tuple[tuple[int, ...], tuple[int, ...]]] = []
    for source in sources:
        text = "".join(chr(code_point) for code_point in source)
        normalized = tuple(
            ord(character)
            for character in unicodedata.normalize(form, text)
        )
        records.append((source, normalized))
    return records


def _code_point_ranges(code_points: list[int]) -> list[list[str]]:
    if not code_points:
        return []
    ranges: list[list[str]] = []
    start = previous = code_points[0]
    for code_point in code_points[1:]:
        if code_point == previous + 1:
            previous = code_point
            continue
        ranges.append([f"{start:X}", f"{previous:X}"])
        start = previous = code_point
    ranges.append([f"{start:X}", f"{previous:X}"])
    return ranges


def _valued_ranges(values: list[tuple[int, int]]) -> list[list[object]]:
    if not values:
        return []
    ranges: list[list[object]] = []
    start, start_value = values[0]
    previous, previous_value = values[0]
    for code_point, value in values[1:]:
        if code_point == previous + 1 and value == previous_value + 1:
            previous, previous_value = code_point, value
            continue
        ranges.append([f"{start:X}", f"{previous:X}", start_value])
        start, start_value = code_point, value
        previous, previous_value = code_point, value
    ranges.append([f"{start:X}", f"{previous:X}", start_value])
    return ranges


def build_payload() -> dict[str, object]:
    decompositions: dict[str, str] = {}
    canonical_decompositions: dict[str, str] = {}
    combining_classes: dict[str, int] = {}
    compositions: dict[str, str] = {}
    alphabetic: list[int] = []
    decimal_digits: list[tuple[int, int]] = []
    digits: list[tuple[int, int]] = []
    whitespace: list[int] = []

    for code_point in _scalars():
        if _is_surrogate(code_point):
            continue
        character = chr(code_point)
        if character.isalpha():
            alphabetic.append(code_point)
        if character.isdecimal():
            decimal_digits.append((code_point, unicodedata.decimal(character)))
        if character.isdigit():
            digits.append((code_point, unicodedata.digit(character)))
        if character.isspace():
            whitespace.append(code_point)
        combining_class = unicodedata.combining(character)
        if combining_class:
            combining_classes[f"{code_point:X}"] = combining_class

        normalized = unicodedata.normalize("NFKD", character)
        if normalized != character and not S_BASE <= code_point < S_BASE + S_COUNT:
            decompositions[f"{code_point:X}"] = _hex_sequence(normalized)
        canonical = unicodedata.normalize("NFD", character)
        if canonical != character and not S_BASE <= code_point < S_BASE + S_COUNT:
            canonical_decompositions[f"{code_point:X}"] = _hex_sequence(canonical)

        raw_decomposition = unicodedata.decomposition(character)
        if not raw_decomposition or raw_decomposition.startswith("<"):
            continue
        parts = raw_decomposition.split()
        if len(parts) != 2:
            continue
        first, second = (int(part, 16) for part in parts)
        if unicodedata.normalize("NFC", chr(first) + chr(second)) == character:
            compositions[f"{first:X} {second:X}"] = f"{code_point:X}"

    scalar_sources = [
        (code_point,)
        for code_point in _scalars()
        if not _is_surrogate(code_point)
    ]
    relevant = set(int(value, 16) for value in decompositions)
    relevant.update(int(value, 16) for value in combining_classes)
    for pair, composite in compositions.items():
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
    property_records = [
        (
            (code_point,),
            (
                int(character.isalpha()),
                unicodedata.decimal(character, -1) + 1,
                unicodedata.digit(character, -1) + 1,
                int(character.isspace()),
            ),
        )
        for code_point in _scalars()
        if not _is_surrogate(code_point)
        for character in (chr(code_point),)
    ]

    properties = {
        "alphabeticRanges": _code_point_ranges(alphabetic),
        "decimalDigitRanges": _valued_ranges(decimal_digits),
        "digitRanges": _valued_ranges(digits),
        "whitespaceRanges": _code_point_ranges(whitespace),
    }

    return {
        "schemaVersion": SCHEMA_VERSION,
        "source": {
            "implementation": platform.python_implementation(),
            "pythonVersion": platform.python_version(),
            "unicodeVersion": unicodedata.unidata_version,
            "normalizationForms": ["NFC", "NFKC"],
        },
        "counts": {
            "decompositions": len(decompositions),
            "canonicalDecompositions": len(canonical_decompositions),
            "combiningClasses": len(combining_classes),
            "compositions": len(compositions),
            "alphabeticRanges": len(properties["alphabeticRanges"]),
            "decimalDigitRanges": len(properties["decimalDigitRanges"]),
            "digitRanges": len(properties["digitRanges"]),
            "whitespaceRanges": len(properties["whitespaceRanges"]),
            "scalarDigestRecords": len(scalar_sources),
            "sequenceDigestRecords": len(sequence_sources),
        },
        "digests": {
            "scalarNfkcSha256": _record_digest(
                _normalization_records(scalar_sources, "NFKC")
            ),
            "sequenceNfkcSha256": _record_digest(
                _normalization_records(sequence_sources, "NFKC")
            ),
            "scalarNfcSha256": _record_digest(
                _normalization_records(scalar_sources, "NFC")
            ),
            "sequenceNfcSha256": _record_digest(
                _normalization_records(sequence_sources, "NFC")
            ),
            "propertySha256": _record_digest(property_records),
        },
        "decompositions": decompositions,
        "canonicalDecompositions": canonical_decompositions,
        "combiningClasses": combining_classes,
        "compositions": compositions,
        "properties": properties,
    }


def render(payload: dict[str, object]) -> bytes:
    return (
        json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--accept", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.accept == args.check:
        parser.error("select exactly one of --accept or --check")
    if sys.version_info[:3] != EXPECTED_PYTHON:
        parser.error(
            "requires CPython {}.{}.{}; got {}".format(
                *EXPECTED_PYTHON, platform.python_version()
            )
        )
    if unicodedata.unidata_version != EXPECTED_UNICODE:
        parser.error(
            f"requires Unicode {EXPECTED_UNICODE}; got {unicodedata.unidata_version}"
        )

    rendered = render(build_payload())
    if args.check:
        if not args.output.is_file():
            parser.error(f"missing accepted output: {args.output}")
        current = args.output.read_bytes()
        if current != rendered:
            parser.error(
                "accepted output differs (expected sha256 {}, generated {})".format(
                    hashlib.sha256(current).hexdigest(),
                    hashlib.sha256(rendered).hexdigest(),
                )
            )
        print(
            "verified {} ({})".format(
                args.output, hashlib.sha256(rendered).hexdigest()
            )
        )
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(rendered)
    print(
        "wrote {} ({})".format(
            args.output, hashlib.sha256(rendered).hexdigest()
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
