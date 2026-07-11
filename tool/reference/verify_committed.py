#!/usr/bin/env python3
"""Read-only verification of every accepted pinned-reference fixture."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path
import subprocess
import sys
from typing import Callable, Mapping, Sequence


UPSTREAM_COMMIT = "fba1236595f2d2bf21d414ba6e57d25256afada3"
UPSTREAM_REPOSITORY = "hexgrad/misaki"
UPSTREAM_VERSION = "0.9.4"
LANGUAGES = ("en", "ja", "ko", "zh")
PYTHON_KEYS = (
    "en",
    "en-trf",
    "en-trf-espeak",
    "ja",
    "ja-cutlet",
    "ko",
    "zh",
    "zh-en",
)
_CASE_IDENTITY_FIELDS = (
    "caseId",
    "input",
    "language",
    "mode",
    "options",
    "seed",
)


class ManifestError(ValueError):
    """The committed accepted-fixture manifest is malformed."""


@dataclass(frozen=True)
class FixtureSpec:
    """One accepted fixture and the interpreter family that verifies it."""

    language: str
    python_key: str
    input_path: Path
    expected_path: Path
    case_count: int


def _object(value: object, location: str) -> dict[str, object]:
    if not isinstance(value, dict) or not all(
        isinstance(key, str) for key in value
    ):
        raise ManifestError(f"{location} must be an object with string keys")
    return value


def _object_without_duplicate_keys(
    pairs: Sequence[tuple[str, object]],
) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ManifestError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise ManifestError(f"non-finite JSON number {value!r} is not allowed")


def _decode_json(source: str, location: str) -> object:
    try:
        return json.loads(
            source,
            object_pairs_hook=_object_without_duplicate_keys,
            parse_constant=_reject_json_constant,
        )
    except ManifestError as error:
        raise ManifestError(f"{location}: {error}") from error
    except json.JSONDecodeError as error:
        raise ManifestError(
            f"{location}: invalid JSON at line {error.lineno}, "
            f"column {error.colno}"
        ) from error


def _read_utf8(path: Path, location: str) -> str:
    try:
        return path.read_bytes().decode("utf-8")
    except (OSError, UnicodeError) as error:
        raise ManifestError(f"cannot read {location}: {error}") from error


def _read_jsonl_records(
    path: Path,
    location: str,
) -> list[dict[str, object]]:
    source = _read_utf8(path, location)
    if not source.endswith("\n"):
        raise ManifestError(f"{location} must end with an LF newline")
    if "\r" in source:
        raise ManifestError(f"{location} must use LF line endings")

    records: list[dict[str, object]] = []
    for line_number, line in enumerate(source[:-1].split("\n"), start=1):
        record_location = f"{location}:{line_number}"
        if not line.strip():
            raise ManifestError(f"{record_location}: blank records are forbidden")
        records.append(
            _object(_decode_json(line, record_location), record_location)
        )
    if not records:
        raise ManifestError(f"{location} contains no records")
    return records


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _case_identity_value(record: Mapping[str, object], field: str) -> object:
    if field == "options":
        return record.get(field, {})
    return record.get(field)


def _validate_case_pair(
    input_record: Mapping[str, object],
    expected_record: Mapping[str, object],
    *,
    language: str,
    location: str,
) -> None:
    if input_record.get("language") != language:
        raise ManifestError(
            f"{location} corpus language must match manifest language {language!r}"
        )
    if expected_record.get("language") != language:
        raise ManifestError(
            f"{location} fixture language must match manifest language {language!r}"
        )
    schema_version = expected_record.get("schemaVersion")
    if isinstance(schema_version, bool) or schema_version != 1:
        raise ManifestError(f"{location} fixture schemaVersion must be 1")
    for field in _CASE_IDENTITY_FIELDS:
        if _case_identity_value(input_record, field) != _case_identity_value(
            expected_record, field
        ):
            raise ManifestError(
                f"{location} corpus and fixture differ at field {field!r}"
            )
    for field, value in (
        ("upstreamRepository", UPSTREAM_REPOSITORY),
        ("upstreamCommit", UPSTREAM_COMMIT),
        ("upstreamVersion", UPSTREAM_VERSION),
    ):
        if expected_record.get(field) != value:
            raise ManifestError(
                f"{location} fixture {field} must be {value!r}"
            )


def _validate_provenance(
    *,
    repo_root: Path,
    input_path: Path,
    expected_path: Path,
    case_count: int,
    location: str,
) -> Path:
    provenance_path = expected_path.with_suffix(".provenance.json")
    if not provenance_path.is_file():
        raise ManifestError(
            f"{location} has no adjacent provenance file: "
            f"{provenance_path.name}"
        )
    resolved_provenance = provenance_path.resolve()
    if resolved_provenance.parent != expected_path.parent:
        raise ManifestError(
            f"{location} provenance must stay in the pinned fixture directory"
        )
    provenance = _object(
        _decode_json(
            _read_utf8(provenance_path, str(provenance_path)),
            str(provenance_path),
        ),
        str(provenance_path),
    )
    schema_version = provenance.get("schemaVersion")
    if isinstance(schema_version, bool) or schema_version != 1:
        raise ManifestError(f"{provenance_path} schemaVersion must be 1")

    expected_values: tuple[tuple[str, object], ...] = (
        ("upstreamRepository", UPSTREAM_REPOSITORY),
        ("upstreamCommit", UPSTREAM_COMMIT),
        ("upstreamVersion", UPSTREAM_VERSION),
        ("caseCorpus", input_path.relative_to(repo_root.resolve()).as_posix()),
        ("fixture", expected_path.name),
        ("caseCorpusSha256", _sha256_file(input_path)),
        ("fixtureSha256", _sha256_file(expected_path)),
    )
    for field, expected_value in expected_values:
        if provenance.get(field) != expected_value:
            raise ManifestError(
                f"{provenance_path} {field} does not match the accepted files"
            )
    if "caseCount" in provenance:
        provenance_count = provenance["caseCount"]
        if (
            isinstance(provenance_count, bool)
            or not isinstance(provenance_count, int)
            or provenance_count != case_count
        ):
            raise ManifestError(
                f"{provenance_path} caseCount must be {case_count}"
            )
    return resolved_provenance


def _repo_path(repo_root: Path, value: object, location: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{location} must be a non-empty relative path")
    candidate = Path(value)
    if candidate.is_absolute():
        raise ManifestError(f"{location} must be relative to the repository")
    resolved = (repo_root / candidate).resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError as error:
        raise ManifestError(f"{location} escapes the repository") from error
    if not resolved.is_file():
        raise ManifestError(f"{location} does not identify a file: {value}")
    return resolved


def load_manifest(manifest_path: Path, repo_root: Path) -> list[FixtureSpec]:
    """Loads and strictly validates the accepted fixture manifest."""

    raw = _decode_json(
        _read_utf8(manifest_path, str(manifest_path)),
        str(manifest_path),
    )
    manifest = _object(raw, "manifest")
    if set(manifest) != {"fixtures", "schemaVersion", "upstreamCommit"}:
        raise ManifestError("manifest has missing or unexpected fields")
    schema_version = manifest["schemaVersion"]
    if isinstance(schema_version, bool) or schema_version != 1:
        raise ManifestError("manifest schemaVersion must be 1")
    if manifest["upstreamCommit"] != UPSTREAM_COMMIT:
        raise ManifestError(
            f"manifest upstreamCommit must be {UPSTREAM_COMMIT}"
        )
    raw_fixtures = manifest["fixtures"]
    if not isinstance(raw_fixtures, list) or not raw_fixtures:
        raise ManifestError("manifest fixtures must be a non-empty array")

    specs: list[FixtureSpec] = []
    seen_expected: set[Path] = set()
    seen_provenance: set[Path] = set()
    expected_directory = (
        repo_root / "test/fixtures/upstream" / UPSTREAM_COMMIT
    ).resolve()
    input_directory = (repo_root / "tool/reference/cases").resolve()
    for index, value in enumerate(raw_fixtures):
        location = f"fixtures[{index}]"
        item = _object(value, location)
        if set(item) != {
            "caseCount",
            "expected",
            "input",
            "language",
            "pythonKey",
        }:
            raise ManifestError(f"{location} has missing or unexpected fields")
        language = item["language"]
        python_key = item["pythonKey"]
        case_count = item["caseCount"]
        if language not in LANGUAGES:
            raise ManifestError(f"{location}.language is not accepted")
        if python_key not in PYTHON_KEYS:
            raise ManifestError(f"{location}.pythonKey is not accepted")
        if language not in ("en", "ja", "zh") and python_key != language:
            raise ManifestError(
                f"{location}.pythonKey must match its language family"
            )
        if isinstance(case_count, bool) or not isinstance(case_count, int):
            raise ManifestError(f"{location}.caseCount must be an integer")
        if case_count <= 0:
            raise ManifestError(f"{location}.caseCount must be positive")
        input_path = _repo_path(repo_root, item["input"], f"{location}.input")
        expected_path = _repo_path(
            repo_root, item["expected"], f"{location}.expected"
        )
        if input_path.parent != input_directory:
            raise ManifestError(
                f"{location}.input must be in tool/reference/cases"
            )
        if expected_path.parent != expected_directory:
            raise ManifestError(
                f"{location}.expected must be in the pinned fixture directory"
            )
        if input_path.suffix != ".jsonl" or expected_path.suffix != ".jsonl":
            raise ManifestError(f"{location} paths must be JSONL files")
        if expected_path in seen_expected:
            raise ManifestError(f"{location}.expected is duplicated")
        seen_expected.add(expected_path)
        expected_records = _read_jsonl_records(
            expected_path,
            f"{location}.expected",
        )
        if len(expected_records) != case_count:
            raise ManifestError(
                f"{location}.caseCount is {case_count}, fixture has "
                f"{len(expected_records)} records"
            )
        input_records = _read_jsonl_records(
            input_path,
            f"{location}.input",
        )
        if len(input_records) != case_count:
            raise ManifestError(
                f"{location}.caseCount is {case_count}, corpus has "
                f"{len(input_records)} records"
            )
        modes: set[str] = set()
        for record_index, record in enumerate(input_records, start=1):
            mode = record.get("mode")
            if not isinstance(mode, str) or not mode:
                raise ManifestError(
                    f"{location} record {record_index} mode must be a "
                    "non-empty string"
                )
            modes.add(mode)
        if language == "en":
            transformer_values: set[bool] = set()
            espeak_values: set[bool] = set()
            for record_index, record in enumerate(input_records, start=1):
                options = _object(
                    record.get("options", {}),
                    f"{location} record {record_index} options",
                )
                transformer = options.get("trf", False)
                if not isinstance(transformer, bool):
                    raise ManifestError(
                        f"{location} record {record_index} options.trf must "
                        "be a boolean"
                    )
                transformer_values.add(transformer)
                espeak_values.add("espeak" in str(record.get("mode", "")))
            if len(espeak_values) != 1:
                raise ManifestError(
                    f"{location} must not mix eSpeak and no-fallback English cases"
                )
            if transformer_values == {True} and espeak_values == {True}:
                required_python_key = "en-trf-espeak"
            elif transformer_values == {True}:
                required_python_key = "en-trf"
            elif True in transformer_values:
                raise ManifestError(
                    f"{location} must not mix transformer and small-model "
                    "English cases"
                )
            else:
                required_python_key = "en"
            if python_key != required_python_key:
                raise ManifestError(
                    f"{location}.pythonKey must be {required_python_key!r} "
                    "for its English model mode"
                )
        elif language == "ja":
            if modes == {"cutlet"}:
                required_python_key = "ja-cutlet"
            elif "cutlet" in modes:
                raise ManifestError(
                    f"{location} must not mix cutlet and non-cutlet modes"
                )
            else:
                required_python_key = "ja"
            if python_key != required_python_key:
                raise ManifestError(
                    f"{location}.pythonKey must be {required_python_key!r} "
                    f"for its Japanese mode"
                )
        elif language == "zh":
            callback_mode = "frontend-1.1-en-small-no-fallback"
            if modes == {callback_mode}:
                required_python_key = "zh-en"
            elif callback_mode in modes:
                raise ManifestError(
                    f"{location} must not mix combined-callback and "
                    "Chinese-only modes"
                )
            else:
                required_python_key = "zh"
            if python_key != required_python_key:
                raise ManifestError(
                    f"{location}.pythonKey must be {required_python_key!r} "
                    f"for its Chinese mode"
                )
        for record_index, (input_record, expected_record) in enumerate(
            zip(input_records, expected_records),
            start=1,
        ):
            _validate_case_pair(
                input_record,
                expected_record,
                language=language,
                location=f"{location} record {record_index}",
            )
        seen_provenance.add(
            _validate_provenance(
                repo_root=repo_root,
                input_path=input_path,
                expected_path=expected_path,
                case_count=case_count,
                location=location,
            )
        )
        specs.append(
            FixtureSpec(
                language=language,
                python_key=python_key,
                input_path=input_path,
                expected_path=expected_path,
                case_count=case_count,
            )
        )

    committed_expected = {
        path.resolve() for path in expected_directory.glob("*.jsonl")
    }
    if seen_expected != committed_expected:
        unlisted = sorted(
            path.name for path in committed_expected - seen_expected
        )
        unexpected = sorted(
            path.name for path in seen_expected - committed_expected
        )
        detail = []
        if unlisted:
            detail.append(f"unlisted fixtures: {', '.join(unlisted)}")
        if unexpected:
            detail.append(f"unexpected fixtures: {', '.join(unexpected)}")
        raise ManifestError(
            "manifest does not exactly cover the pinned fixture directory ("
            + "; ".join(detail)
            + ")"
        )

    committed_provenance = {
        path.resolve()
        for path in expected_directory.glob("*.provenance.json")
    }
    if seen_provenance != committed_provenance:
        orphaned = sorted(
            path.name for path in committed_provenance - seen_provenance
        )
        missing = sorted(
            path.name for path in seen_provenance - committed_provenance
        )
        detail = []
        if orphaned:
            detail.append(f"orphaned provenance: {', '.join(orphaned)}")
        if missing:
            detail.append(f"missing provenance: {', '.join(missing)}")
        raise ManifestError(
            "manifest does not exactly cover fixture provenance ("
            + "; ".join(detail)
            + ")"
        )
    return specs


def verification_command(
    spec: FixtureSpec,
    *,
    python: str,
    exporter: Path,
    upstream_root: Path,
    verbose_errors: bool,
) -> list[str]:
    """Builds the argument-vector-only command for one read-only replay."""

    command = [
        python,
        str(exporter),
        "verify",
        "--upstream-root",
        str(upstream_root),
        "--input",
        str(spec.input_path),
        "--expected",
        str(spec.expected_path),
    ]
    if verbose_errors:
        command.append("--verbose-errors")
    return command


def verify_all(
    specs: Sequence[FixtureSpec],
    *,
    interpreters: Mapping[str, str],
    exporter: Path,
    upstream_root: Path,
    repo_root: Path,
    verbose_errors: bool,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> int:
    """Runs every selected fixture verification and returns a process code."""

    environment = dict(os.environ)
    environment["PYTHONHASHSEED"] = "0"
    failures = 0
    for spec in specs:
        result = runner(
            verification_command(
                spec,
                python=interpreters[spec.python_key],
                exporter=exporter,
                upstream_root=upstream_root,
                verbose_errors=verbose_errors,
            ),
            cwd=repo_root,
            env=environment,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            failures += 1
    if failures:
        print(
            f"failed {failures} of {len(specs)} committed fixture verifications",
            file=sys.stderr,
        )
        return 1
    print(
        f"verified {sum(spec.case_count for spec in specs)} committed cases "
        f"across {len(specs)} fixture files"
    )
    return 0


def _parser(repo_root: Path) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=repo_root / "tool/reference/accepted_fixtures.json",
    )
    parser.add_argument(
        "--upstream-root",
        type=Path,
        default=Path(
            os.environ.get("MISAKI_UPSTREAM_ROOT", "/private/tmp/misaki-upstream")
        ),
    )
    for python_key in PYTHON_KEYS:
        destination = "python_" + python_key.replace("-", "_")
        environment_key = python_key.upper().replace("-", "_")
        parser.add_argument(
            f"--python-{python_key}",
            dest=destination,
            default=os.environ.get(
                f"MISAKI_ORACLE_{environment_key}_PYTHON", sys.executable
            ),
            help=f"locked {python_key} oracle interpreter",
        )
    parser.add_argument(
        "--language",
        action="append",
        choices=LANGUAGES,
        help="verify only this language; may be repeated",
    )
    parser.add_argument("--verbose-errors", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Command-line entry point."""

    repo_root = Path(__file__).resolve().parents[2]
    args = _parser(repo_root).parse_args(argv)
    try:
        specs = load_manifest(args.manifest.resolve(), repo_root)
    except ManifestError as error:
        print(f"invalid accepted-fixture manifest: {error}", file=sys.stderr)
        return 2
    languages = set(args.language or LANGUAGES)
    selected = [spec for spec in specs if spec.language in languages]
    interpreters = {
        python_key: getattr(args, "python_" + python_key.replace("-", "_"))
        for python_key in PYTHON_KEYS
    }
    return verify_all(
        selected,
        interpreters=interpreters,
        exporter=repo_root / "tool/reference/export_fixtures.py",
        upstream_root=args.upstream_root.resolve(),
        repo_root=repo_root,
        verbose_errors=args.verbose_errors,
    )


if __name__ == "__main__":
    raise SystemExit(main())
