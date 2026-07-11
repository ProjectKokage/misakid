#!/usr/bin/env python3
"""Audit and inventory the exact en_core_web_trf 3.8.0 wheel.

The wheel is an explicit development-time input. This tool never downloads,
installs, imports, or executes it. It first enforces the reviewed whole-file
size and SHA-256, then reads the ZIP through bounded, traversal-safe paths and
hashes every regular member. ``--accept`` writes an unaccepted candidate only
while the spec says no inventory has been accepted. After human review, the
candidate digest and acceptance flag must be recorded manually in the spec;
only then can the read-only ``--check`` operation succeed. The tool never
rewrites its spec.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import stat
import sys
import zipfile


SCHEMA_VERSION = 1
BUFFER_SIZE = 1024 * 1024
MAX_ENTRIES = 10_000
MAX_MEMBER_BYTES = 1024 * 1024 * 1024
MAX_TOTAL_BYTES = 2 * 1024 * 1024 * 1024
MAX_EXPANSION_RATIO = 100
MAX_LOCAL_MANIFEST_BYTES = 8 * 1024 * 1024
MAX_INVENTORY_BYTES = 64 * 1024 * 1024
SUPPORTED_COMPRESSION = frozenset((zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED))
DEFAULT_SPEC = Path(__file__).with_name("en_trf_resource_spec.json")
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]

EXPECTED_ROOT_FIELDS = frozenset(
    (
        "schemaVersion",
        "upstream",
        "modelWheel",
        "python312RuntimeDelta",
        "requirements",
        "preparedCorpora",
        "requiredModelMemberSuffixes",
        "acceptanceState",
    )
)
EXPECTED_UPSTREAM = {
    "repository": "https://github.com/hexgrad/misaki",
    "commit": "fba1236595f2d2bf21d414ba6e57d25256afada3",
    "version": "0.9.4",
    "enPySha256": "a9c36c90a3fa6c6084e9042fd8e19f6049add4f1435d8fe5ca1b77f3529a98f4",
    "uvLockSha256": "52d912cb52640c6b472c40258ee9c49edb63c1397ac1fb85c0dc17ad06654bd9",
}
EXPECTED_MODEL_STATIC_FIELDS = {
    "distribution": "en-core-web-trf",
    "version": "3.8.0",
    "url": (
        "https://github.com/explosion/spacy-models/releases/download/"
        "en_core_web_trf-3.8.0/en_core_web_trf-3.8.0-py3-none-any.whl"
    ),
    "releaseRepositoryCommit": "374ece89b2099818244f5a65ef466b89c0c392ae",
    "declaredLicense": "MIT",
}
EXPECTED_RUNTIME_DELTA = (
    {
        "distribution": "curated-tokenizers",
        "version": "0.0.9",
        "sdistSizeBytes": 2237055,
        "sdistSha256": "c93d47e54ab3528a6db2796eeb4bdce5d44e8226c671e42c2f23522ab1d0ce25",
        "macosArm64WheelSizeBytes": 703466,
        "macosArm64WheelSha256": "2abbb571666a9c9b3a15f9df022e25ed1137e9fa8346788aaa747c00f940a3c6",
    },
    {
        "distribution": "curated-transformers",
        "version": "0.1.1",
        "sdistSizeBytes": 16313,
        "sdistSha256": "4671f03314df30efda2ec2b59bc7692ea34fcea44cb65382342c16684e8a2119",
        "wheelSizeBytes": 25972,
        "wheelSha256": "d716063d73d803c6925d2dab56fde9b9ab8e89e663c2c0587804944ba488ff01",
    },
    {
        "distribution": "spacy-curated-transformers",
        "version": "0.3.0",
        "sdistSizeBytes": 218192,
        "sdistSha256": "989a6bf2aa7becd1ac8c3be5f245cd489223d4e16e7218f6b69479c7e2689937",
        "wheelSizeBytes": 236322,
        "wheelSha256": "ddfd33e81b53ad798dac841ab022189f9543718ff874eda1081fce6ff93de377",
    },
    {
        "distribution": "torch",
        "version": "2.6.0",
        "macosArm64Python312WheelSizeBytes": 66532538,
        "macosArm64Python312WheelSha256": "9a610afe216a85a8b9bc9f8365ed561535c93e804c2a317ef7fabcc5deda0989",
    },
)
EXPECTED_REQUIREMENTS = {
    "path": "tool/reference/requirements-en-trf-py312.txt",
    "sha256": "ba6ff423296bb16365a4c5093234648ba7d683826b4c81b478d5d0036f60d7ba",
}
EXPECTED_CORPORA = (
    {
        "path": "tool/reference/cases/en_american_trf_no_fallback.jsonl",
        "caseCount": 38,
        "sha256": "10e7dd90c1c9a27e2f9eae2c16f10037636361c76b030c87027a65bb2bf0c04d",
        "mode": "american-no-fallback",
    },
    {
        "path": "tool/reference/cases/en_british_trf_no_fallback.jsonl",
        "caseCount": 38,
        "sha256": "3fc2929e1ebafe0d77ba124e7ecfd61e454230997228dd807118c85726ee66da",
        "mode": "british-no-fallback",
    },
)
EXPECTED_MEMBER_SUFFIXES = (
    "/config.cfg",
    "/meta.json",
    "/tokenizer",
    "/vocab/lookups.bin",
    "/transformer/model",
    "/tagger/model",
)
EXPECTED_ACCEPTANCE_FIELDS = frozenset(
    (
        "wholeWheelIdentityReviewed",
        "memberInventoryAccepted",
        "memberInventorySha256",
        "transformerFixturesAccepted",
    )
)


class AuditError(ValueError):
    """A stable transformer artifact or archive validation failure."""


def _sha256_stream(stream) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = stream.read(BUFFER_SIZE)
        if not chunk:
            return digest.hexdigest(), size
        digest.update(chunk)
        size += len(chunk)


def _load_json(path: Path, label: str) -> dict[str, object]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise AuditError(f"Could not read {label}: {error}") from error
    if not isinstance(decoded, dict):
        raise AuditError(f"{label} must contain a JSON object")
    return decoded


def _require_map(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict) or not all(
        isinstance(key, str) for key in value
    ):
        raise AuditError(f"{label} must be a string-keyed object")
    return value


def _require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise AuditError(f"{label} must be a non-empty string")
    return value


def _require_int(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise AuditError(f"{label} must be a nonnegative integer")
    return value


def _require_bool(value: object, label: str) -> bool:
    if not isinstance(value, bool):
        raise AuditError(f"{label} must be a boolean")
    return value


def _require_sha256(value: object, label: str) -> str:
    digest = _require_string(value, label)
    if len(digest) != 64 or any(
        character not in "0123456789abcdef" for character in digest
    ):
        raise AuditError(f"{label} must be 64 lowercase hexadecimal characters")
    return digest


def _require_exact_fields(
    value: dict[str, object], expected: frozenset[str], label: str
) -> None:
    actual = frozenset(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise AuditError(
            f"{label} fields are malformed (missing={missing}, extra={extra})"
        )


def _repository_file(
    repository_root: Path, relative_path: object, label: str
) -> Path:
    text = _require_string(relative_path, f"{label}.path")
    if "\\" in text or text.startswith("/"):
        raise AuditError(f"{label}.path must be a repository-relative POSIX path")
    pure = PurePosixPath(text)
    if (
        pure.is_absolute()
        or any(part in ("", ".", "..") for part in pure.parts)
        or posixpath.normpath(text) != text
        or "//" in text
        or pure.parts[0].endswith(":")
    ):
        raise AuditError(f"{label}.path must be a canonical repository path")

    root = repository_root.resolve()
    candidate = root
    for part in pure.parts:
        candidate /= part
        if candidate.is_symlink():
            raise AuditError(f"{label}.path must not traverse a symbolic link")
    try:
        resolved = candidate.resolve(strict=True)
        metadata = resolved.stat()
    except OSError as error:
        raise AuditError(f"Could not read {label}: {error}") from error
    if os.path.commonpath((str(root), str(resolved))) != str(root):
        raise AuditError(f"{label}.path escapes the repository")
    if not stat.S_ISREG(metadata.st_mode):
        raise AuditError(f"{label}.path must identify a regular file")
    if metadata.st_size > MAX_LOCAL_MANIFEST_BYTES:
        raise AuditError(f"{label} exceeds the local manifest size bound")
    return resolved


def _validated_local_bytes(
    repository_root: Path,
    record: dict[str, object],
    label: str,
) -> bytes:
    _require_exact_fields(record, frozenset(("path", "sha256")), label)
    expected_digest = _require_sha256(record.get("sha256"), f"{label}.sha256")
    path = _repository_file(repository_root, record.get("path"), label)
    try:
        contents = path.read_bytes()
    except OSError as error:
        raise AuditError(f"Could not read {label}: {error}") from error
    actual_digest = hashlib.sha256(contents).hexdigest()
    if actual_digest != expected_digest:
        raise AuditError(
            f"{label} SHA-256 mismatch: expected {expected_digest}, got {actual_digest}"
        )
    return contents


def _validate_corpus(
    repository_root: Path,
    record: dict[str, object],
    expected: dict[str, object],
    index: int,
) -> None:
    label = f"preparedCorpora[{index}]"
    _require_exact_fields(record, frozenset(("path", "caseCount", "sha256")), label)
    if record != {key: expected[key] for key in ("path", "caseCount", "sha256")}:
        raise AuditError(f"{label} does not match the pinned corpus record")
    case_count = _require_int(record.get("caseCount"), f"{label}.caseCount")
    contents = _validated_local_bytes(
        repository_root,
        {"path": record["path"], "sha256": record["sha256"]},
        label,
    )
    try:
        text = contents.decode("utf-8")
    except UnicodeError as error:
        raise AuditError(f"{label} is not UTF-8: {error}") from error
    lines = text.splitlines()
    if len(lines) != case_count or any(not line for line in lines):
        raise AuditError(
            f"{label} contains {len(lines)} rows; expected exactly {case_count}"
        )
    case_ids: set[str] = set()
    for line_number, line in enumerate(lines, 1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise AuditError(
                f"{label} row {line_number} is malformed JSON: {error}"
            ) from error
        if not isinstance(row, dict):
            raise AuditError(f"{label} row {line_number} must contain an object")
        case_id = row.get("caseId")
        if not isinstance(case_id, str) or not case_id or case_id in case_ids:
            raise AuditError(f"{label} row {line_number} has an invalid caseId")
        case_ids.add(case_id)
        options = row.get("options")
        if (
            row.get("language") != "en"
            or row.get("mode") != expected["mode"]
            or not isinstance(options, dict)
            or options.get("trf") is not True
        ):
            raise AuditError(f"{label} row {line_number} is not a transformer case")


def _acceptance_state(spec: dict[str, object]) -> dict[str, object]:
    return _require_map(spec.get("acceptanceState"), "acceptanceState")


def _load_spec(
    path: Path, repository_root: Path = REPOSITORY_ROOT
) -> dict[str, object]:
    spec = _load_json(path, "transformer resource spec")
    _require_exact_fields(spec, EXPECTED_ROOT_FIELDS, "transformer resource spec")
    if spec.get("schemaVersion") != SCHEMA_VERSION:
        raise AuditError("Unsupported transformer resource spec schema")

    upstream = _require_map(spec.get("upstream"), "upstream")
    _require_exact_fields(upstream, frozenset(EXPECTED_UPSTREAM), "upstream")
    if upstream != EXPECTED_UPSTREAM:
        raise AuditError("upstream does not match the pinned Misaki source identity")

    wheel = _require_map(spec.get("modelWheel"), "modelWheel")
    _require_exact_fields(
        wheel,
        frozenset((*EXPECTED_MODEL_STATIC_FIELDS, "sizeBytes", "sha256")),
        "modelWheel",
    )
    for field, expected in EXPECTED_MODEL_STATIC_FIELDS.items():
        if wheel.get(field) != expected:
            raise AuditError(f"modelWheel.{field} does not match the reviewed artifact")
    _require_sha256(wheel.get("sha256"), "modelWheel.sha256")
    expected_size = _require_int(wheel.get("sizeBytes"), "modelWheel.sizeBytes")
    if expected_size == 0 or expected_size > MAX_TOTAL_BYTES:
        raise AuditError("modelWheel.sizeBytes is outside the supported bound")

    runtime_delta = spec.get("python312RuntimeDelta")
    if not isinstance(runtime_delta, list):
        raise AuditError("python312RuntimeDelta must be an array")
    if runtime_delta != list(EXPECTED_RUNTIME_DELTA):
        raise AuditError("python312RuntimeDelta does not match the pinned runtime closure")
    for index, record in enumerate(runtime_delta):
        runtime_record = _require_map(record, f"python312RuntimeDelta[{index}]")
        for field, value in runtime_record.items():
            if field.endswith("Sha256"):
                _require_sha256(value, f"python312RuntimeDelta[{index}].{field}")
            elif field.endswith("SizeBytes"):
                if _require_int(value, f"python312RuntimeDelta[{index}].{field}") == 0:
                    raise AuditError(
                        f"python312RuntimeDelta[{index}].{field} must be positive"
                    )

    requirements = _require_map(spec.get("requirements"), "requirements")
    if requirements != EXPECTED_REQUIREMENTS:
        raise AuditError("requirements does not match the pinned requirements record")
    _validated_local_bytes(repository_root, requirements, "requirements")

    corpora = spec.get("preparedCorpora")
    if not isinstance(corpora, list) or len(corpora) != len(EXPECTED_CORPORA):
        raise AuditError("preparedCorpora must contain the two pinned corpora")
    for index, (record, expected) in enumerate(zip(corpora, EXPECTED_CORPORA)):
        _validate_corpus(
            repository_root,
            _require_map(record, f"preparedCorpora[{index}]"),
            expected,
            index,
        )

    suffixes = spec.get("requiredModelMemberSuffixes")
    if (
        not isinstance(suffixes, list)
        or tuple(suffixes) != EXPECTED_MEMBER_SUFFIXES
        or not all(
            isinstance(suffix, str)
            and suffix.startswith("/")
            and ".." not in PurePosixPath(suffix).parts
            for suffix in suffixes
        )
        or len(suffixes) != len(set(suffixes))
    ):
        raise AuditError("requiredModelMemberSuffixes is malformed")

    acceptance = _require_map(spec.get("acceptanceState"), "acceptanceState")
    _require_exact_fields(acceptance, EXPECTED_ACCEPTANCE_FIELDS, "acceptanceState")
    whole_reviewed = _require_bool(
        acceptance.get("wholeWheelIdentityReviewed"),
        "acceptanceState.wholeWheelIdentityReviewed",
    )
    if not whole_reviewed:
        raise AuditError("The whole-wheel identity has not been reviewed")
    inventory_accepted = _require_bool(
        acceptance.get("memberInventoryAccepted"),
        "acceptanceState.memberInventoryAccepted",
    )
    inventory_digest = acceptance.get("memberInventorySha256")
    if inventory_accepted:
        _require_sha256(
            inventory_digest, "acceptanceState.memberInventorySha256"
        )
    elif inventory_digest is not None:
        raise AuditError(
            "memberInventorySha256 must be null until the inventory is accepted"
        )
    _require_bool(
        acceptance.get("transformerFixturesAccepted"),
        "acceptanceState.transformerFixturesAccepted",
    )
    return spec


def _identity(path: Path, stream) -> tuple[os.stat_result, str, int]:
    before = os.fstat(stream.fileno())
    if not stat.S_ISREG(before.st_mode):
        raise AuditError("Transformer wheel must be a regular file")
    if path.is_symlink():
        raise AuditError("Transformer wheel path must not be a symbolic link")
    stream.seek(0)
    digest, size = _sha256_stream(stream)
    stream.seek(0)
    return before, digest, size


def _same_file(left: os.stat_result, right: os.stat_result) -> bool:
    return (
        left.st_dev,
        left.st_ino,
        left.st_size,
        left.st_mtime_ns,
    ) == (
        right.st_dev,
        right.st_ino,
        right.st_size,
        right.st_mtime_ns,
    )


def _validate_member_path(name: str, is_directory: bool) -> str:
    if not name or "\x00" in name or "\\" in name or name.startswith("/"):
        raise AuditError(f"Unsafe wheel member path: {name!r}")
    normalized = name[:-1] if is_directory and name.endswith("/") else name
    if not normalized or name.endswith("/") != is_directory:
        raise AuditError(f"Non-canonical wheel member path: {name!r}")
    pure = PurePosixPath(normalized)
    if (
        pure.is_absolute()
        or any(part in ("", ".", "..") for part in pure.parts)
        or posixpath.normpath(normalized) != normalized
        or "//" in normalized
        or pure.parts[0].endswith(":")
    ):
        raise AuditError(f"Unsafe wheel member path: {name!r}")
    return normalized


def _member_kind(info: zipfile.ZipInfo) -> str:
    unix_mode = info.external_attr >> 16
    file_type = stat.S_IFMT(unix_mode)
    if info.is_dir():
        if file_type not in (0, stat.S_IFDIR):
            raise AuditError(f"Directory member has incompatible type: {info.filename}")
        return "directory"
    if file_type == stat.S_IFLNK:
        raise AuditError(f"Symbolic-link member is forbidden: {info.filename}")
    if file_type not in (0, stat.S_IFREG):
        raise AuditError(f"Unsupported archive member type: {info.filename}")
    return "file"


def _inventory_from_zip(
    stream,
    required_suffixes: list[str],
) -> dict[str, object]:
    try:
        archive = zipfile.ZipFile(stream, mode="r")
    except (OSError, zipfile.BadZipFile) as error:
        raise AuditError(f"Transformer wheel is not a valid ZIP: {error}") from error
    with archive:
        if archive.comment:
            raise AuditError("Transformer wheel ZIP comment must be empty")
        infos = archive.infolist()
        if not infos or len(infos) > MAX_ENTRIES:
            raise AuditError(
                f"Transformer wheel entry count must be 1..{MAX_ENTRIES}"
            )
        seen: set[str] = set()
        seen_casefolded: set[str] = set()
        total_uncompressed = 0
        total_compressed = 0
        members: list[dict[str, object]] = []
        member_bytes: dict[str, bytes] = {}

        for info in infos:
            kind = _member_kind(info)
            path = _validate_member_path(info.filename, kind == "directory")
            folded = path.casefold()
            if path in seen or folded in seen_casefolded:
                raise AuditError(f"Duplicate or colliding wheel member: {path}")
            seen.add(path)
            seen_casefolded.add(folded)
            if info.flag_bits & 0x1:
                raise AuditError(f"Encrypted wheel member is forbidden: {path}")
            if info.compress_type not in SUPPORTED_COMPRESSION:
                raise AuditError(f"Unsupported compression for wheel member: {path}")
            if info.file_size < 0 or info.file_size > MAX_MEMBER_BYTES:
                raise AuditError(f"Wheel member exceeds the size bound: {path}")
            if info.compress_size < 0:
                raise AuditError(f"Wheel member has a negative compressed size: {path}")
            if (
                (info.file_size > 0 and info.compress_size == 0)
                or (
                    info.compress_size > 0
                    and info.file_size
                    > info.compress_size * MAX_EXPANSION_RATIO
                )
            ):
                raise AuditError(f"Wheel member exceeds the expansion bound: {path}")
            total_uncompressed += info.file_size
            total_compressed += info.compress_size
            if total_uncompressed > MAX_TOTAL_BYTES:
                raise AuditError("Transformer wheel exceeds the total size bound")

            if kind == "directory":
                if info.file_size != 0:
                    raise AuditError(f"Directory member is non-empty: {path}")
                digest = hashlib.sha256(b"").hexdigest()
            else:
                try:
                    with archive.open(info, mode="r") as source:
                        digest, extracted_size = _sha256_stream(source)
                except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                    raise AuditError(f"Could not read wheel member {path}: {error}") from error
                if extracted_size != info.file_size:
                    raise AuditError(f"Wheel member size changed while reading: {path}")
                if any(path.endswith(suffix) for suffix in required_suffixes):
                    if info.file_size > 4 * 1024 * 1024 and not path.endswith(
                        ("/transformer/model", "/tagger/model")
                    ):
                        raise AuditError(f"Required metadata member is unexpectedly large: {path}")
                    if info.file_size <= 4 * 1024 * 1024:
                        with archive.open(info, mode="r") as source:
                            member_bytes[path] = source.read()
            members.append(
                {
                    "path": path,
                    "kind": kind,
                    "sizeBytes": info.file_size,
                    "compressedSizeBytes": info.compress_size,
                    "compression": info.compress_type,
                    "crc32": f"{info.CRC:08x}",
                    "sha256": digest,
                }
            )

        members.sort(key=lambda member: str(member["path"]))
        matches: dict[str, dict[str, object]] = {}
        candidate_roots: set[str] | None = None
        for suffix in required_suffixes:
            candidates = [
                member
                for member in members
                if member["kind"] == "file"
                and str(member["path"]).endswith(suffix)
            ]
            if not candidates:
                raise AuditError(
                    f"Required suffix {suffix!r} matched no members"
                )
            suffix_roots = {
                str(candidate["path"])[: -len(suffix)]
                for candidate in candidates
            }
            candidate_roots = (
                suffix_roots
                if candidate_roots is None
                else candidate_roots.intersection(suffix_roots)
            )
        if candidate_roots is None or len(candidate_roots) != 1:
            raise AuditError("Required model members do not share one package root")
        model_root = candidate_roots.pop()
        expected_root = "en_core_web_trf/en_core_web_trf-3.8.0"
        if model_root != expected_root:
            raise AuditError(
                f"Unexpected transformer model package root: {model_root!r}"
            )
        members_by_path = {
            str(member["path"]): member
            for member in members
            if member["kind"] == "file"
        }
        for suffix in required_suffixes:
            expected_path = f"{model_root}{suffix}"
            try:
                matches[suffix] = members_by_path[expected_path]
            except KeyError as error:
                raise AuditError(
                    f"Required model member is missing: {expected_path}"
                ) from error

        meta_path = str(matches["/meta.json"]["path"])
        try:
            model_metadata = json.loads(member_bytes[meta_path].decode("utf-8"))
        except (KeyError, UnicodeError, json.JSONDecodeError) as error:
            raise AuditError(f"Model meta.json is malformed: {error}") from error
        if not isinstance(model_metadata, dict):
            raise AuditError("Model meta.json must contain an object")
        if model_metadata.get("lang") != "en":
            raise AuditError("Model meta.json lang must be en")
        if model_metadata.get("name") != "core_web_trf":
            raise AuditError("Model meta.json name must be core_web_trf")
        if model_metadata.get("version") != "3.8.0":
            raise AuditError("Model meta.json version must be 3.8.0")
        if model_metadata.get("license") != "MIT":
            raise AuditError("Model meta.json license must be MIT")
        components = model_metadata.get("components")
        if not isinstance(components, list) or not {"transformer", "tagger"}.issubset(
            set(components)
        ):
            raise AuditError("Model meta.json lacks transformer/tagger components")

        config_path = str(matches["/config.cfg"]["path"])
        try:
            config_text = member_bytes[config_path].decode("utf-8")
        except (KeyError, UnicodeError) as error:
            raise AuditError(f"Model config.cfg is malformed: {error}") from error
        if (
            not config_text
            or "[components.transformer]" not in config_text
            or "[components.tagger]" not in config_text
        ):
            raise AuditError("Model config.cfg lacks transformer/tagger sections")

        return {
            "entryCount": len(members),
            "totalUncompressedBytes": total_uncompressed,
            "totalCompressedBytes": total_compressed,
            "modelPackageRoot": model_root,
            "requiredMembers": matches,
            "modelMetadata": model_metadata,
            "configUtf8Sha256": hashlib.sha256(config_text.encode("utf-8")).hexdigest(),
            "members": members,
        }


def audit_wheel(wheel_path: Path, spec: dict[str, object]) -> dict[str, object]:
    wheel_spec = _require_map(spec.get("modelWheel"), "modelWheel")
    expected_size = _require_int(wheel_spec.get("sizeBytes"), "modelWheel.sizeBytes")
    expected_hash = _require_sha256(wheel_spec.get("sha256"), "modelWheel.sha256")
    suffixes_raw = spec.get("requiredModelMemberSuffixes")
    if not isinstance(suffixes_raw, list) or not all(
        isinstance(suffix, str) for suffix in suffixes_raw
    ):
        raise AuditError("requiredModelMemberSuffixes is malformed")
    required_suffixes = list(suffixes_raw)

    try:
        with wheel_path.open("rb") as stream:
            before, digest, size = _identity(wheel_path, stream)
            if size != expected_size:
                raise AuditError(
                    f"Transformer wheel size mismatch: expected {expected_size}, got {size}"
                )
            if digest != expected_hash:
                raise AuditError(
                    f"Transformer wheel SHA-256 mismatch: expected {expected_hash}, got {digest}"
                )
            inventory = _inventory_from_zip(stream, required_suffixes)
            after, second_digest, second_size = _identity(wheel_path, stream)
            if not _same_file(before, after) or second_size != size or second_digest != digest:
                raise AuditError("Transformer wheel changed while it was audited")
    except AuditError:
        raise
    except OSError as error:
        raise AuditError(f"Could not read transformer wheel: {error}") from error

    return {
        "schemaVersion": SCHEMA_VERSION,
        "artifact": {
            "distribution": wheel_spec["distribution"],
            "version": wheel_spec["version"],
            "sizeBytes": size,
            "sha256": digest,
        },
        "zip": inventory,
    }


def _render(payload: dict[str, object]) -> bytes:
    return (
        json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def _read_inventory(path: Path) -> bytes:
    try:
        with path.open("rb") as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode) or path.is_symlink():
                raise AuditError("Inventory path must be a non-symbolic regular file")
            if before.st_size > MAX_INVENTORY_BYTES:
                raise AuditError("Inventory exceeds the size bound")
            contents = stream.read(MAX_INVENTORY_BYTES + 1)
            after = os.fstat(stream.fileno())
    except AuditError:
        raise
    except OSError as error:
        raise AuditError(f"Could not read transformer inventory: {error}") from error
    if len(contents) > MAX_INVENTORY_BYTES:
        raise AuditError("Inventory exceeds the size bound")
    if not _same_file(before, after) or len(contents) != before.st_size:
        raise AuditError("Transformer inventory changed while it was read")
    return contents


def _write_candidate(path: Path, rendered: bytes) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("xb") as target:
            target.write(rendered)
            target.flush()
            os.fsync(target.fileno())
        return True
    except FileExistsError:
        existing = _read_inventory(path)
        if existing != rendered:
            raise AuditError(
                "Candidate inventory already exists with different contents"
            )
        return False
    except AuditError:
        raise
    except OSError as error:
        raise AuditError(f"Could not write candidate inventory: {error}") from error


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel", required=True, type=Path)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--accept", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(arguments)
    if args.accept == args.check:
        parser.error("select exactly one of --accept or --check")

    try:
        spec = _load_spec(args.spec)
        acceptance = _acceptance_state(spec)
        inventory_accepted = _require_bool(
            acceptance.get("memberInventoryAccepted"),
            "acceptanceState.memberInventoryAccepted",
        )
        if args.accept and inventory_accepted:
            raise AuditError(
                "An inventory is already accepted; --accept cannot replace it"
            )
        if args.check and not inventory_accepted:
            raise AuditError(
                "No member inventory is accepted; generate and review a candidate first"
            )

        payload = audit_wheel(args.wheel, spec)
        rendered = _render(payload)
        rendered_digest = hashlib.sha256(rendered).hexdigest()
        if args.check:
            expected_inventory_digest = _require_sha256(
                acceptance.get("memberInventorySha256"),
                "acceptanceState.memberInventorySha256",
            )
            accepted = _read_inventory(args.output)
            accepted_digest = hashlib.sha256(accepted).hexdigest()
            if accepted_digest != expected_inventory_digest:
                raise AuditError(
                    "Accepted inventory SHA-256 differs from acceptanceState"
                )
            if accepted != rendered:
                raise AuditError(
                    "Accepted transformer inventory differs from the exact wheel"
                )
            print(f"verified accepted {args.output} ({rendered_digest})")
            return 0
        wrote = _write_candidate(args.output, rendered)
        action = "wrote" if wrote else "reused identical"
        print(
            f"{action} candidate {args.output} ({rendered_digest}); "
            "review it, then manually set memberInventoryAccepted=true and "
            "memberInventorySha256 to this digest; spec unchanged"
        )
        return 0
    except AuditError as error:
        parser.error(str(error))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
