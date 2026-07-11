#!/usr/bin/env python3
"""Generate licensed Vietnamese cleaner constants from pinned modules.

This generator never opens the prohibited vi_cleaner/num2vi.py input.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import sys
from typing import Any
import warnings


COMMIT = "fba1236595f2d2bf21d414ba6e57d25256afada3"
ROOT = Path("tool/upstream_data") / COMMIT / "misaki/vi_cleaner"
OUTPUT = Path("lib/src/generated/vietnamese_cleaner_tables.dart")

SOURCES = {
    "abbreviation_vi.py": "c027efb3cfc19911d1e5b50c07704a82b2372d86aadd0bd370351341e07d407e",
    "acronym_vi.py": "c8666d780b61f2423b71d18fd96b6bc8aa686c532d82a6bab7e9515612c286dd",
    "currency_vi.py": "1e27d758a8556092c69cbafa660b3792fcbcbe0da92447428d0d63c2cee7009a",
    "letter_vi.py": "281b8fc3b068b6a293b2e3635f395226be10038a0f82965f886f1277fedc9cfc",
    "measurement_vi.py": "44eea187ec67e8329f2c486411b5d5c03d0bc7c366246e2c85378c9d1f7d9710",
    "symbol_vi.py": "dfe4a22e17a432ee00f24842a6ee08063a3b3e4a1fb1c738d813f53ed6dbb405",
}

TABLES = {
    ("abbreviation_vi.py", "_abbreviations_vi"): (
        "vietnameseBaseAbbreviations",
        8,
    ),
    ("acronym_vi.py", "hardcoded_acronyms"): (
        "vietnameseSpelledAcronyms",
        47,
    ),
    ("acronym_vi.py", "acronyms_exceptions_vi"): (
        "vietnameseBaseAcronyms",
        81,
    ),
    ("acronym_vi.py", "non_uppercase_exceptions"): (
        "vietnameseNonUppercaseExceptions",
        1,
    ),
    ("currency_vi.py", "_currency_key"): ("vietnameseBaseCurrencies", 13),
    ("letter_vi.py", "_letter_key_vi"): ("vietnameseCleanerLetterNames", 24),
    ("measurement_vi.py", "_measurement_key_vi"): (
        "vietnameseMeasurements",
        38,
    ),
    ("symbol_vi.py", "vietnamese_set"): ("vietnameseCharacterSet", 194),
}


def args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def literal(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("$", r"\$")


def extract() -> dict[tuple[str, str], Any]:
    result: dict[tuple[str, str], Any] = {}
    for file_name, expected_hash in SOURCES.items():
        source_bytes = (ROOT / file_name).read_bytes()
        actual_hash = hashlib.sha256(source_bytes).hexdigest()
        if actual_hash != expected_hash:
            raise ValueError(
                f"{file_name} SHA-256 is {actual_hash}, expected {expected_hash}"
            )
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", SyntaxWarning)
            tree = ast.parse(source_bytes.decode("utf-8"), filename=file_name)
        wanted = {name for source, name in TABLES if source == file_name}
        for node in tree.body:
            if (
                isinstance(node, ast.Assign)
                and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id in wanted
            ):
                result[(file_name, node.targets[0].id)] = ast.literal_eval(node.value)
    if set(result) != set(TABLES):
        raise ValueError(f"missing tables: {sorted(set(TABLES) - set(result))}")
    for key, (_, count) in TABLES.items():
        if len(result[key]) != count:
            raise ValueError(f"{key} has {len(result[key])} entries, expected {count}")
    return result


def generate(values: dict[tuple[str, str], Any]) -> str:
    lines = [
        "// GENERATED FILE. DO NOT EDIT.",
        "// Generator: tool/generators/generate_vietnamese_cleaner_tables.py",
        f"// Upstream: hexgrad/misaki {COMMIT} (0.9.4)",
        "// Sources/licenses: Viphoneme, CodeLinkIO, and Vinorm; see",
        "// THIRD_PARTY_NOTICES.md. The unlicensed num2vi.py is excluded.",
    ]
    for file_name, digest in SOURCES.items():
        lines.append(f"// {file_name} SHA-256: {digest}")
    lines.extend(("", "// dart format off"))
    for key, (dart_name, _) in TABLES.items():
        value = values[key]
        lines.append(f"/// Pinned cleaner table `{key[1]}` from `{key[0]}`.")
        if isinstance(value, dict):
            lines.append(f"const Map<String, String> {dart_name} = <String, String>{{")
            lines.extend(
                f"  {literal(source)}: {literal(replacement)},"
                for source, replacement in value.items()
            )
            lines.append("};")
        elif isinstance(value, list):
            lines.append(f"const Set<String> {dart_name} = <String>{{")
            lines.extend(f"  {literal(item)}," for item in value)
            lines.append("};")
        elif isinstance(value, str):
            lines.append(f"const String {dart_name} = {literal(value)};")
        else:
            raise ValueError(f"unsupported table {key}")
        lines.append("")
    lines.append("// dart format on")
    return "\n".join(lines) + "\n"


def main() -> int:
    parsed = args()
    output = generate(extract())
    if parsed.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != output:
            print(f"{OUTPUT} is not reproducible", file=sys.stderr)
            return 1
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT.with_suffix(OUTPUT.suffix + ".tmp")
    temporary.write_text(output, encoding="utf-8")
    temporary.replace(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
