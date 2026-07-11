#!/usr/bin/env python3
"""Compare exact CPython 3.11.13 text behavior with the accepted candidate.

This standard-library-only diagnostic is intentionally separate from fixture
generation. It must run under the exact Vietnamese-oracle Python before the
candidate tables can be described as pinned-3.11.13 compatible.
"""

from __future__ import annotations

import json
from pathlib import Path
import platform
import sys

from export_python311_case import build_payload


EXPECTED_PYTHON = (3, 11, 13)
EXPECTED_UNICODE = "14.0.0"
SOURCE = Path(
    "tool/upstream_data/python-3.11-unicode-14.0.0/case_maps.json"
)
COMPARED_FIELDS = (
    "counts",
    "digests",
    "lowercaseMappings",
    "uppercaseMappings",
    "casedRanges",
    "caseIgnorableRanges",
    "whitespaceRanges",
)


def main() -> int:
    if sys.version_info[:3] != EXPECTED_PYTHON:
        raise SystemExit(
            "requires CPython {}.{}.{}; got {}".format(
                *EXPECTED_PYTHON, platform.python_version()
            )
        )
    import unicodedata

    if unicodedata.unidata_version != EXPECTED_UNICODE:
        raise SystemExit(
            f"requires Unicode {EXPECTED_UNICODE}; got "
            f"{unicodedata.unidata_version}"
        )

    accepted = json.loads(SOURCE.read_text(encoding="utf-8"))
    actual = build_payload()
    mismatches = [
        field for field in COMPARED_FIELDS if actual[field] != accepted[field]
    ]
    report = {
        "acceptedExportRuntime": accepted["source"]["pythonVersion"],
        "comparedFields": list(COMPARED_FIELDS),
        "mismatches": mismatches,
        "pythonVersion": platform.python_version(),
        "unicodeVersion": unicodedata.unidata_version,
    }
    print(json.dumps(report, sort_keys=True, indent=2))
    return 1 if mismatches else 0


if __name__ == "__main__":
    raise SystemExit(main())
