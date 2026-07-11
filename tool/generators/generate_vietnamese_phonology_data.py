#!/usr/bin/env python3
"""Generate immutable Dart Vietnamese phonology tables from pinned vi.py.

The input is licensed Viphoneme/Misaki material recorded in
THIRD_PARTY_NOTICES.md. This generator deliberately does not read the
unlicensed vi_cleaner/num2vi.py file.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


UPSTREAM_COMMIT = "fba1236595f2d2bf21d414ba6e57d25256afada3"
SOURCE = Path("tool/upstream_data") / UPSTREAM_COMMIT / "misaki/vi.py"
SOURCE_SHA256 = "be333eac8211063eafd3304b13eafa2f2250af0a950b47f231f7758fb08d951e"
OUTPUT = Path("lib/src/generated/vietnamese_phonology_data.dart")

TABLES = {
    "Cus_onsets": ("vietnameseOnsets", 31),
    "Cus_nuclei": ("vietnameseNuclei", 158),
    "Cus_offglides": ("vietnameseOffglides", 125),
    "Cus_onglides": ("vietnameseOnglides", 105),
    "Cus_onoffglides": ("vietnameseOnoffglides", 59),
    "Cus_codas": ("vietnameseCodas", 9),
    "Cus_tones_p": ("vietnameseToneByCharacter", 60),
    "Cus_gi": ("vietnameseGi", 5),
    "Cus_qu": ("vietnameseQu", 6),
    "EN": ("vietnameseEnglishLetterNames", 27),
    "VI": ("vietnameseLetterNames", 33),
    "vi_syms": ("vietnameseSymbols", 139),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def extract_tables(source: str) -> dict[str, Any]:
    tree = ast.parse(source, filename=str(SOURCE))
    result: dict[str, Any] = {}
    for node in tree.body:
        if (
            isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id in TABLES
        ):
            result[node.targets[0].id] = ast.literal_eval(node.value)
            continue
        if (
            isinstance(node, ast.Expr)
            and isinstance(node.value, ast.Call)
            and isinstance(node.value.func, ast.Attribute)
            and node.value.func.attr == "update"
            and isinstance(node.value.func.value, ast.Name)
            and node.value.func.value.id in TABLES
            and len(node.value.args) == 1
            and not node.value.keywords
        ):
            name = node.value.func.value.id
            update = ast.literal_eval(node.value.args[0])
            if not isinstance(result.get(name), dict) or not isinstance(update, dict):
                raise ValueError(f"{name}.update must combine dictionaries")
            result[name].update(update)

    if set(result) != set(TABLES):
        raise ValueError(f"missing tables: {sorted(set(TABLES) - set(result))}")
    for source_name, (_, expected_count) in TABLES.items():
        if len(result[source_name]) != expected_count:
            raise ValueError(
                f"{source_name} has {len(result[source_name])} entries, "
                f"expected {expected_count}"
            )
    return result


def literal(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("$", r"\$")


def generate(tables: dict[str, Any]) -> str:
    lines = [
        "// GENERATED FILE. DO NOT EDIT.",
        "// Generator: tool/generators/generate_vietnamese_phonology_data.py",
        f"// Upstream: hexgrad/misaki {UPSTREAM_COMMIT} (0.9.4)",
        "// Source: Viphoneme 616a505fdbe83b23bd30a358819e6dded0e1de4a (MIT)",
        f"// vi.py SHA-256: {SOURCE_SHA256}",
        "",
        "// dart format off",
    ]
    for source_name, (dart_name, _) in TABLES.items():
        value = tables[source_name]
        lines.append(f"/// Pinned Vietnamese phonology table `{source_name}`.")
        if isinstance(value, dict):
            value_type = "int" if source_name == "Cus_tones_p" else "String"
            lines.append(
                f"const Map<String, {value_type}> {dart_name} = "
                f"<String, {value_type}>{{"
            )
            for key in sorted(value):
                encoded_value = (
                    str(value[key]) if value_type == "int" else literal(value[key])
                )
                lines.append(f"  {literal(key)}: {encoded_value},")
            lines.append("};")
        elif isinstance(value, list) and all(isinstance(item, str) for item in value):
            lines.append(f"const List<String> {dart_name} = <String>[")
            lines.extend(f"  {literal(item)}," for item in value)
            lines.append("];")
        else:
            raise ValueError(f"unsupported table type for {source_name}")
        lines.append("")
    lines.append("// dart format on")
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    source_bytes = SOURCE.read_bytes()
    actual_hash = hashlib.sha256(source_bytes).hexdigest()
    if actual_hash != SOURCE_SHA256:
        raise ValueError(f"vi.py SHA-256 is {actual_hash}, expected {SOURCE_SHA256}")
    output = generate(extract_tables(source_bytes.decode("utf-8")))
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != output:
            print(f"{OUTPUT} is not reproducible from pinned vi.py", file=sys.stderr)
            return 1
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT.with_suffix(OUTPUT.suffix + ".tmp")
    temporary.write_text(output, encoding="utf-8")
    temporary.replace(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
