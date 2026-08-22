"""Promote a qualified candidate after real Fonix parity to immutable V1."""

from __future__ import annotations

import argparse
import json
import shutil
import tempfile
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from .constants import (
    ARCHITECTURE,
    MAXIMUM_PHONE_ERROR_RATE,
    MAXIMUM_PROMOTED_MODEL_BYTES,
    MAXIMUM_WARM_P95_MICROSECONDS,
    MINIMUM_WORD_ACCURACY,
    MODEL_FILE,
)
from .pipeline import _sha256, _validate_output, _write_json

_MANIFEST_FILE = "model-manifest.json"
_REPORT_FILE = "training-report.json"
_PARITY_FILE = "parity.json"
_RECEIPT_FILE = "fonix-parity-receipt.json"


def promote_candidate(
    *,
    repo_root: Path,
    candidate: Path,
    fonix_receipt: Path,
    output: Path,
) -> Path:
    """Copy exact candidate bytes and mint V1 only after every gate passes."""

    repo_root = repo_root.resolve(strict=True)
    candidate = candidate.resolve(strict=True)
    fonix_receipt = fonix_receipt.resolve(strict=True)
    output = _validate_output(repo_root, output)
    if not candidate.is_dir():
        raise ValueError("candidate must be a directory.")

    model_path = _regular_file(candidate / MODEL_FILE)
    manifest_path = _regular_file(candidate / _MANIFEST_FILE)
    report_path = _regular_file(candidate / _REPORT_FILE)
    parity_path = _regular_file(candidate / _PARITY_FILE)
    receipt_path = _regular_file(fonix_receipt)

    manifest = _read_object(manifest_path)
    report = _read_object(report_path)
    parity = _read_object(parity_path)
    receipt = _read_object(receipt_path)
    model_sha256 = _sha256(model_path)
    manifest_sha256 = _sha256(manifest_path)
    parity_sha256 = _sha256(parity_path)

    _verify_candidate(
        manifest=manifest,
        report=report,
        parity=parity,
        model_sha256=model_sha256,
        model_size=model_path.stat().st_size,
    )
    _verify_receipt(
        receipt,
        model_sha256=model_sha256,
        manifest_sha256=manifest_sha256,
        parity_sha256=parity_sha256,
    )

    version = f"v1-{model_sha256[:12]}"
    promoted_manifest = dict(manifest)
    promoted_manifest["version"] = version
    promoted_report = dict(report)
    promoted_report["version"] = version
    promoted_report["candidateAccepted"] = True
    promotion_contract = _object(
        promoted_report.get("promotionContract"),
        "training-report promotionContract",
    )
    promotion_contract["passed"] = True
    promoted_report["promotionContract"] = promotion_contract
    promoted_report["promotion"] = {
        "version": version,
        "candidateManifestSha256": manifest_sha256,
        "fonixParityReceipt": {
            "file": _RECEIPT_FILE,
            "sha256": _sha256(receipt_path),
        },
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent)
    )
    try:
        shutil.copyfile(model_path, staging / MODEL_FILE)
        shutil.copyfile(parity_path, staging / _PARITY_FILE)
        shutil.copyfile(receipt_path, staging / _RECEIPT_FILE)
        _write_json(staging / _MANIFEST_FILE, promoted_manifest)
        _write_json(staging / _REPORT_FILE, promoted_report)
        if _sha256(staging / MODEL_FILE) != model_sha256:
            raise RuntimeError("The promoted model bytes changed during copying.")
        staging.rename(output)
    except BaseException:
        shutil.rmtree(staging)
        raise
    return output


def main(arguments: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Promote a qualified en-US G2P candidate to immutable V1.",
    )
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--fonix-receipt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parsed = parser.parse_args(arguments)
    output = promote_candidate(
        repo_root=parsed.repo_root,
        candidate=parsed.candidate,
        fonix_receipt=parsed.fonix_receipt,
        output=parsed.output,
    )
    print(json.dumps({"output": str(output)}, sort_keys=True))
    return 0


def _verify_candidate(
    *,
    manifest: dict[str, Any],
    report: dict[str, Any],
    parity: dict[str, Any],
    model_sha256: str,
    model_size: int,
) -> None:
    version = manifest.get("version")
    if (
        manifest.get("schemaVersion") != 1
        or manifest.get("modelId") != "misakid-en-us-g2p"
        or manifest.get("architecture") != ARCHITECTURE
        or not isinstance(version, str)
        or version != f"candidate-{model_sha256[:12]}"
    ):
        raise ValueError("The candidate manifest identity is invalid.")
    model = _object(manifest.get("model"), "candidate manifest model")
    if model.get("sha256") != model_sha256 or model.get("sizeBytes") != model_size:
        raise ValueError("The candidate model identity is invalid.")
    if (
        report.get("schemaVersion") != 1
        or report.get("modelId") != "misakid-en-us-g2p"
        or report.get("version") != version
        or report.get("trainingGatesPassed") is not True
        or report.get("candidateAccepted") is not False
    ):
        raise ValueError("The candidate training report is not promotable.")
    contract = _object(
        report.get("promotionContract"),
        "candidate promotionContract",
    )
    if (
        contract.get("trainingGatesPassed") is not True
        or contract.get("fonixParityRequiredForV1") is not True
        or contract.get("passed") is not False
        or contract.get("minimumWordAccuracy") != MINIMUM_WORD_ACCURACY
        or contract.get("maximumPhoneErrorRate") != MAXIMUM_PHONE_ERROR_RATE
        or contract.get("maximumModelSizeBytes") != MAXIMUM_PROMOTED_MODEL_BYTES
        or contract.get("maximumWarmP95Microseconds") != MAXIMUM_WARM_P95_MICROSECONDS
    ):
        raise ValueError("The candidate promotion contract is invalid.")
    held_out = _object(contract.get("heldOutTest"), "held-out test metrics")
    performance = _object(contract.get("performance"), "performance evidence")
    warm_inference = _object(
        performance.get("warmInferenceMicroseconds"),
        "warm inference evidence",
    )
    if (
        _number(held_out.get("wordAccuracy"), "wordAccuracy") < MINIMUM_WORD_ACCURACY
        or _number(held_out.get("phoneErrorRate"), "phoneErrorRate")
        > MAXIMUM_PHONE_ERROR_RATE
        or _integer(warm_inference.get("p95"), "warm p95")
        > MAXIMUM_WARM_P95_MICROSECONDS
        or model_size > MAXIMUM_PROMOTED_MODEL_BYTES
    ):
        raise ValueError("The candidate measurements do not pass promotion gates.")
    artifact = _object(report.get("artifact"), "candidate artifact")
    if (
        artifact.get("sha256") != model_sha256
        or artifact.get("sizeBytes") != model_size
    ):
        raise ValueError("The candidate report artifact identity is invalid.")
    if (
        parity.get("schemaVersion") != 1
        or parity.get("decodedParity") is not True
        or parity.get("modelSha256") != model_sha256
        or parity.get("maximumCases") != 32
        or not isinstance(parity.get("cases"), list)
        or len(parity["cases"]) != 32
    ):
        raise ValueError("The candidate Torch/ONNX parity evidence is invalid.")


def _verify_receipt(
    receipt: dict[str, Any],
    *,
    model_sha256: str,
    manifest_sha256: str,
    parity_sha256: str,
) -> None:
    if (
        receipt.get("schemaVersion") != 1
        or receipt.get("kind") != "misakid-fonix-en-parity"
        or receipt.get("passed") is not True
        or receipt.get("architecture") != ARCHITECTURE
        or receipt.get("modelId") != "misakid-en-us-g2p"
        or receipt.get("candidateVersion") != f"candidate-{model_sha256[:12]}"
        or receipt.get("modelSha256") != model_sha256
        or receipt.get("candidateManifestSha256") != manifest_sha256
        or receipt.get("paritySha256") != parity_sha256
        or receipt.get("cases") != 32
    ):
        raise ValueError("The Fonix parity receipt does not match the candidate.")


def _regular_file(path: Path) -> Path:
    if not path.is_file():
        raise ValueError(f"Required regular file is missing: {path.name}.")
    return path


def _read_object(path: Path) -> dict[str, Any]:
    decoded = json.loads(path.read_bytes())
    return _object(decoded, path.name)


def _object(value: object, location: str) -> dict[str, Any]:
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise ValueError(f"{location} must be a JSON object.")
    return value


def _number(value: object, location: str) -> float:
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise ValueError(f"{location} must be numeric.")
    return float(value)


def _integer(value: object, location: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{location} must be an integer.")
    return value


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


if __name__ == "__main__":
    raise SystemExit(main())
