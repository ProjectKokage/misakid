#!/usr/bin/env python3
"""Export deterministic CPython 3.11.15 / Unicode 14 text tables.

This is an explicit development-time export. It never runs during package use
or normal Dart tests. The accepted payload contains only derived Unicode case
data and is written only with ``--accept``.
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


EXPECTED_PYTHON = (3, 11, 15)
EXPECTED_UNICODE = "14.0.0"
SCHEMA_VERSION = 1
SIGMA = "\N{GREEK CAPITAL LETTER SIGMA}"
FINAL_SIGMA = "\N{GREEK SMALL LETTER FINAL SIGMA}"
SMALL_SIGMA = "\N{GREEK SMALL LETTER SIGMA}"


def _is_surrogate(code_point: int) -> bool:
    return 0xD800 <= code_point <= 0xDFFF


def _hex_sequence(text: str) -> str:
    return " ".join(f"{ord(character):X}" for character in text)


def _record_digest(
    records: list[tuple[tuple[int, ...], tuple[int, ...]]],
) -> str:
    digest = hashlib.sha256()
    for source, result in records:
        digest.update(struct.pack(">I", len(source)))
        for code_point in source:
            digest.update(struct.pack(">I", code_point))
        digest.update(struct.pack(">I", len(result)))
        for code_point in result:
            digest.update(struct.pack(">I", code_point))
    return digest.hexdigest()


def _ranges(code_points: list[int]) -> list[list[str]]:
    if not code_points:
        return []
    result: list[list[str]] = []
    start = previous = code_points[0]
    for code_point in code_points[1:]:
        if code_point == previous + 1:
            previous = code_point
            continue
        result.append([f"{start:X}", f"{previous:X}"])
        start = previous = code_point
    result.append([f"{start:X}", f"{previous:X}"])
    return result


def build_payload() -> dict[str, object]:
    lower: dict[str, str] = {}
    upper: dict[str, str] = {}
    cased: list[int] = []
    case_ignorable: list[int] = []
    whitespace: list[int] = []
    lower_records: list[tuple[tuple[int, ...], tuple[int, ...]]] = []
    upper_records: list[tuple[tuple[int, ...], tuple[int, ...]]] = []
    property_records: list[tuple[tuple[int, ...], tuple[int, ...]]] = []

    for code_point in range(0x110000):
        if _is_surrogate(code_point):
            continue
        character = chr(code_point)
        lowered = character.lower()
        uppered = character.upper()
        if lowered != character:
            lower[f"{code_point:X}"] = _hex_sequence(lowered)
        if uppered != character:
            upper[f"{code_point:X}"] = _hex_sequence(uppered)

        # These probes ask CPython's own Final_Sigma implementation for the
        # exact Unicode properties used by str.lower(), without depending on a
        # third-party Unicode-property package.
        is_cased = (character + SIGMA).lower().endswith(FINAL_SIGMA)
        is_case_ignorable = (
            not is_cased
            and ("A" + character + SIGMA).lower().endswith(FINAL_SIGMA)
        )
        following = ("A" + SIGMA + character + "A").lower()[1]
        expected = SMALL_SIGMA if is_cased or is_case_ignorable else FINAL_SIGMA
        if following != expected:
            raise AssertionError(
                f"case-property probe mismatch at U+{code_point:04X}"
            )
        if is_cased:
            cased.append(code_point)
        if is_case_ignorable:
            case_ignorable.append(code_point)
        if character.isspace():
            whitespace.append(code_point)

        lower_records.append(((code_point,), tuple(map(ord, lowered))))
        upper_records.append(((code_point,), tuple(map(ord, uppered))))
        property_records.append(
            (
                (code_point,),
                (
                    int(is_cased),
                    int(is_case_ignorable),
                    int(character.isspace()),
                ),
            )
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "source": {
            "implementation": platform.python_implementation(),
            "pythonVersion": platform.python_version(),
            "unicodeVersion": unicodedata.unidata_version,
            "operations": [
                "str.lower",
                "str.upper",
                "str.isspace",
                "Final_Sigma",
            ],
        },
        "counts": {
            "scalarRecords": len(lower_records),
            "lowercaseMappings": len(lower),
            "uppercaseMappings": len(upper),
            "casedRanges": len(_ranges(cased)),
            "caseIgnorableRanges": len(_ranges(case_ignorable)),
            "whitespaceRanges": len(_ranges(whitespace)),
        },
        "digests": {
            "lowercaseSha256": _record_digest(lower_records),
            "uppercaseSha256": _record_digest(upper_records),
            "propertiesSha256": _record_digest(property_records),
        },
        "lowercaseMappings": lower,
        "uppercaseMappings": upper,
        "casedRanges": _ranges(cased),
        "caseIgnorableRanges": _ranges(case_ignorable),
        "whitespaceRanges": _ranges(whitespace),
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
            "requires CPython {}; got {}".format(
                ".".join(map(str, EXPECTED_PYTHON)), platform.python_version()
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
        if args.output.read_bytes() != rendered:
            parser.error("accepted output differs from this runtime")
        print(f"verified {args.output}")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(rendered)
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
