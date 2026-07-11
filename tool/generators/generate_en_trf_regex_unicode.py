#!/usr/bin/env python3
"""Generate the pinned regex 2024.11.6 Unicode property tables for Dart.

Run this with the exact Python transformer reference environment. It imports
only the property-table inspector and ``regex``; it does not read model files,
load pickle data, or generate parity fixtures.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tool.reference.inspect_en_trf_model import (  # noqa: E402
    EXPECTED_REGEX_PROPERTY_COUNTS,
    _regex_property_ranges,
)


EXPECTED_REGEX_VERSION = "2024.11.6"
OUTPUT_PATH = (
    ROOT
    / "packages/misakid_spacy_trf_en/lib/src/transformer/"
    "regex_unicode_data.g.dart"
)


def _build_ranges() -> dict[str, list[list[int]]]:
    try:
        import regex
    except ImportError as error:
        raise ValueError("the pinned regex runtime is required") from error
    actual_version = importlib.metadata.version("regex")
    if actual_version != EXPECTED_REGEX_VERSION:
        raise ValueError(
            f"regex=={EXPECTED_REGEX_VERSION} is required; found {actual_version}"
        )
    ranges = {
        "letter": _regex_property_ranges(regex, "GENERALCATEGORY", "LETTER"),
        "number": _regex_property_ranges(regex, "GENERALCATEGORY", "NUMBER"),
        "whiteSpace": _regex_property_ranges(regex, "WHITESPACE", "YES"),
    }
    for name, values in ranges.items():
        expected_ranges, expected_scalars = EXPECTED_REGEX_PROPERTY_COUNTS[name]
        actual_scalars = sum(end - start + 1 for start, end in values)
        if len(values) != expected_ranges or actual_scalars != expected_scalars:
            raise ValueError(
                f"{name} has {len(values)} ranges/{actual_scalars} scalars; "
                f"expected {expected_ranges}/{expected_scalars}"
            )
    return ranges


def _behavior_digest(ranges: dict[str, list[list[int]]]) -> str:
    encoded = json.dumps(
        ranges,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("ascii")
    return hashlib.sha256(encoded).hexdigest()


def _render_ranges(name: str, ranges: list[list[int]]) -> str:
    values = [value for pair in ranges for value in pair]
    lines = [f"const List<int> {name} = <int>["]
    for value in values:
        lines.append(f"  0x{value:X},")
    lines.append("];\n")
    return "\n".join(lines)


def _render(ranges: dict[str, list[list[int]]]) -> str:
    digest = _behavior_digest(ranges)
    output = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        "// Generator: tool/generators/generate_en_trf_regex_unicode.py",
        "// Source: regex==2024.11.6 via tool/reference/inspect_en_trf_model.py",
        f"// Decoded range SHA-256: {digest}",
        "",
        "/// SHA-256 of the canonical decoded regex property ranges.",
        "const String regex20241106RangeDataSha256 =",
        f"    '{digest}';",
        "",
        "/// Tests a scalar against regex 2024.11.6 general-category Letter.",
        "bool isRegex20241106LetterScalar(int scalar) =>",
        "    _isScalarInInclusiveRanges(scalar, regex20241106LetterRanges);",
        "",
        "/// Tests a scalar against regex 2024.11.6 general-category Number.",
        "bool isRegex20241106NumberScalar(int scalar) =>",
        "    _isScalarInInclusiveRanges(scalar, regex20241106NumberRanges);",
        "",
        "/// Tests a scalar against regex 2024.11.6 White_Space.",
        "bool isRegex20241106WhitespaceScalar(int scalar) =>",
        "    _isScalarInInclusiveRanges(scalar, regex20241106WhitespaceRanges);",
        "",
        "bool _isScalarInInclusiveRanges(int scalar, List<int> ranges) {",
        "  var low = 0;",
        "  var high = ranges.length ~/ 2 - 1;",
        "  while (low <= high) {",
        "    final middle = (low + high) >> 1;",
        "    final offset = middle * 2;",
        "    if (scalar < ranges[offset]) {",
        "      high = middle - 1;",
        "    } else if (scalar > ranges[offset + 1]) {",
        "      low = middle + 1;",
        "    } else {",
        "      return true;",
        "    }",
        "  }",
        "  return false;",
        "}",
        "",
        "/// Inclusive regex 2024.11.6 Letter ranges (677 ranges).",
        _render_ranges("regex20241106LetterRanges", ranges["letter"]).rstrip(),
        "",
        "/// Inclusive regex 2024.11.6 Number ranges (144 ranges).",
        _render_ranges("regex20241106NumberRanges", ranges["number"]).rstrip(),
        "",
        "/// Inclusive regex 2024.11.6 White_Space ranges (10 ranges).",
        _render_ranges(
            "regex20241106WhitespaceRanges", ranges["whiteSpace"]
        ).rstrip(),
        "",
    ]
    return "\n".join(output)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify that committed generated output is current",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        rendered = _render(_build_ranges())
    except (ImportError, ValueError) as error:
        print(f"Unicode table generation failed: {error}", file=sys.stderr)
        return 1
    if arguments.check:
        try:
            current = OUTPUT_PATH.read_text("utf-8")
        except OSError as error:
            print(f"Could not read {OUTPUT_PATH}: {error}", file=sys.stderr)
            return 1
        if current != rendered:
            print(
                "Generated Unicode table differs; rerun without --check.",
                file=sys.stderr,
            )
            return 1
        print(f"verified {OUTPUT_PATH.relative_to(ROOT)}")
        return 0
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
