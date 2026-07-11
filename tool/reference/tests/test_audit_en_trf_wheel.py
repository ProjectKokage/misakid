from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile

from tool.reference import audit_en_trf_wheel as audit


ROOT = Path(__file__).resolve().parents[3]
SPEC_PATH = ROOT / "tool/reference/en_trf_resource_spec.json"
AUDITOR_PATH = ROOT / "tool/reference/audit_en_trf_wheel.py"
MODEL_ROOT = "en_core_web_trf/en_core_web_trf-3.8.0"


def _model_members() -> dict[str, bytes]:
    return {
        # The real wheel also contains distribution-level metadata. It shares
        # the `/meta.json` suffix with the actual serialized pipeline metadata
        # and must not make package-root discovery ambiguous.
        "en_core_web_trf/meta.json": b'{"distribution": "en_core_web_trf"}',
        f"{MODEL_ROOT}/config.cfg": (
            b"[components.transformer]\nfactory = 'transformer'\n"
            b"[components.tagger]\nfactory = 'tagger'\n"
        ),
        f"{MODEL_ROOT}/meta.json": json.dumps(
            {
                "lang": "en",
                "name": "core_web_trf",
                "version": "3.8.0",
                "license": "MIT",
                "components": ["transformer", "tagger"],
            },
            sort_keys=True,
        ).encode("utf-8"),
        f"{MODEL_ROOT}/tokenizer": b"tokenizer",
        f"{MODEL_ROOT}/vocab/lookups.bin": b"lookups",
        f"{MODEL_ROOT}/transformer/model": b"transformer-weights",
        f"{MODEL_ROOT}/tagger/model": b"tagger-weights",
    }


def _wheel(
    members: dict[str, bytes] | None = None,
    *,
    compression: int = zipfile.ZIP_DEFLATED,
) -> io.BytesIO:
    result = io.BytesIO()
    with zipfile.ZipFile(result, "w", compression=compression) as archive:
        for path, data in (members or _model_members()).items():
            archive.writestr(path, data)
    result.seek(0)
    return result


def _spec_for_wheel(
    wheel_bytes: bytes,
    *,
    inventory_accepted: bool = False,
    inventory_sha256: str | None = None,
) -> dict[str, object]:
    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    spec["modelWheel"]["sizeBytes"] = len(wheel_bytes)
    spec["modelWheel"]["sha256"] = hashlib.sha256(wheel_bytes).hexdigest()
    acceptance = spec["acceptanceState"]
    acceptance["memberInventoryAccepted"] = inventory_accepted
    acceptance["memberInventorySha256"] = inventory_sha256
    return spec


def _write_json(path: Path, payload: dict[str, object]) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _run_cli(
    wheel: Path,
    spec: Path,
    output: Path,
    mode: str,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        (
            sys.executable,
            str(AUDITOR_PATH),
            "--wheel",
            str(wheel),
            "--spec",
            str(spec),
            "--output",
            str(output),
            mode,
        ),
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


class TransformerResourceSpecTests(unittest.TestCase):
    def test_spec_pins_artifact_runtime_delta_and_prepared_corpora(self):
        spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        self.assertEqual(spec["schemaVersion"], 1)
        self.assertEqual(
            spec["upstream"]["commit"],
            "fba1236595f2d2bf21d414ba6e57d25256afada3",
        )
        self.assertEqual(spec["modelWheel"]["sizeBytes"], 457_421_864)
        self.assertEqual(
            spec["modelWheel"]["sha256"],
            "272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5",
        )
        self.assertEqual(
            {
                entry["distribution"]: entry["version"]
                for entry in spec["python312RuntimeDelta"]
            },
            {
                "curated-tokenizers": "0.0.9",
                "curated-transformers": "0.1.1",
                "spacy-curated-transformers": "0.3.0",
                "torch": "2.6.0",
            },
        )

        for record in [spec["requirements"], *spec["preparedCorpora"]]:
            path = ROOT / record["path"]
            self.assertEqual(
                hashlib.sha256(path.read_bytes()).hexdigest(), record["sha256"]
            )
        for record in spec["preparedCorpora"]:
            rows = [
                json.loads(line)
                for line in (ROOT / record["path"])
                .read_text(encoding="utf-8")
                .splitlines()
            ]
            self.assertEqual(len(rows), record["caseCount"])
            self.assertTrue(all(row["options"]["trf"] is True for row in rows))

        requirements = (
            ROOT / spec["requirements"]["path"]
        ).read_text(encoding="utf-8")
        for requirement in (
            "curated-tokenizers==0.0.9",
            "curated-transformers==0.1.1",
            "spacy-curated-transformers==0.3.0",
            "torch==2.6.0",
        ):
            self.assertIn(f"\n{requirement}\n", f"\n{requirements}")
        self.assertIn(
            "#sha256=" + spec["modelWheel"]["sha256"], requirements
        )

        self.assertEqual(
            spec["acceptanceState"],
            {
                "wholeWheelIdentityReviewed": True,
                "memberInventoryAccepted": True,
                "memberInventorySha256": (
                    "4e3cae8256e9e701739cdbd720ffe5f3047202e4a0ebace4bc469a33b1ae7eba"
                ),
                "transformerFixturesAccepted": True,
            },
        )
        self.assertEqual(audit._load_spec(SPEC_PATH), spec)

    def test_spec_loader_rejects_an_unpinned_or_malformed_spec(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "spec.json"
            path.write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(audit.AuditError, "fields"):
                audit._load_spec(path)

            original = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
            mutations = {
                "missing upstream": lambda value: value.pop("upstream"),
                "wrong upstream": lambda value: value["upstream"].__setitem__(
                    "commit", "0" * 40
                ),
                "runtime omitted": lambda value: value.__setitem__(
                    "python312RuntimeDelta", []
                ),
                "requirements hash": lambda value: value["requirements"].__setitem__(
                    "sha256", "0" * 64
                ),
                "corpus count": lambda value: value["preparedCorpora"][0].__setitem__(
                    "caseCount", 31
                ),
                "whole wheel unreviewed": lambda value: value[
                    "acceptanceState"
                ].__setitem__("wholeWheelIdentityReviewed", False),
                "digest before acceptance": lambda value: value[
                    "acceptanceState"
                ].update(
                    memberInventoryAccepted=False,
                    memberInventorySha256="0" * 64,
                ),
                "accepted without digest": lambda value: value[
                    "acceptanceState"
                ].update(
                    memberInventoryAccepted=True,
                    memberInventorySha256=None,
                ),
                "unknown field": lambda value: value.__setitem__("unknown", True),
            }
            for name, mutate in mutations.items():
                with self.subTest(name=name):
                    payload = json.loads(json.dumps(original))
                    mutate(payload)
                    _write_json(path, payload)
                    with self.assertRaises(audit.AuditError):
                        audit._load_spec(path)

    def test_spec_loader_hashes_the_repository_local_manifests(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            local_paths = [
                audit.EXPECTED_REQUIREMENTS["path"],
                *(record["path"] for record in audit.EXPECTED_CORPORA),
            ]
            for relative in local_paths:
                source = ROOT / relative
                target = repository / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)

            audit._load_spec(SPEC_PATH, repository)
            requirements = repository / audit.EXPECTED_REQUIREMENTS["path"]
            requirements.write_bytes(requirements.read_bytes() + b"# tampered\n")
            with self.assertRaisesRegex(audit.AuditError, "SHA-256 mismatch"):
                audit._load_spec(SPEC_PATH, repository)


class TransformerWheelInventoryTests(unittest.TestCase):
    def setUp(self):
        spec = audit._load_spec(SPEC_PATH)
        self.suffixes = list(spec["requiredModelMemberSuffixes"])

    def test_inventory_hashes_every_member_and_captures_model_contract(self):
        first = audit._inventory_from_zip(_wheel(), self.suffixes)
        second = audit._inventory_from_zip(_wheel(), self.suffixes)
        self.assertEqual(first, second)
        self.assertEqual(first["entryCount"], 7)
        self.assertEqual(first["modelPackageRoot"], MODEL_ROOT)
        self.assertEqual(
            first["modelMetadata"]["components"], ["transformer", "tagger"]
        )
        self.assertEqual(set(first["requiredMembers"]), set(self.suffixes))
        self.assertEqual(
            [member["path"] for member in first["members"]],
            sorted(member["path"] for member in first["members"]),
        )
        for member in first["members"]:
            self.assertRegex(member["sha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(member["crc32"], r"^[0-9a-f]{8}$")

    def test_rejects_traversal_absolute_backslash_and_drive_paths(self):
        for path in ("../escape", "/absolute", r"back\slash", "C:/drive"):
            with self.subTest(path=path):
                members = _model_members()
                members[path] = b"unsafe"
                with self.assertRaisesRegex(audit.AuditError, "path"):
                    audit._inventory_from_zip(_wheel(members), self.suffixes)

    def test_rejects_duplicate_and_case_colliding_members(self):
        for second_name in (
            f"{MODEL_ROOT}/tokenizer",
            f"{MODEL_ROOT}/TOKENIZER",
        ):
            with self.subTest(second_name=second_name):
                wheel = io.BytesIO()
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    with zipfile.ZipFile(wheel, "w") as archive:
                        for path, data in _model_members().items():
                            archive.writestr(path, data)
                        archive.writestr(second_name, b"collision")
                wheel.seek(0)
                with self.assertRaisesRegex(audit.AuditError, "Duplicate"):
                    audit._inventory_from_zip(wheel, self.suffixes)

    def test_rejects_symbolic_links_and_other_non_regular_entries(self):
        for mode, expected in (
            (stat.S_IFLNK | 0o777, "Symbolic-link"),
            (stat.S_IFIFO | 0o600, "Unsupported archive member type"),
        ):
            with self.subTest(mode=mode):
                wheel = _wheel()
                contents = io.BytesIO()
                with zipfile.ZipFile(contents, "w") as target:
                    with zipfile.ZipFile(wheel) as source:
                        for info in source.infolist():
                            target.writestr(info.filename, source.read(info))
                    special = zipfile.ZipInfo("unsafe-special")
                    special.create_system = 3
                    special.external_attr = mode << 16
                    target.writestr(special, b"target")
                contents.seek(0)
                with self.assertRaisesRegex(audit.AuditError, expected):
                    audit._inventory_from_zip(contents, self.suffixes)

    def test_rejects_unsupported_compression_and_wrong_model_root(self):
        if zipfile.bz2 is not None:
            with self.assertRaisesRegex(audit.AuditError, "compression"):
                audit._inventory_from_zip(
                    _wheel(compression=zipfile.ZIP_BZIP2), self.suffixes
                )
        renamed = {
            path.replace("en_core_web_trf-3.8.0", "en_core_web_trf-3.8.1"): data
            for path, data in _model_members().items()
        }
        with self.assertRaisesRegex(audit.AuditError, "package root"):
            audit._inventory_from_zip(_wheel(renamed), self.suffixes)

    def test_whole_wheel_gate_rejects_before_accepting_any_member_data(self):
        spec = audit._load_spec(SPEC_PATH)
        with tempfile.TemporaryDirectory() as directory:
            wheel = Path(directory) / "model.whl"
            wheel.write_bytes(_wheel().getvalue())
            with self.assertRaisesRegex(audit.AuditError, "size mismatch"):
                audit.audit_wheel(wheel, spec)


class TransformerWheelCliTests(unittest.TestCase):
    def test_candidate_review_transition_and_read_only_check(self):
        wheel_bytes = _wheel().getvalue()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wheel = root / "model.whl"
            spec_path = root / "spec.json"
            inventory = root / "inventory.json"
            wheel.write_bytes(wheel_bytes)
            _write_json(spec_path, _spec_for_wheel(wheel_bytes))

            original_spec = spec_path.read_bytes()
            accepted = _run_cli(wheel, spec_path, inventory, "--accept")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertIn("wrote candidate", accepted.stdout)
            self.assertIn("spec unchanged", accepted.stdout)
            self.assertEqual(spec_path.read_bytes(), original_spec)
            candidate = inventory.read_bytes()
            candidate_digest = hashlib.sha256(candidate).hexdigest()

            reused = _run_cli(wheel, spec_path, inventory, "--accept")
            self.assertEqual(reused.returncode, 0, reused.stderr)
            self.assertIn("reused identical candidate", reused.stdout)
            self.assertEqual(inventory.read_bytes(), candidate)

            premature_check = _run_cli(
                wheel, spec_path, inventory, "--check"
            )
            self.assertEqual(premature_check.returncode, 2)
            self.assertIn("No member inventory is accepted", premature_check.stderr)
            self.assertEqual(spec_path.read_bytes(), original_spec)
            self.assertEqual(inventory.read_bytes(), candidate)

            transitioned = json.loads(spec_path.read_text(encoding="utf-8"))
            transitioned["acceptanceState"]["memberInventoryAccepted"] = True
            transitioned["acceptanceState"][
                "memberInventorySha256"
            ] = candidate_digest
            _write_json(spec_path, transitioned)
            reviewed_spec = spec_path.read_bytes()

            checked = _run_cli(wheel, spec_path, inventory, "--check")
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertIn("verified accepted", checked.stdout)
            self.assertEqual(spec_path.read_bytes(), reviewed_spec)
            self.assertEqual(inventory.read_bytes(), candidate)

            replacement = _run_cli(wheel, spec_path, inventory, "--accept")
            self.assertEqual(replacement.returncode, 2)
            self.assertIn("already accepted", replacement.stderr)
            self.assertEqual(spec_path.read_bytes(), reviewed_spec)
            self.assertEqual(inventory.read_bytes(), candidate)

    def test_same_size_hash_mismatch_is_rejected_before_output(self):
        wheel_bytes = _wheel().getvalue()
        tampered = bytearray(wheel_bytes)
        tampered[len(tampered) // 2] ^= 1
        self.assertEqual(len(tampered), len(wheel_bytes))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wheel = root / "model.whl"
            spec_path = root / "spec.json"
            inventory = root / "inventory.json"
            wheel.write_bytes(tampered)
            _write_json(spec_path, _spec_for_wheel(wheel_bytes))
            spec_before = spec_path.read_bytes()

            result = _run_cli(wheel, spec_path, inventory, "--accept")
            self.assertEqual(result.returncode, 2)
            self.assertIn("SHA-256 mismatch", result.stderr)
            self.assertFalse(inventory.exists())
            self.assertEqual(spec_path.read_bytes(), spec_before)

    def test_missing_wheel_never_mutates_spec_or_inventory(self):
        wheel_bytes = _wheel().getvalue()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            missing_wheel = root / "missing.whl"
            spec_path = root / "spec.json"
            inventory = root / "inventory.json"
            inventory.write_bytes(b"accepted inventory sentinel\n")
            inventory_digest = hashlib.sha256(inventory.read_bytes()).hexdigest()
            _write_json(
                spec_path,
                _spec_for_wheel(
                    wheel_bytes,
                    inventory_accepted=True,
                    inventory_sha256=inventory_digest,
                ),
            )
            spec_before = spec_path.read_bytes()
            inventory_before = inventory.read_bytes()

            result = _run_cli(
                missing_wheel, spec_path, inventory, "--check"
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("Could not read transformer wheel", result.stderr)
            self.assertEqual(spec_path.read_bytes(), spec_before)
            self.assertEqual(inventory.read_bytes(), inventory_before)

    def test_check_rejects_an_inventory_not_bound_by_the_reviewed_digest(self):
        wheel_bytes = _wheel().getvalue()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wheel = root / "model.whl"
            spec_path = root / "spec.json"
            inventory = root / "inventory.json"
            wheel.write_bytes(wheel_bytes)
            _write_json(spec_path, _spec_for_wheel(wheel_bytes))
            accepted = _run_cli(wheel, spec_path, inventory, "--accept")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            transitioned = _spec_for_wheel(
                wheel_bytes,
                inventory_accepted=True,
                inventory_sha256="0" * 64,
            )
            _write_json(spec_path, transitioned)
            inventory_before = inventory.read_bytes()
            spec_before = spec_path.read_bytes()

            checked = _run_cli(wheel, spec_path, inventory, "--check")
            self.assertEqual(checked.returncode, 2)
            self.assertIn("differs from acceptanceState", checked.stderr)
            self.assertEqual(spec_path.read_bytes(), spec_before)
            self.assertEqual(inventory.read_bytes(), inventory_before)


if __name__ == "__main__":
    unittest.main()
