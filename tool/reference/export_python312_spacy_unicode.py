#!/usr/bin/env python3
"""Export deterministic CPython 3.12 Unicode behavior used by spaCy.

This is an explicit development-time capture of the exact Unicode predicates
and lowercase mappings needed by the pure-Dart en_core_web_sm adapter. It
never runs during package use or normal Dart tests. Accepted output is changed
only with ``--accept``.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import platform
import re
import struct
import sys
import unicodedata


EXPECTED_PYTHON = (3, 12, 11)
EXPECTED_UNICODE = "15.0.0"
SCHEMA_VERSION = 1
MAX_SCALAR = 0x10FFFF


def _is_surrogate(code_point: int) -> bool:
    return 0xD800 <= code_point <= 0xDFFF


def _internal_predicate(name: str):
    function = getattr(ctypes.pythonapi, name)
    function.argtypes = [ctypes.c_uint]
    function.restype = ctypes.c_int
    return function


IS_ALPHA = _internal_predicate("_PyUnicode_IsAlpha")
IS_DIGIT = _internal_predicate("_PyUnicode_IsDigit")
IS_UPPERCASE = _internal_predicate("_PyUnicode_IsUppercase")
IS_CASED = _internal_predicate("_PyUnicode_IsCased")
IS_CASE_IGNORABLE = _internal_predicate("_PyUnicode_IsCaseIgnorable")
WORD = re.compile(r"\w", flags=re.UNICODE).fullmatch


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


def _behavior_digest(
    properties: dict[str, list[list[str]]],
    lowercase_mappings: dict[str, str],
) -> str:
    """Hash canonical decoded records, independently of JSON formatting."""
    digest = hashlib.sha256()
    for name in sorted(properties):
        encoded_name = name.encode("ascii")
        digest.update(struct.pack(">I", len(encoded_name)))
        digest.update(encoded_name)
        for start_hex, end_hex in properties[name]:
            digest.update(struct.pack(">II", int(start_hex, 16), int(end_hex, 16)))
        digest.update(struct.pack(">I", 0xFFFFFFFF))
    for source_hex, lowered in sorted(
        lowercase_mappings.items(), key=lambda entry: int(entry[0], 16)
    ):
        lowered_bytes = lowered.encode("utf-8")
        digest.update(struct.pack(">II", int(source_hex, 16), len(lowered_bytes)))
        digest.update(lowered_bytes)
    return digest.hexdigest()


def build_payload() -> dict[str, object]:
    alphabetic: list[int] = []
    digits: list[int] = []
    uppercase: list[int] = []
    words_without_underscore: list[int] = []
    cased: list[int] = []
    case_ignorable: list[int] = []
    whitespace: list[int] = []
    lowercase_mappings: dict[str, str] = {}

    for code_point in range(MAX_SCALAR + 1):
        if _is_surrogate(code_point):
            continue
        character = chr(code_point)
        if IS_ALPHA(code_point):
            alphabetic.append(code_point)
        if IS_DIGIT(code_point):
            digits.append(code_point)
        if IS_UPPERCASE(code_point):
            uppercase.append(code_point)
        if code_point != 0x5F and WORD(character):
            words_without_underscore.append(code_point)
        if IS_CASED(code_point):
            cased.append(code_point)
        if IS_CASE_IGNORABLE(code_point):
            case_ignorable.append(code_point)
        if character.isspace():
            whitespace.append(code_point)
        lowered = character.lower()
        if lowered != character:
            lowercase_mappings[f"{code_point:X}"] = lowered

    properties = {
        "alphabeticRanges": _ranges(alphabetic),
        "caseIgnorableRanges": _ranges(case_ignorable),
        "casedRanges": _ranges(cased),
        "digitRanges": _ranges(digits),
        "uppercaseRanges": _ranges(uppercase),
        "whitespaceRanges": _ranges(whitespace),
        "wordRangesWithoutUnderscore": _ranges(words_without_underscore),
    }
    return {
        "schemaVersion": SCHEMA_VERSION,
        "source": {
            "implementation": platform.python_implementation(),
            "pythonVersion": platform.python_version(),
            "unicodeVersion": unicodedata.unidata_version,
            "predicates": [
                "_PyUnicode_IsAlpha",
                "_PyUnicode_IsDigit",
                "_PyUnicode_IsUppercase",
                "_PyUnicode_IsCased",
                "_PyUnicode_IsCaseIgnorable",
                "re.UNICODE \\w",
                "str.isspace",
                "str.lower",
            ],
        },
        "counts": {
            **{name: len(ranges) for name, ranges in properties.items()},
            "lowercaseMappings": len(lowercase_mappings),
        },
        "digests": {
            "decodedBehaviorSha256": _behavior_digest(
                properties, lowercase_mappings
            )
        },
        "properties": properties,
        "lowercaseMappings": lowercase_mappings,
    }


def render(payload: dict[str, object]) -> bytes:
    return (
        json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
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
    if platform.python_implementation() != "CPython":
        parser.error("requires CPython")
    if unicodedata.unidata_version != EXPECTED_UNICODE:
        parser.error(
            f"requires Unicode {EXPECTED_UNICODE}; got {unicodedata.unidata_version}"
        )

    rendered = render(build_payload())
    generated_sha256 = hashlib.sha256(rendered).hexdigest()
    if args.check:
        if not args.output.is_file():
            parser.error(f"missing accepted output: {args.output}")
        current = args.output.read_bytes()
        if current != rendered:
            parser.error(
                "accepted output differs (accepted sha256 {}, generated {})".format(
                    hashlib.sha256(current).hexdigest(), generated_sha256
                )
            )
        print(f"verified {args.output} ({generated_sha256})")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(rendered)
    print(f"wrote {args.output} ({generated_sha256})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
