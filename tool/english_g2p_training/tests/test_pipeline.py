import hashlib
import json
from pathlib import Path

import pytest

from misakid_g2p_training.constants import ARCHITECTURE
from misakid_g2p_training.data import Example
from misakid_g2p_training.pipeline import _length_grouped_indices, _nearest_rank
from misakid_g2p_training.promotion import promote_candidate


def test_length_grouped_batches_never_add_right_padding() -> None:
    examples = (
        Example("a", "a"),
        Example("four", "f"),
        Example("to", "t"),
        Example("b", "b"),
        Example("sixsix", "s"),
        Example("go", "g"),
    )

    batches = list(_length_grouped_indices(examples, batch_size=2, shuffle_seed=23))

    assert sorted(index for batch in batches for index in batch) == list(
        range(len(examples))
    )
    assert all(
        len({len(examples[index].word) for index in batch}) == 1 for batch in batches
    )
    assert batches == list(
        _length_grouped_indices(examples, batch_size=2, shuffle_seed=23)
    )


def test_nearest_rank_uses_an_observed_duration() -> None:
    values = list(range(1, 101))

    assert _nearest_rank(values, 0.50) == 50
    assert _nearest_rank(values, 0.95) == 95
    assert _nearest_rank(values, 0.99) == 99


def test_promotion_requires_matching_fonix_receipt(tmp_path: Path) -> None:
    candidate = tmp_path / "candidate"
    candidate.mkdir()
    model = b"qualified-model"
    model_sha256 = hashlib.sha256(model).hexdigest()
    version = f"candidate-{model_sha256[:12]}"
    (candidate / "model.onnx").write_bytes(model)
    _write_json(
        candidate / "model-manifest.json",
        {
            "schemaVersion": 1,
            "modelId": "misakid-en-us-g2p",
            "architecture": ARCHITECTURE,
            "version": version,
            "model": {"sha256": model_sha256, "sizeBytes": len(model)},
        },
    )
    _write_json(
        candidate / "training-report.json",
        {
            "schemaVersion": 1,
            "modelId": "misakid-en-us-g2p",
            "version": version,
            "candidateAccepted": False,
            "trainingGatesPassed": True,
            "promotionContract": {
                "trainingGatesPassed": True,
                "fonixParityRequiredForV1": True,
                "minimumWordAccuracy": 0.67,
                "maximumPhoneErrorRate": 0.07,
                "maximumModelSizeBytes": 6 * 1024 * 1024,
                "maximumWarmP95Microseconds": 2_000,
                "heldOutTest": {
                    "wordAccuracy": 0.71,
                    "phoneErrorRate": 0.05,
                },
                "performance": {"warmInferenceMicroseconds": {"p95": 900}},
                "passed": False,
            },
            "artifact": {"sha256": model_sha256, "sizeBytes": len(model)},
        },
    )
    _write_json(
        candidate / "parity.json",
        {
            "schemaVersion": 1,
            "decodedParity": True,
            "modelSha256": model_sha256,
            "maximumCases": 32,
            "cases": [{} for _ in range(32)],
        },
    )
    manifest_sha256 = _digest(candidate / "model-manifest.json")
    parity_sha256 = _digest(candidate / "parity.json")
    receipt = tmp_path / "receipt.json"
    _write_json(
        receipt,
        {
            "schemaVersion": 1,
            "kind": "misakid-fonix-en-parity",
            "passed": True,
            "architecture": ARCHITECTURE,
            "modelId": "misakid-en-us-g2p",
            "candidateVersion": version,
            "modelSha256": model_sha256,
            "candidateManifestSha256": manifest_sha256,
            "paritySha256": parity_sha256,
            "cases": 32,
        },
    )

    output = promote_candidate(
        repo_root=Path(__file__).resolve().parents[3],
        candidate=candidate,
        fonix_receipt=receipt,
        output=tmp_path / "v1",
    )

    promoted_manifest = json.loads((output / "model-manifest.json").read_bytes())
    promoted_report = json.loads((output / "training-report.json").read_bytes())
    assert promoted_manifest["version"] == f"v1-{model_sha256[:12]}"
    assert promoted_report["candidateAccepted"] is True
    assert promoted_report["promotionContract"]["passed"] is True
    assert (output / "model.onnx").read_bytes() == model

    mismatched = json.loads(receipt.read_bytes())
    mismatched["modelSha256"] = "0" * 64
    _write_json(tmp_path / "mismatched.json", mismatched)
    with pytest.raises(ValueError, match="does not match"):
        promote_candidate(
            repo_root=Path(__file__).resolve().parents[3],
            candidate=candidate,
            fonix_receipt=tmp_path / "mismatched.json",
            output=tmp_path / "rejected-v1",
        )


def _write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, sort_keys=True) + "\n", encoding="utf-8")


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
