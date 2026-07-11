#!/usr/bin/env python3
"""Copy the exact pure-Python Chinese closure into a separate English venv.

Run this script with the accepted Chinese-oracle interpreter.  It validates
every installed RECORD entry before and after copying, rejects native or
shared-library payloads, and never modifies the source environment.
"""

from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import importlib.metadata
from pathlib import Path
import shutil
import sys


EXPECTED_PYTHON = (3, 12, 11)
EXPECTED_DISTRIBUTIONS = {
    "cn2an": "0.5.23",
    "jieba": "0.42.1",
    "ordered-set": "4.1.0",
    "proces": "0.1.7",
    "pypinyin": "0.53.0",
    "pypinyin-dict": "0.9.0",
}
NATIVE_SUFFIXES = frozenset(
    {".a", ".dll", ".dylib", ".exe", ".lib", ".node", ".pyd", ".so", ".wasm"}
)
NATIVE_MAGICS = (
    b"\x00asm",  # WebAssembly
    b"\x7fELF",
    b"!<arch>\n",
    b"MZ",  # PE/COFF
    b"\xca\xfe\xba\xbe",  # universal Mach-O / Java class; both are compiled payloads
    b"\xce\xfa\xed\xfe",
    b"\xcf\xfa\xed\xfe",
    b"\xfe\xed\xfa\xce",
    b"\xfe\xed\xfa\xcf",
)


def _fail(message: str) -> "NoReturn":
    raise SystemExit(message)


def _inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def _digest(path: Path, algorithm: str) -> str:
    try:
        digest = hashlib.new(algorithm)
    except ValueError as error:
        _fail(f"unsupported RECORD hash algorithm {algorithm!r}: {error}")
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return base64.urlsafe_b64encode(digest.digest()).rstrip(b"=").decode("ascii")


def _is_native_payload(path: Path) -> bool:
    """Reject compiled payloads by canonical names and bounded file magic."""
    name = path.name.lower()
    if path.suffix.lower() in NATIVE_SUFFIXES or ".so." in name:
        return True
    with path.open("rb") as source:
        prefix = source.read(8)
    return any(prefix.startswith(magic) for magic in NATIVE_MAGICS)


def _records(distribution: importlib.metadata.Distribution, root: Path) -> list[Path]:
    record = Path(distribution.locate_file("")) / f"{distribution.metadata['Name'].replace('-', '_')}-{distribution.version}.dist-info" / "RECORD"
    if not record.is_file():
        candidates = [
            Path(distribution.locate_file(path))
            for path in distribution.files or ()
            if str(path).endswith(".dist-info/RECORD")
        ]
        if len(candidates) != 1 or not candidates[0].is_file():
            _fail(f"{distribution.metadata['Name']} has no unique RECORD")
        record = candidates[0]

    paths: list[Path] = []
    with record.open(newline="", encoding="utf-8") as source:
        for index, row in enumerate(csv.reader(source), start=1):
            if len(row) != 3 or not row[0]:
                _fail(f"{record}: malformed row {index}")
            path = (Path(distribution.locate_file("")) / row[0]).resolve()
            if not _inside(path, root):
                _fail(f"{record}: row {index} escapes the source venv")
            if path.is_symlink() or not path.is_file():
                _fail(f"{record}: row {index} is missing, linked, or not a file")
            if _is_native_payload(path):
                _fail(f"{record}: native/shared-library entry is forbidden: {path}")
            if row[2]:
                try:
                    expected_size = int(row[2])
                except ValueError:
                    _fail(f"{record}: row {index} has an invalid size")
                if path.stat().st_size != expected_size:
                    _fail(f"{record}: row {index} size differs")
            if row[1]:
                if "=" not in row[1]:
                    _fail(f"{record}: row {index} has an invalid hash")
                algorithm, expected_hash = row[1].split("=", 1)
                if _digest(path, algorithm) != expected_hash:
                    _fail(f"{record}: row {index} hash differs")
            paths.append(path)
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True, type=Path)
    arguments = parser.parse_args()
    if sys.version_info[:3] != EXPECTED_PYTHON:
        parser.error(
            "requires CPython {}.{}.{}; got {}".format(
                *EXPECTED_PYTHON, sys.version.split()[0]
            )
        )

    source_root = Path(sys.prefix).resolve()
    destination_root = arguments.destination.expanduser().resolve()
    if source_root == destination_root or _inside(destination_root, source_root):
        parser.error("destination must be a separate virtual environment")
    if not (destination_root / "pyvenv.cfg").is_file():
        parser.error("destination is not an existing virtual environment")

    copied: dict[str, list[Path]] = {}
    for name, expected_version in EXPECTED_DISTRIBUTIONS.items():
        distribution = importlib.metadata.distribution(name)
        if distribution.version != expected_version:
            _fail(
                f"{name} is {distribution.version}; expected {expected_version}"
            )
        source_paths = _records(distribution, source_root)
        destination_paths: list[Path] = []
        for source in source_paths:
            relative = source.relative_to(source_root)
            destination = destination_root / relative
            if destination.exists():
                if not destination.is_file() or source.read_bytes() != destination.read_bytes():
                    _fail(f"destination already contains different bytes: {destination}")
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination, follow_symlinks=False)
            destination_paths.append(destination)
        copied[name] = destination_paths

    for name, paths in copied.items():
        for path in paths:
            if path.is_symlink() or not path.is_file():
                _fail(f"copied {name} entry is missing, linked, or not a file: {path}")
        distribution = importlib.metadata.Distribution.at(
            next(path.parent for path in paths if path.name == "METADATA")
        )
        if distribution.version != EXPECTED_DISTRIBUTIONS[name]:
            _fail(f"copied {name} metadata has the wrong version")
        _records(distribution, destination_root)

    print(
        "copied and verified "
        + ", ".join(
            f"{name}=={version}"
            for name, version in EXPECTED_DISTRIBUTIONS.items()
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
