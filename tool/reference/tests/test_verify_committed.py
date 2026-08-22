import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from tool.reference import verify_committed


def _jsonl_record(value):
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ) + "\n"


def _write_valid_manifest_tree(
    root,
    *,
    language="en",
    mode="american-no-fallback",
    python_key=None,
    options=None,
):
    input_path = root / "tool/reference/cases/example.jsonl"
    expected_path = (
        root
        / "test/fixtures/upstream"
        / verify_committed.UPSTREAM_COMMIT
        / "example.jsonl"
    )
    input_path.parent.mkdir(parents=True)
    expected_path.parent.mkdir(parents=True)
    case = {
        "caseId": "example",
        "input": "hello",
        "language": language,
        "mode": mode,
        "options": options or {"version": None},
    }
    expected = {
        **case,
        "backendVersions": {},
        "phonemes": "həlˈO",
        "schemaVersion": 1,
        "tokens": [],
        "upstreamCommit": verify_committed.UPSTREAM_COMMIT,
        "upstreamRepository": verify_committed.UPSTREAM_REPOSITORY,
        "upstreamVersion": verify_committed.UPSTREAM_VERSION,
    }
    input_path.write_text(_jsonl_record(case), encoding="utf-8")
    expected_path.write_text(_jsonl_record(expected), encoding="utf-8")
    provenance_path = expected_path.with_suffix(".provenance.json")
    provenance = {
        "caseCorpus": input_path.relative_to(root).as_posix(),
        "caseCount": 1,
        "fixture": expected_path.name,
        "schemaVersion": 1,
        "upstreamCommit": verify_committed.UPSTREAM_COMMIT,
        "upstreamRepository": verify_committed.UPSTREAM_REPOSITORY,
        "upstreamVersion": verify_committed.UPSTREAM_VERSION,
    }
    provenance_path.write_text(
        json.dumps(provenance, sort_keys=True),
        encoding="utf-8",
    )
    manifest_path = root / "manifest.json"
    manifest = {
        "fixtures": [
            {
                "caseCount": 1,
                "expected": expected_path.relative_to(root).as_posix(),
                "input": input_path.relative_to(root).as_posix(),
                "language": language,
                "pythonKey": python_key or language,
            }
        ],
        "schemaVersion": 1,
        "upstreamCommit": verify_committed.UPSTREAM_COMMIT,
    }
    manifest_path.write_text(
        json.dumps(manifest, sort_keys=True),
        encoding="utf-8",
    )
    return (
        manifest_path,
        input_path,
        expected_path,
        provenance_path,
        case,
        provenance,
    )


class AcceptedManifestTests(unittest.TestCase):
    def test_committed_manifest_is_complete_and_counts_exact_records(self):
        repo = Path.cwd()
        specs = verify_committed.load_manifest(
            repo / "tool/reference/accepted_fixtures.json", repo
        )

        self.assertEqual(len(specs), 17)
        self.assertEqual(sum(spec.case_count for spec in specs), 431)
        self.assertEqual(
            {spec.language for spec in specs}, {"en", "ja", "ko", "zh"}
        )
        self.assertEqual(
            len({spec.expected_path for spec in specs}), len(specs)
        )
        fixture_directory = (
            repo
            / "test/fixtures/upstream"
            / verify_committed.UPSTREAM_COMMIT
        )
        self.assertEqual(
            {spec.expected_path for spec in specs},
            set(fixture_directory.glob("*.jsonl")),
        )
        chinese = next(
            spec
            for spec in specs
            if spec.expected_path.name == "zh_legacy.jsonl"
        )
        self.assertEqual(chinese.python_key, "zh")
        self.assertEqual(chinese.case_count, 24)
        self.assertEqual(chinese.input_path.name, "zh_legacy.jsonl")
        self.assertEqual(chinese.expected_path.name, "zh_legacy.jsonl")
        combined = next(
            spec
            for spec in specs
            if spec.expected_path.name
            == "zh_frontend_1_1_en_small_no_fallback.jsonl"
        )
        self.assertEqual(combined.python_key, "zh-en")
        self.assertEqual(combined.case_count, 14)
        transformer = [
            spec
            for spec in specs
            if spec.expected_path.name.endswith("_trf_no_fallback.jsonl")
        ]
        self.assertEqual(len(transformer), 2)
        self.assertTrue(
            all(spec.python_key == "en-trf" for spec in transformer)
        )
        transformer_espeak = [
            spec
            for spec in specs
            if spec.expected_path.name.endswith("_trf_espeak_fallback.jsonl")
        ]
        self.assertEqual(len(transformer_espeak), 2)
        self.assertTrue(
            all(
                spec.python_key == "en-trf-espeak"
                for spec in transformer_espeak
            )
        )

    def test_transformer_manifest_uses_a_distinct_locked_interpreter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                python_key="en-trf",
                options={"trf": True, "version": None},
            )
            specs = verify_committed.load_manifest(manifest, root)
            self.assertEqual(specs[0].python_key, "en-trf")

            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["fixtures"][0]["pythonKey"] = "en"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "pythonKey must be 'en-trf'",
            ):
                verify_committed.load_manifest(manifest, root)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                mode="american-espeak-fallback",
                python_key="en-trf-espeak",
                options={"trf": True, "version": None},
            )
            specs = verify_committed.load_manifest(manifest, root)
            self.assertEqual(specs[0].python_key, "en-trf-espeak")

            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["fixtures"][0]["pythonKey"] = "en-trf"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "pythonKey must be 'en-trf-espeak'",
            ):
                verify_committed.load_manifest(manifest, root)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                python_key="en-trf",
            )
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "pythonKey must be 'en'",
            ):
                verify_committed.load_manifest(manifest, root)

    def test_manifest_rejects_path_escape_and_count_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            input_path = root / "tool/reference/cases/input.jsonl"
            expected_path = (
                root
                / "test/fixtures/upstream"
                / verify_committed.UPSTREAM_COMMIT
                / "expected.jsonl"
            )
            input_path.parent.mkdir(parents=True)
            expected_path.parent.mkdir(parents=True)
            input_path.write_text("{}\n", encoding="utf-8")
            expected_path.write_text("{}\n", encoding="utf-8")
            manifest = root / "manifest.json"
            record = {
                "caseCount": 2,
                "expected": str(expected_path.relative_to(root)),
                "input": str(input_path.relative_to(root)),
                "language": "en",
                "pythonKey": "en",
            }
            manifest.write_text(
                json.dumps(
                    {
                        "fixtures": [record],
                        "schemaVersion": 1,
                        "upstreamCommit": verify_committed.UPSTREAM_COMMIT,
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                verify_committed.ManifestError, "fixture has 1 records"
            ):
                verify_committed.load_manifest(manifest, root)

            record["caseCount"] = 1
            record["input"] = "../outside.jsonl"
            manifest.write_text(
                json.dumps(
                    {
                        "fixtures": [record],
                        "schemaVersion": 1,
                        "upstreamCommit": verify_committed.UPSTREAM_COMMIT,
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                verify_committed.ManifestError, "escapes the repository"
            ):
                verify_committed.load_manifest(manifest, root)

    def test_cutlet_manifest_uses_a_distinct_locked_interpreter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                language="ja",
                mode="cutlet",
                python_key="ja-cutlet",
            )
            specs = verify_committed.load_manifest(manifest, root)
            self.assertEqual(specs[0].python_key, "ja-cutlet")

            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["fixtures"][0]["pythonKey"] = "ja"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "pythonKey must be 'ja-cutlet'",
            ):
                verify_committed.load_manifest(manifest, root)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                language="ja",
                mode="pyopenjtalk",
                python_key="ja-cutlet",
            )
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "pythonKey must be 'ja'",
            ):
                verify_committed.load_manifest(manifest, root)

    def test_chinese_callback_manifest_uses_combined_locked_interpreter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                language="zh",
                mode="frontend-1.1-en-small-no-fallback",
                python_key="zh-en",
            )
            specs = verify_committed.load_manifest(manifest, root)
            self.assertEqual(specs[0].python_key, "zh-en")

            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["fixtures"][0]["pythonKey"] = "zh"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "pythonKey must be 'zh-en'",
            ):
                verify_committed.load_manifest(manifest, root)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                language="zh",
                mode="frontend-1.1",
                python_key="zh-en",
            )
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "pythonKey must be 'zh'",
            ):
                verify_committed.load_manifest(manifest, root)

    def test_manifest_rejects_corpus_count_and_identity_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, input_path, _, _, case, _ = _write_valid_manifest_tree(
                root
            )
            self.assertEqual(
                len(verify_committed.load_manifest(manifest, root)),
                1,
            )

            changed = {**case, "input": "changed"}
            input_path.write_text(_jsonl_record(changed), encoding="utf-8")
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "differ at field 'input'",
            ):
                verify_committed.load_manifest(manifest, root)

            input_path.write_text(
                _jsonl_record(case) + _jsonl_record(case),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "corpus has 2 records",
            ):
                verify_committed.load_manifest(manifest, root)

            input_path.write_text(
                _jsonl_record(case) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "blank records are forbidden",
            ):
                verify_committed.load_manifest(manifest, root)

    def test_manifest_rejects_provenance_and_coverage_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (
                manifest,
                _,
                expected_path,
                provenance_path,
                _,
                provenance,
            ) = _write_valid_manifest_tree(root)

            extra_fixture = expected_path.with_name("unlisted.jsonl")
            extra_fixture.write_text("{}\n", encoding="utf-8")
            with self.assertRaisesRegex(
                verify_committed.ManifestError,
                "unlisted fixtures: unlisted.jsonl",
            ):
                verify_committed.load_manifest(manifest, root)


class VerificationRunnerTests(unittest.TestCase):
    def test_parser_exposes_distinct_specialized_interpreter_options(self):
        parser = verify_committed._parser(Path.cwd())
        args = parser.parse_args(
            [
                "--python-ja",
                "/ja/python",
                "--python-en-trf",
                "/en-trf/python",
                "--python-en-trf-espeak",
                "/en-trf-espeak/python",
                "--python-ja-cutlet",
                "/cutlet/python",
                "--python-zh-en",
                "/zh-en/python",
            ]
        )

        self.assertEqual(args.python_ja, "/ja/python")
        self.assertEqual(args.python_en_trf, "/en-trf/python")
        self.assertEqual(args.python_en_trf_espeak, "/en-trf-espeak/python")
        self.assertEqual(args.python_ja_cutlet, "/cutlet/python")
        self.assertEqual(args.python_zh_en, "/zh-en/python")

        with mock.patch.dict(
            verify_committed.os.environ,
            {
                "MISAKI_ORACLE_JA_CUTLET_PYTHON": "/cutlet/from-env",
                "MISAKI_ORACLE_EN_TRF_PYTHON": "/en-trf/from-env",
                "MISAKI_ORACLE_EN_TRF_ESPEAK_PYTHON": "/en-trf-espeak/from-env",
                "MISAKI_ORACLE_ZH_EN_PYTHON": "/zh-en/from-env",
            },
        ):
            environment_args = verify_committed._parser(Path.cwd()).parse_args([])
        self.assertEqual(
            environment_args.python_ja_cutlet,
            "/cutlet/from-env",
        )
        self.assertEqual(environment_args.python_en_trf, "/en-trf/from-env")
        self.assertEqual(
            environment_args.python_en_trf_espeak,
            "/en-trf-espeak/from-env",
        )
        self.assertEqual(environment_args.python_zh_en, "/zh-en/from-env")

    def test_command_is_argument_vector_and_verifier_is_read_only(self):
        repo = Path.cwd()
        spec = verify_committed.load_manifest(
            repo / "tool/reference/accepted_fixtures.json", repo
        )[0]
        runner = mock.Mock(
            return_value=subprocess.CompletedProcess([], returncode=0)
        )

        with contextlib.redirect_stdout(io.StringIO()):
            result = verify_committed.verify_all(
                [spec],
                interpreters={
                    "en": "/locked/python",
                    "en-trf": "/locked/transformer-python",
                },
                exporter=repo / "tool/reference/export_fixtures.py",
                upstream_root=Path("/pinned/upstream"),
                repo_root=repo,
                verbose_errors=True,
                runner=runner,
            )

        self.assertEqual(result, 0)
        command = runner.call_args.args[0]
        self.assertEqual(command[0], "/locked/python")
        self.assertIn("verify", command)
        self.assertNotIn("regenerate", command)
        self.assertNotIn("--accept", command)
        self.assertIn("--verbose-errors", command)
        self.assertEqual(runner.call_args.kwargs["env"]["PYTHONHASHSEED"], "0")
        self.assertFalse(runner.call_args.kwargs["check"])

    def test_cutlet_fixture_dispatches_to_cutlet_interpreter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, *_ = _write_valid_manifest_tree(
                root,
                language="ja",
                mode="cutlet",
                python_key="ja-cutlet",
            )
            spec = verify_committed.load_manifest(manifest, root)[0]
            runner = mock.Mock(
                return_value=subprocess.CompletedProcess([], returncode=0)
            )

            with contextlib.redirect_stdout(io.StringIO()):
                result = verify_committed.verify_all(
                    [spec],
                    interpreters={"ja-cutlet": "/cutlet/python"},
                    exporter=root / "tool/reference/export_fixtures.py",
                    upstream_root=Path("/pinned/upstream"),
                    repo_root=root,
                    verbose_errors=False,
                    runner=runner,
                )

            self.assertEqual(result, 0)
            self.assertEqual(runner.call_args.args[0][0], "/cutlet/python")

    def test_chinese_callback_dispatches_to_combined_interpreter(self):
        repo = Path.cwd()
        spec = next(
            spec
            for spec in verify_committed.load_manifest(
                repo / "tool/reference/accepted_fixtures.json", repo
            )
            if spec.python_key == "zh-en"
        )
        runner = mock.Mock(
            return_value=subprocess.CompletedProcess([], returncode=0)
        )

        with contextlib.redirect_stdout(io.StringIO()):
            result = verify_committed.verify_all(
                [spec],
                interpreters={"zh-en": "/combined/python"},
                exporter=repo / "tool/reference/export_fixtures.py",
                upstream_root=Path("/pinned/upstream"),
                repo_root=repo,
                verbose_errors=False,
                runner=runner,
            )

        self.assertEqual(result, 0)
        self.assertEqual(runner.call_args.args[0][0], "/combined/python")

    def test_transformer_espeak_dispatches_to_combined_interpreter(self):
        repo = Path.cwd()
        spec = next(
            spec
            for spec in verify_committed.load_manifest(
                repo / "tool/reference/accepted_fixtures.json", repo
            )
            if spec.python_key == "en-trf-espeak"
        )
        runner = mock.Mock(
            return_value=subprocess.CompletedProcess([], returncode=0)
        )

        with contextlib.redirect_stdout(io.StringIO()):
            result = verify_committed.verify_all(
                [spec],
                interpreters={
                    "en-trf-espeak": "/transformer-espeak/python"
                },
                exporter=repo / "tool/reference/export_fixtures.py",
                upstream_root=Path("/pinned/upstream"),
                repo_root=repo,
                verbose_errors=False,
                runner=runner,
            )

        self.assertEqual(result, 0)
        self.assertEqual(
            runner.call_args.args[0][0], "/transformer-espeak/python"
        )

    def test_failure_is_aggregated_without_skipping_later_fixtures(self):
        repo = Path.cwd()
        specs = verify_committed.load_manifest(
            repo / "tool/reference/accepted_fixtures.json", repo
        )[:2]
        runner = mock.Mock(
            side_effect=[
                subprocess.CompletedProcess([], returncode=1),
                subprocess.CompletedProcess([], returncode=0),
            ]
        )

        with contextlib.redirect_stderr(io.StringIO()):
            result = verify_committed.verify_all(
                specs,
                interpreters={
                    "en": "/locked/python",
                    "en-trf": "/locked/transformer-python",
                },
                exporter=repo / "tool/reference/export_fixtures.py",
                upstream_root=Path("/pinned/upstream"),
                repo_root=repo,
                verbose_errors=False,
                runner=runner,
            )

        self.assertEqual(result, 1)
        self.assertEqual(runner.call_count, 2)


if __name__ == "__main__":
    unittest.main()
