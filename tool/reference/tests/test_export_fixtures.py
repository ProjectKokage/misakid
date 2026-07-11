from dataclasses import dataclass
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

from tool.reference import export_fixtures as reference


@dataclass
class FakeToken:
    text: str
    tag: str
    whitespace: str
    phonemes: str
    start_ts: float
    end_ts: float
    _: object


def make_case(**overrides):
    values = {
        "language": "ja",
        "mode": "ja-num2kana",
        "options": {"dictionary": "hiragana"},
        "input_text": "300",
        "case_id": "case-1",
        "seed": None,
    }
    values.update(overrides)
    return reference.FixtureCase(**values)


class SerializationTests(unittest.TestCase):
    def test_serializes_all_dataclass_metadata_and_dynamic_fields(self):
        token = FakeToken(
            text="café",
            tag="NN",
            whitespace=" ",
            phonemes="kafˈA",
            start_ts=1.25,
            end_ts=2.5,
            _={"rating": 4, "moras": ["カ", "フェ"], "flags": {"b", "a"}},
        )
        token.rating = 3

        serialized = reference.serialize_token(token)

        self.assertEqual(serialized["text"], "café")
        self.assertEqual(serialized["_"]["rating"], 4)
        self.assertEqual(serialized["_"]["flags"], ["a", "b"])
        self.assertEqual(serialized["rating"], 3)
        self.assertIn("start_ts", serialized)
        self.assertIn("end_ts", serialized)

    def test_json_line_is_sorted_utf8_and_compact(self):
        line = reference.canonical_json_line({"z": "❓", "a": 1})
        self.assertEqual(line, '{"a":1,"z":"❓"}\n')

    def test_non_finite_float_is_rejected(self):
        with self.assertRaises(reference.SerializationFailure):
            reference.canonicalize(float("nan"))

    def test_resource_tree_fingerprint_is_path_stable_and_byte_exact(self):
        with tempfile.TemporaryDirectory() as first_name:
            with tempfile.TemporaryDirectory() as second_name:
                first = Path(first_name)
                second = Path(second_name)
                for root in (first, second):
                    (root / "nested").mkdir()
                    (root / "nested" / "b.bin").write_bytes(b"two")
                    (root / "a.bin").write_bytes(b"one")

                first_fingerprint = reference._directory_tree_fingerprint(
                    str(first)
                )
                second_fingerprint = reference._directory_tree_fingerprint(
                    str(second)
                )
                self.assertEqual(first_fingerprint, second_fingerprint)
                self.assertEqual(first_fingerprint[1:], (2, 6))

                (second / "a.bin").write_bytes(b"changed")
                reference._directory_tree_fingerprint.cache_clear()
                self.assertNotEqual(
                    first_fingerprint,
                    reference._directory_tree_fingerprint(str(second)),
                )


class RecordTests(unittest.TestCase):
    def test_success_preserves_null_tokens(self):
        record = reference.build_fixture_record(
            make_case(),
            lambda _case: ("さんびゃく", None),
            version_provider=lambda _case: {},
        )

        self.assertEqual(record["phonemes"], "さんびゃく")
        self.assertIsNone(record["tokens"])
        self.assertEqual(record["upstreamCommit"], reference.UPSTREAM_COMMIT)
        self.assertNotIn("error", record)

    def test_empty_token_list_remains_distinct_from_null(self):
        record = reference.build_fixture_record(
            make_case(),
            lambda _case: ("", []),
            version_provider=lambda _case: {},
        )
        self.assertEqual(record["tokens"], [])

    def test_backend_failure_uses_stable_category_without_traceback(self):
        def fail(_case):
            raise ModuleNotFoundError("environment-specific path /tmp/example")

        record = reference.build_fixture_record(
            make_case(), fail, version_provider=lambda _case: {}
        )

        self.assertEqual(record["error"], {"category": "backendUnavailable"})
        self.assertIsNone(record["phonemes"])
        self.assertNotIn("traceback", record)
        self.assertNotIn("message", record["error"])

    def test_explicit_tool_error_keeps_its_category(self):
        def fail(_case):
            raise reference.UnsupportedMode("test")

        record = reference.build_fixture_record(
            make_case(), fail, version_provider=lambda _case: {}
        )
        self.assertEqual(record["error"], {"category": "unsupportedMode"})

    def test_auxiliary_backend_input_is_preserved(self):
        backend_input = {
            "kind": "example.words",
            "schemaVersion": 1,
            "words": [{"text": "東京"}],
        }
        result = reference.ReferenceResult("toːkʲoː", [], backend_input)
        record = reference.build_fixture_record(
            make_case(), lambda _case: result, version_provider=lambda _case: {}
        )
        self.assertEqual(record["backendInput"], backend_input)

    def test_backend_input_is_preserved_when_upstream_pipeline_fails(self):
        backend_input = {
            "kind": "example.words",
            "schemaVersion": 1,
            "words": [{"text": "　"}],
        }

        def fail(_case):
            raise reference.UpstreamExecutionFailure(
                IndexError("list index out of range"), backend_input
            )

        record = reference.build_fixture_record(
            make_case(), fail, version_provider=lambda _case: {}
        )
        self.assertEqual(record["error"], {"category": "upstreamFailure"})
        self.assertEqual(record["backendInput"], backend_input)
        self.assertIsNone(record["phonemes"])
        self.assertIsNone(record["tokens"])


class JapaneseNumberModeTests(unittest.TestCase):
    def make_runner_without_checkout(self):
        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        return runner

    def test_num2kana_dispatch_is_dependency_free(self):
        module = SimpleNamespace(Convert=lambda text, dictionary: dictionary + ":" + text)
        with mock.patch.object(reference, "_import_upstream_module", return_value=module) as imported:
            result = self.make_runner_without_checkout().run(make_case())

        self.assertEqual(result, ("hiragana:300", None))
        imported.assert_called_once_with("misaki.num2kana")

    def test_kanji_reverse_dispatch(self):
        module = SimpleNamespace(ConvertKanji=lambda text: "12345")
        case = make_case(mode="ja-kanji-number", options={}, input_text="一万二千三百四十五")
        with mock.patch.object(reference, "_import_upstream_module", return_value=module):
            result = self.make_runner_without_checkout().run(case)
        self.assertEqual(result, ("12345", None))


def pyopenjtalk_word(**overrides):
    word = {
        "acc": 0,
        "cform": "*",
        "chain_flag": -1,
        "chain_rule": "C2",
        "ctype": "*",
        "mora_size": 4,
        "orig": "東京",
        "pos": "名詞",
        "pos_group1": "固有名詞",
        "pos_group2": "地域",
        "pos_group3": "一般",
        "pron": "トーキョー",
        "read": "トウキョウ",
        "string": "東京",
    }
    word.update(overrides)
    return word


class JapanesePyopenjtalkModeTests(unittest.TestCase):
    def test_raw_frontend_stream_is_captured_once_and_replayed(self):
        original_words = [pyopenjtalk_word()]

        class FakeBackend:
            def __init__(self):
                self.calls = 0

            def run_frontend(self, _text):
                self.calls += 1
                return copy.deepcopy(original_words)

        backend = FakeBackend()

        class FakeJAG2P:
            def __init__(self, version, unk):
                self.version = version
                self.unk = unk

            def __call__(self, text):
                replayed = module.pyopenjtalk.run_frontend(text)
                replayed[0]["string"] = "mutated by pipeline"
                return "toːkʲoː", []

        module = SimpleNamespace(JAG2P=FakeJAG2P, pyopenjtalk=backend)
        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        case = make_case(mode="pyopenjtalk", options={}, input_text="東京")

        with mock.patch.object(reference, "_import_upstream_module", return_value=module):
            result = runner.run(case)

        self.assertIsInstance(result, reference.ReferenceResult)
        self.assertEqual(backend.calls, 1)
        self.assertEqual(result.backend_input["words"], original_words)
        self.assertEqual(result.backend_input["schemaVersion"], 1)
        self.assertEqual(result.backend_input["kind"], "pyopenjtalk.run_frontend.words")

    def test_raw_frontend_schema_rejects_missing_and_wrong_typed_fields(self):
        missing = pyopenjtalk_word()
        missing.pop("pron")
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_pyopenjtalk_frontend([missing])

        wrong_type = pyopenjtalk_word(acc=True)
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_pyopenjtalk_frontend([wrong_type])


def cutlet_word(
    surface,
    *,
    pron=None,
    kana=None,
    char_type=6,
    is_unk=True,
):
    return SimpleNamespace(
        surface=surface,
        feature=SimpleNamespace(pron=pron, kana=kana),
        char_type=char_type,
        is_unk=is_unk,
    )


class JapaneseCutletModeTests(unittest.TestCase):
    @staticmethod
    def make_runner_without_checkout():
        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        return runner

    @staticmethod
    def make_case(text="今日"):
        return reference.FixtureCase(
            language="ja", mode="cutlet", options={}, input_text=text
        )

    def test_serializer_captures_readings_raw_types_and_longest_grouping(self):
        readings = []

        def kata2hira(value):
            readings.append(value)
            return {"キョ": "きょ", "ウ": "う"}.get(value, value)

        replay = reference.serialize_cutlet_backend_input(
            "今日。謎",
            [
                cutlet_word("今", pron="キョ", char_type=2, is_unk=False),
                cutlet_word("日", pron="", kana="ウ", char_type=7),
                cutlet_word("。", char_type=3),
                cutlet_word("謎", char_type=5),
            ],
            kata2hira,
            frozenset({"今", "今日"}),
        )

        self.assertEqual(readings, ["キョ", "ウ", "。", "謎"])
        self.assertEqual(
            replay,
            {
                "kind": reference.CUTLET_BACKEND_INPUT_KIND,
                "normalizedText": "今日。謎",
                "schemaVersion": reference.CUTLET_BACKEND_INPUT_SCHEMA_VERSION,
                "words": [
                    {
                        "charType": 2,
                        "hiragana": "きょ",
                        "isUnknown": False,
                        "joinWithNext": True,
                        "kana": None,
                        "pronunciation": "キョ",
                        "surface": "今",
                    },
                    {
                        "charType": 7,
                        "hiragana": "う",
                        "isUnknown": True,
                        "joinWithNext": False,
                        "kana": "ウ",
                        "pronunciation": "",
                        "surface": "日",
                    },
                    {
                        "charType": 3,
                        "hiragana": "。",
                        "isUnknown": True,
                        "joinWithNext": False,
                        "kana": None,
                        "pronunciation": None,
                        "surface": "。",
                    },
                    {
                        "charType": 5,
                        "hiragana": "謎",
                        "isUnknown": True,
                        "joinWithNext": False,
                        "kana": None,
                        "pronunciation": None,
                        "surface": "謎",
                    },
                ],
            },
        )

    def test_serializer_uses_three_node_longest_match(self):
        replay = reference.serialize_cutlet_backend_input(
            "あうぎ",
            [
                cutlet_word("あ", pron="ア", char_type=6, is_unk=False),
                cutlet_word("う", pron="ウ", char_type=6, is_unk=False),
                cutlet_word("ぎ", pron="ギ", char_type=6, is_unk=False),
            ],
            lambda value: {"ア": "あ", "ウ": "う", "ギ": "ぎ"}[value],
            frozenset({"あ", "あう", "あうぎ"}),
        )

        self.assertEqual(
            [word["joinWithNext"] for word in replay["words"]],
            [True, True, False],
        )

    def test_serializer_rejects_untyped_morphology_drift(self):
        valid = cutlet_word("猫", pron="ネコ")
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_cutlet_backend_input("猫", (valid,), str, set())
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_cutlet_backend_input(
                "猫", [cutlet_word("")], str, set()
            )
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_cutlet_backend_input(
                "猫", [cutlet_word("猫", char_type=True)], str, set()
            )
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_cutlet_backend_input(
                "猫", [cutlet_word("猫", is_unk=1)], str, set()
            )
        with self.assertRaisesRegex(
            reference.InvalidResult, "pronunciation must be a string or null"
        ):
            reference.serialize_cutlet_backend_input(
                "猫", [cutlet_word("猫", pron=1, kana="ネコ")], str, set()
            )
        with self.assertRaisesRegex(
            reference.InvalidResult, "kana must be a string or null"
        ):
            reference.serialize_cutlet_backend_input(
                "猫", [cutlet_word("猫", pron="", kana=1)], str, set()
            )
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_cutlet_backend_input("猫", [valid], str, [])

    def test_actual_tagger_call_is_captured_once_and_restored(self):
        raw_words = [
            cutlet_word("今", pron="キョ", char_type=2, is_unk=False),
            cutlet_word("日", pron="ウ", char_type=2, is_unk=False),
        ]

        class FakeTagger:
            def __init__(self):
                self.inputs = []

            def __call__(self, text):
                self.inputs.append(text)
                return copy.deepcopy(raw_words)

        tagger = FakeTagger()
        constructed = []

        class FakeJAG2P:
            def __init__(self, version, unk):
                self.version = version
                self.unk = unk
                self.cutlet = SimpleNamespace(tagger=tagger)
                constructed.append(self)

            def __call__(self, text):
                if not text:
                    return "", None
                words = list(self.cutlet.tagger("normalized:" + text))
                words[0].surface = "mutated after capture"
                return "kʲoɯ", None

        module = SimpleNamespace(JAG2P=FakeJAG2P)
        cutlet_module = SimpleNamespace(
            JA_WORDS=frozenset({"今日"}),
            jaconv=SimpleNamespace(
                kata2hira=lambda value: {"キョ": "きょ", "ウ": "う"}.get(
                    value, value
                )
            ),
        )

        def import_module(name):
            return {"misaki.ja": module, "misaki.cutlet": cutlet_module}[name]

        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_require_python_312"
        ), mock.patch.object(
            reference, "_require_cutlet_dependency_versions"
        ), mock.patch.object(
            reference,
            "_require_cutlet_ja_words_resource",
            return_value=reference.CUTLET_JA_WORDS_IDENTITY,
        ), mock.patch.object(
            reference,
            "_require_cutlet_unidic_resource",
            return_value={
                "fugashi-system-dictionary": (
                    reference.CUTLET_UNIDIC_LIVE_DICTIONARY_IDENTITY
                ),
                "unidic-dictionary-tree": reference.CUTLET_UNIDIC_TREE_IDENTITY,
                "unidic-dictionary-version": (
                    reference.CUTLET_UNIDIC_VERSION_MARKER
                ),
            },
        ), mock.patch.object(
            reference, "_import_upstream_module", side_effect=import_module
        ):
            result = runner.run(self.make_case())
            empty = runner.run(self.make_case(""))

        self.assertEqual(len(constructed), 1)
        self.assertEqual(tagger.inputs, ["normalized:今日"])
        self.assertIs(constructed[0].cutlet.tagger, tagger)
        self.assertIsNone(result.tokens)
        self.assertEqual(
            result.backend_input,
            {
                "kind": reference.CUTLET_BACKEND_INPUT_KIND,
                "normalizedText": "normalized:今日",
                "schemaVersion": reference.CUTLET_BACKEND_INPUT_SCHEMA_VERSION,
                "words": [
                    {
                        "charType": 2,
                        "hiragana": "きょ",
                        "isUnknown": False,
                        "joinWithNext": True,
                        "kana": None,
                        "pronunciation": "キョ",
                        "surface": "今",
                    },
                    {
                        "charType": 2,
                        "hiragana": "う",
                        "isUnknown": False,
                        "joinWithNext": False,
                        "kana": None,
                        "pronunciation": "ウ",
                        "surface": "日",
                    },
                ],
            },
        )
        self.assertEqual(empty.backend_input["normalizedText"], "")
        self.assertEqual(empty.backend_input["words"], [])

    def test_locked_versions_are_preflighted_and_recorded(self):
        installed = dict(reference.CUTLET_LOCKED_DISTRIBUTIONS)
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ), mock.patch.object(
            reference.platform, "python_version", return_value="3.12.11"
        ), mock.patch.object(
            reference.unicodedata, "unidata_version", "15.0.0"
        ), mock.patch.object(
            reference.importlib,
            "import_module",
            return_value=SimpleNamespace(
                JA_WORDS=frozenset(), Tagger=lambda: object()
            ),
        ), mock.patch.object(
            reference,
            "_require_cutlet_ja_words_resource",
            return_value=reference.CUTLET_JA_WORDS_IDENTITY,
        ), mock.patch.object(
            reference,
            "_require_cutlet_unidic_resource",
            return_value={
                "fugashi-system-dictionary": (
                    reference.CUTLET_UNIDIC_LIVE_DICTIONARY_IDENTITY
                ),
                "unidic-dictionary-tree": reference.CUTLET_UNIDIC_TREE_IDENTITY,
                "unidic-dictionary-version": (
                    reference.CUTLET_UNIDIC_VERSION_MARKER
                ),
            },
        ):
            reference._require_cutlet_dependency_versions()
            versions = reference.backend_versions(self.make_case())

        self.assertEqual(
            versions,
            {
                **installed,
                "fugashi-system-dictionary": (
                    reference.CUTLET_UNIDIC_LIVE_DICTIONARY_IDENTITY
                ),
                "misaki-ja-words": reference.CUTLET_JA_WORDS_IDENTITY,
                "python": "3.12.11",
                "unicode-data": "15.0.0",
                "unidic-dictionary-tree": reference.CUTLET_UNIDIC_TREE_IDENTITY,
                "unidic-dictionary-version": reference.CUTLET_UNIDIC_VERSION_MARKER,
            },
        )

        installed["fugashi"] = "1.3.0"
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_cutlet_dependency_versions()

    def test_fugashi_runtime_error_is_typed_for_versions_and_engine(self):
        def failing_factory():
            raise RuntimeError("Failed initializing MeCab")

        with self.assertRaisesRegex(
            reference.BackendUnavailable, "fugashi/MeCab initialization failed"
        ) as initialization:
            reference._initialize_cutlet_backend(failing_factory)
        self.assertIsInstance(initialization.exception.__cause__, RuntimeError)

        installed = dict(reference.CUTLET_LOCKED_DISTRIBUTIONS)
        cutlet_module = SimpleNamespace(
            JA_WORDS=frozenset(), Tagger=failing_factory
        )
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ), mock.patch.object(
            reference.importlib,
            "import_module",
            return_value=cutlet_module,
        ), mock.patch.object(
            reference,
            "_require_cutlet_ja_words_resource",
            return_value=reference.CUTLET_JA_WORDS_IDENTITY,
        ):
            versions = reference.backend_versions(self.make_case())
        self.assertIsNone(versions["fugashi-system-dictionary"])
        self.assertIsNone(versions["unidic-dictionary-tree"])
        self.assertIsNone(versions["unidic-dictionary-version"])

        module = SimpleNamespace(JAG2P=lambda **_kwargs: failing_factory())

        def import_module(name):
            return {"misaki.ja": module, "misaki.cutlet": cutlet_module}[name]

        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_require_python_312"
        ), mock.patch.object(
            reference, "_require_cutlet_dependency_versions"
        ), mock.patch.object(
            reference, "_import_upstream_module", side_effect=import_module
        ):
            with self.assertRaisesRegex(
                reference.BackendUnavailable,
                "fugashi/MeCab initialization failed",
            ) as engine_failure:
                runner.run(self.make_case())
            record = reference.build_fixture_record(
                self.make_case(),
                runner.run,
                version_provider=lambda _case: {},
            )
        self.assertIsInstance(engine_failure.exception.__cause__, RuntimeError)
        self.assertEqual(record["error"], {"category": "backendUnavailable"})
        self.assertIsNone(record["phonemes"])
        self.assertIsNone(record["tokens"])

    def test_ja_words_resource_identity_is_exact_and_actionable(self):
        with tempfile.TemporaryDirectory() as directory_name:
            package = Path(directory_name) / "misaki"
            resource_directory = package / "data"
            resource_directory.mkdir(parents=True)
            module_path = package / "cutlet.py"
            module_path.touch()
            payload = "猫\n犬".encode("utf-8")
            resource_path = resource_directory / "ja_words.txt"
            resource_path.write_bytes(payload)
            digest = reference.hashlib.sha256(payload).hexdigest()
            identity = "sha256:{}+bytes:{}+records:2".format(
                digest, len(payload)
            )
            module = SimpleNamespace(__file__=str(module_path))
            words = frozenset(("猫", "犬"))

            with mock.patch.object(
                reference, "CUTLET_JA_WORDS_SHA256", digest
            ), mock.patch.object(
                reference, "CUTLET_JA_WORDS_SIZE_BYTES", len(payload)
            ), mock.patch.object(
                reference, "CUTLET_JA_WORDS_RECORD_COUNT", 2
            ), mock.patch.object(
                reference, "CUTLET_JA_WORDS_IDENTITY", identity
            ):
                self.assertEqual(
                    reference._require_cutlet_ja_words_resource(module, words),
                    identity,
                )
                resource_path.write_bytes(payload + b"\nchanged")
                with self.assertRaisesRegex(
                    reference.BackendUnavailable, "ja_words.txt identity"
                ):
                    reference._require_cutlet_ja_words_resource(module, words)
                resource_path.write_bytes(payload)
                with self.assertRaisesRegex(
                    reference.InvalidResult, "exactly 2 unique records"
                ):
                    reference._require_cutlet_ja_words_resource(
                        module, frozenset(("猫",))
                    )

    def test_live_tagger_must_use_only_the_validated_system_dictionary(self):
        with tempfile.TemporaryDirectory() as directory_name:
            dicdir = Path(directory_name) / "dicdir"
            dicdir.mkdir()
            system_dictionary = dicdir / "sys.dic"
            system_dictionary.touch()
            tagger = SimpleNamespace(
                dictionary_info=[
                    {
                        "charset": reference.CUTLET_UNIDIC_DICTIONARY_CHARSET,
                        "filename": str(system_dictionary),
                        "size": reference.CUTLET_UNIDIC_DICTIONARY_ENTRY_COUNT,
                        "version": (
                            reference.CUTLET_UNIDIC_DICTIONARY_BINARY_VERSION
                        ),
                    }
                ]
            )

            self.assertEqual(
                reference._require_cutlet_tagger_dictionary(tagger, dicdir),
                reference.CUTLET_UNIDIC_LIVE_DICTIONARY_IDENTITY,
            )

            tagger.dictionary_info.append(
                {"filename": str(dicdir / "user.dic")}
            )
            with self.assertRaisesRegex(
                reference.BackendUnavailable, "exactly one dictionary"
            ):
                reference._require_cutlet_tagger_dictionary(tagger, dicdir)

            tagger.dictionary_info = [
                {
                    "charset": reference.CUTLET_UNIDIC_DICTIONARY_CHARSET,
                    "filename": str(
                        Path(directory_name) / "other" / "sys.dic"
                    ),
                    "size": reference.CUTLET_UNIDIC_DICTIONARY_ENTRY_COUNT,
                    "version": reference.CUTLET_UNIDIC_DICTIONARY_BINARY_VERSION,
                }
            ]
            with self.assertRaisesRegex(
                reference.BackendUnavailable, "expected"
            ):
                reference._require_cutlet_tagger_dictionary(tagger, dicdir)

    def test_unidic_tree_version_and_live_dictionary_are_all_exact(self):
        with tempfile.TemporaryDirectory() as directory_name:
            dicdir = Path(directory_name) / "dicdir"
            dicdir.mkdir()
            (dicdir / "version").write_text(
                reference.CUTLET_UNIDIC_VERSION_MARKER,
                encoding="utf-8",
            )
            system_dictionary = dicdir / "sys.dic"
            system_dictionary.write_bytes(b"dictionary")
            expected = reference._directory_tree_fingerprint(str(dicdir))
            identity = "sha256:{}+files:{}+bytes:{}".format(*expected)
            tagger = SimpleNamespace(
                dictionary_info=[
                    {
                        "charset": reference.CUTLET_UNIDIC_DICTIONARY_CHARSET,
                        "filename": str(system_dictionary),
                        "size": reference.CUTLET_UNIDIC_DICTIONARY_ENTRY_COUNT,
                        "version": (
                            reference.CUTLET_UNIDIC_DICTIONARY_BINARY_VERSION
                        ),
                    }
                ]
            )

            with mock.patch.object(
                reference.importlib,
                "import_module",
                return_value=SimpleNamespace(DICDIR=str(dicdir)),
            ), mock.patch.object(
                reference, "CUTLET_UNIDIC_TREE_SHA256", expected[0]
            ), mock.patch.object(
                reference, "CUTLET_UNIDIC_TREE_FILE_COUNT", expected[1]
            ), mock.patch.object(
                reference, "CUTLET_UNIDIC_TREE_SIZE_BYTES", expected[2]
            ), mock.patch.object(
                reference, "CUTLET_UNIDIC_TREE_IDENTITY", identity
            ):
                self.assertEqual(
                    reference._require_cutlet_unidic_resource(tagger),
                    {
                        "fugashi-system-dictionary": (
                            reference.CUTLET_UNIDIC_LIVE_DICTIONARY_IDENTITY
                        ),
                        "unidic-dictionary-tree": identity,
                        "unidic-dictionary-version": (
                            reference.CUTLET_UNIDIC_VERSION_MARKER
                        ),
                    },
                )

                system_dictionary.write_bytes(b"changed")
                reference._directory_tree_fingerprint.cache_clear()
                with self.assertRaisesRegex(
                    reference.BackendUnavailable, "tree identity"
                ):
                    reference._require_cutlet_unidic_resource(tagger)

                system_dictionary.write_bytes(b"dictionary")
                (dicdir / "version").write_text("latest", encoding="utf-8")
                reference._directory_tree_fingerprint.cache_clear()
                with self.assertRaisesRegex(
                    reference.BackendUnavailable, "version marker"
                ):
                    reference._require_cutlet_unidic_resource(tagger)

    def test_cutlet_corpus_has_adversarial_grouping_and_spacing_cases(self):
        cases = reference.read_cases(
            Path("tool/reference/cases/ja_cutlet.jsonl")
        )
        by_id = {case.case_id: case.input_text for case in cases}

        self.assertEqual(len(cases), 27)
        self.assertEqual(by_id["three-node-longest-match"], "あうぎ")
        self.assertEqual(
            by_id["empty-romanization-substring-spacing"], "あ」？い"
        )


class EnglishNoFallbackModeTests(unittest.TestCase):
    def test_cached_engine_captures_each_actual_tokenize_call_once(self):
        constructed = []

        class FakeG2P:
            preprocess_calls = 0

            def __init__(self, **kwargs):
                self.constructor_fallback = kwargs["fallback"]
                self.fallback = kwargs["fallback"]
                self.tokenize_calls = 0
                constructed.append(self)

            @staticmethod
            def preprocess(text):
                FakeG2P.preprocess_calls += 1
                words = text.split()
                return text.upper(), words, {1: "/wɜɹld"}

            def tokenize(self, text, source_words, features):
                self.tokenize_calls += 1
                self.asserted_input = (text, source_words, features)
                return [
                    FakeToken(
                        text="HELLO",
                        tag="UH",
                        whitespace=" ",
                        phonemes=None,
                        start_ts=1.25,
                        end_ts=2.5,
                        _={"is_head": True, "num_flags": "", "prespace": False},
                    ),
                    FakeToken(
                        text="WORLD",
                        tag="NN",
                        whitespace="",
                        phonemes="wɜɹld",
                        start_ts=None,
                        end_ts=None,
                        _={
                            "is_head": True,
                            "num_flags": "",
                            "prespace": False,
                            "rating": 5,
                        },
                    ),
                ]

            def __call__(self, text, preprocess=True):
                preprocess_fn = FakeG2P.preprocess if preprocess is True else preprocess
                prepared_text, source_words, features = (
                    preprocess_fn(text) if preprocess_fn else (text, [], {})
                )
                tokens = self.tokenize(prepared_text, source_words, features)
                tokens[0].text = "mutated after tokenization"
                tokens[0]._["prespace"] = True
                return text, tokens

        module = SimpleNamespace(
            G2P=FakeG2P,
            spacy=SimpleNamespace(
                util=SimpleNamespace(is_package=lambda _name: True)
            ),
        )
        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        case = reference.FixtureCase(
            language="en",
            mode="american-no-fallback",
            options={"version": None},
            input_text="hello world",
        )

        with mock.patch.object(
            reference, "_require_english_dependency_versions"
        ), mock.patch.object(
            reference, "_import_upstream_module", return_value=module
        ):
            first = runner.run(case)
            second = runner.run(
                reference.FixtureCase(
                    language="en",
                    mode="american-no-fallback",
                    options={"version": None},
                    input_text="hello again",
                )
            )

        self.assertIsInstance(first, reference.ReferenceResult)
        self.assertIsInstance(second, reference.ReferenceResult)
        self.assertEqual(len(constructed), 1)
        self.assertTrue(constructed[0].constructor_fallback)
        self.assertIsInstance(
            constructed[0].constructor_fallback, reference._DisabledFallback
        )
        self.assertIsNone(constructed[0].fallback)
        self.assertEqual(FakeG2P.preprocess_calls, 2)
        self.assertEqual(constructed[0].tokenize_calls, 2)

        backend_input = first.backend_input
        self.assertEqual(
            backend_input["kind"], reference.ENGLISH_BACKEND_INPUT_KIND
        )
        self.assertEqual(
            backend_input["schemaVersion"],
            reference.ENGLISH_BACKEND_INPUT_SCHEMA_VERSION,
        )
        self.assertEqual(
            backend_input["preprocess"],
            {
                "applied": True,
                "features": [
                    {"sourceWordIndex": 1, "value": "/wɜɹld"}
                ],
                "sourceWords": ["hello", "world"],
                "text": "HELLO WORLD",
            },
        )
        self.assertEqual(backend_input["tokens"][0]["text"], "HELLO")
        self.assertFalse(backend_input["tokens"][0]["_"]["prespace"])
        self.assertEqual(backend_input["tokens"][0]["start_ts"], 1.25)
        self.assertEqual(backend_input["tokens"][0]["end_ts"], 2.5)
        self.assertIsNone(backend_input["tokens"][0]["phonemes"])
        self.assertEqual(backend_input["tokens"][1]["phonemes"], "wɜɹld")
        self.assertEqual(backend_input["tokens"][1]["_"]["rating"], 5)
        self.assertEqual(first.tokens[0].text, "mutated after tokenization")

    def test_espeak_mode_captures_ordered_raw_backend_calls_per_case(self):
        raw_backend_calls = []

        class FakeRawEspeakBackend:
            def phonemize(self, texts):
                raw_backend_calls.append(list(texts))
                return [" raw:{} ".format(texts[0])]

        class FakeEspeakFallback:
            def __init__(self, british, version):
                self.british = british
                self.version = version
                self.backend = FakeRawEspeakBackend()

            def __call__(self, token):
                phones = self.backend.phonemize([token.text])
                return phones[0].strip(), 2

        class FakeG2P:
            def __init__(self, **kwargs):
                self.fallback = kwargs["fallback"]

            def tokenize(self, text, source_words, features):
                return [
                    FakeToken(
                        text=text,
                        tag="NN",
                        whitespace="",
                        phonemes=None,
                        start_ts=None,
                        end_ts=None,
                        _={"is_head": True, "num_flags": "", "prespace": False},
                    )
                ]

            def __call__(self, text, preprocess=True):
                tokens = self.tokenize(text, [text], {})
                phones, rating = self.fallback(tokens[0])
                tokens[0].phonemes = phones
                tokens[0]._["rating"] = rating
                return phones, tokens

        english_module = SimpleNamespace(
            G2P=FakeG2P,
            spacy=SimpleNamespace(
                util=SimpleNamespace(is_package=lambda _name: True)
            ),
        )
        espeak_module = SimpleNamespace(EspeakFallback=FakeEspeakFallback)

        def import_module(name):
            return english_module if name == "misaki.en" else espeak_module

        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        with mock.patch.object(
            reference, "_require_english_espeak_dependency_versions"
        ), mock.patch.object(
            reference, "_require_english_dependency_versions"
        ), mock.patch.object(
            reference, "_english_espeak_resource_identities"
        ), mock.patch.object(
            reference, "_import_upstream_module", side_effect=import_module
        ):
            first = runner.run(
                reference.FixtureCase(
                    language="en",
                    mode="american-espeak-fallback",
                    options={"version": None},
                    input_text="blorp",
                )
            )
            second = runner.run(
                reference.FixtureCase(
                    language="en",
                    mode="american-espeak-fallback",
                    options={"version": None},
                    input_text="snorf",
                )
            )

        self.assertEqual(raw_backend_calls, [["blorp"], ["snorf"]])
        self.assertEqual(
            first.backend_input["schemaVersion"],
            reference.ENGLISH_ESPEAK_BACKEND_INPUT_SCHEMA_VERSION,
        )
        self.assertEqual(
            first.backend_input["espeakCalls"],
            [{"rawPhones": " raw:blorp ", "text": "blorp"}],
        )
        self.assertEqual(
            second.backend_input["espeakCalls"],
            [{"rawPhones": " raw:snorf ", "text": "snorf"}],
        )

    def test_espeak_call_schema_preserves_null_and_rejects_drift(self):
        token = FakeToken(
            text="hello",
            tag="UH",
            whitespace="",
            phonemes=None,
            start_ts=None,
            end_ts=None,
            _={"is_head": True, "num_flags": "", "prespace": False},
        )
        snapshot = reference.serialize_english_backend_input(
            reference.serialize_english_preprocess_output(
                "hello", ["hello"], {}, True
            ),
            [token],
        )
        captured = reference.attach_english_espeak_calls(
            snapshot,
            [
                {"text": "hello", "rawPhones": None},
                {"text": "world", "rawPhones": ""},
            ],
        )
        self.assertEqual(
            captured["schemaVersion"],
            reference.ENGLISH_ESPEAK_BACKEND_INPUT_SCHEMA_VERSION,
        )
        self.assertIsNone(captured["espeakCalls"][0]["rawPhones"])
        self.assertEqual(captured["espeakCalls"][1]["rawPhones"], "")
        self.assertNotIn("espeakCalls", snapshot)

        for invalid in (
            None,
            [{"text": "hello"}],
            [{"text": 1, "rawPhones": "h"}],
            [{"text": "hello", "rawPhones": 1}],
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(reference.InvalidResult):
                    reference.attach_english_espeak_calls(snapshot, invalid)

    def test_model_call_schema_captures_exact_ids_and_rejects_drift(self):
        token = FakeToken(
            text="a😀",
            tag="NN",
            whitespace="",
            phonemes=None,
            start_ts=None,
            end_ts=None,
            _={"is_head": True, "num_flags": "", "prespace": False},
        )
        snapshot = reference.serialize_english_backend_input(
            reference.serialize_english_preprocess_output(
                "a😀", ["a😀"], {}, True
            ),
            [token],
        )
        call = {
            "generatedIds": [2, 4, 7, 2],
            "inputIds": [1, 5, 3, 2],
            "phonemes": "ˈA",
            "rating": 1,
            "text": "a😀",
        }
        captured = reference.attach_english_model_calls(snapshot, [call])

        self.assertEqual(
            captured["schemaVersion"],
            reference.ENGLISH_MODEL_BACKEND_INPUT_SCHEMA_VERSION,
        )
        self.assertEqual(captured["modelCalls"], [call])
        self.assertNotIn("modelCalls", snapshot)
        call["inputIds"].append(99)
        call["generatedIds"].append(99)
        self.assertEqual(captured["modelCalls"][0]["inputIds"], [1, 5, 3, 2])
        self.assertEqual(
            captured["modelCalls"][0]["generatedIds"], [2, 4, 7, 2]
        )

        valid = {
            "generatedIds": [2],
            "inputIds": [1, 5, 2],
            "phonemes": "",
            "rating": 1,
            "text": "a",
        }
        invalid_calls = (
            None,
            [{key: value for key, value in valid.items() if key != "rating"}],
            [{**valid, "text": ""}],
            [{**valid, "inputIds": [1, 2]}],
            [{**valid, "inputIds": [0, 5, 2]}],
            [{**valid, "inputIds": [1, True, 2]}],
            [{**valid, "generatedIds": []}],
            [{**valid, "generatedIds": [-1]}],
            [{**valid, "phonemes": None}],
            [{**valid, "rating": 2}],
        )
        for invalid in invalid_calls:
            with self.subTest(invalid=invalid):
                with self.assertRaises(reference.InvalidResult):
                    reference.attach_english_model_calls(snapshot, invalid)

    def test_espeak_versions_and_resource_identities_are_pinned(self):
        english_installed = {
            **reference.ENGLISH_LOCKED_DISTRIBUTIONS,
            "en-core-web-sm": "3.8.0",
        }
        with mock.patch.object(reference, "_require_python_312"), mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: english_installed[name],
        ):
            reference._require_english_dependency_versions(False)

        english_installed["regex"] = "2025.1.1"
        with mock.patch.object(reference, "_require_python_312"), mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: english_installed[name],
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_english_dependency_versions(False)

        transformer_installed = {
            **reference.ENGLISH_LOCKED_DISTRIBUTIONS,
            **reference.ENGLISH_TRANSFORMER_LOCKED_DISTRIBUTIONS,
            "en-core-web-trf": "3.8.0",
        }
        with mock.patch.object(reference, "_require_python_312"), mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: transformer_installed[name],
        ):
            reference._require_english_dependency_versions(True)

        transformer_installed["spacy-curated-transformers"] = "0.2.2"
        with mock.patch.object(reference, "_require_python_312"), mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: transformer_installed[name],
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_english_dependency_versions(True)

        installed = dict(reference.ENGLISH_ESPEAK_LOCKED_DISTRIBUTIONS)
        self.assertEqual(installed["joblib"], "1.4.2")
        with mock.patch.object(reference, "_require_python_312"), mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ):
            reference._require_english_espeak_dependency_versions()

        installed["phonemizer-fork"] = "3.3.1"
        with mock.patch.object(reference, "_require_python_312"), mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_english_espeak_dependency_versions()

        installed = dict(reference.ENGLISH_ESPEAK_LOCKED_DISTRIBUTIONS)
        installed["joblib"] = "1.4.0"
        with mock.patch.object(reference, "_require_python_312"), mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_english_espeak_dependency_versions()

        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            library = directory / "libespeak-ng.dylib"
            library.write_bytes(b"library")
            data = directory / "espeak-ng-data"
            data.mkdir()
            (data / "voices").write_bytes(b"voices")
            loader = SimpleNamespace(
                get_library_path=lambda: str(library),
                get_data_path=lambda: str(data),
            )
            versions = {
                **reference.ENGLISH_ESPEAK_LOCKED_DISTRIBUTIONS,
                "en-core-web-sm": "3.8.0",
                "num2words": "0.5.14",
                "spacy": "3.8.4",
            }
            reference._english_espeak_resource_identities.cache_clear()
            with mock.patch.object(
                reference.importlib_metadata,
                "version",
                side_effect=lambda name: versions[name],
            ), mock.patch.object(
                reference.importlib,
                "import_module",
                return_value=loader,
            ), mock.patch.object(
                reference.platform,
                "python_version",
                return_value="3.12.11",
            ):
                recorded = reference.backend_versions(
                    reference.FixtureCase(
                        language="en",
                        mode="american-espeak-fallback",
                        options={"version": None},
                        input_text="blorp",
                    )
                )
            reference._english_espeak_resource_identities.cache_clear()

        self.assertEqual(recorded["python"], "3.12.11")
        self.assertEqual(recorded["joblib"], "1.4.2")
        self.assertRegex(recorded["espeakng-library"], r"^sha256:.+\+bytes:7$")
        self.assertRegex(
            recorded["espeakng-data"], r"^sha256:.+\+files:1\+bytes:6$"
        )

    def test_raw_replay_schema_is_typed_and_rejects_drift(self):
        token = FakeToken(
            text="hello",
            tag="UH",
            whitespace=" ",
            phonemes="həlˈO",
            start_ts=None,
            end_ts=None,
            _={
                "is_head": True,
                "num_flags": "n",
                "prespace": False,
                "stress": -0.5,
                "rating": 5,
            },
        )
        preprocess_output = reference.serialize_english_preprocess_output(
            "hello", ["hello"], {0: -0.5}, True
        )
        backend_input = reference.serialize_english_backend_input(
            preprocess_output, [token]
        )

        self.assertEqual(
            backend_input["preprocess"]["features"],
            [{"sourceWordIndex": 0, "value": -0.5}],
        )
        self.assertEqual(
            set(backend_input["tokens"][0]),
            {"_", "end_ts", "phonemes", "start_ts", "tag", "text", "whitespace"},
        )
        self.assertEqual(
            backend_input["tokens"][0]["_"],
            {
                "is_head": True,
                "num_flags": "n",
                "prespace": False,
                "rating": 5,
                "stress": -0.5,
            },
        )

        with self.assertRaises(reference.InvalidResult):
            reference.serialize_english_preprocess_output(
                "hello", ["hello"], {True: 1}, True
            )
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_english_preprocess_output(
                "hello world", ["hello", "world"], {0: 1, "1": 2}, True
            )
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_english_preprocess_output(
                "hello", ["hello"], {1: 1}, True
            )

        missing_metadata = copy.deepcopy(token)
        missing_metadata._.pop("is_head")
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_english_tokenize_tokens([missing_metadata])

        extra_metadata = copy.deepcopy(token)
        extra_metadata._["alias"] = "hi"
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_english_tokenize_tokens([extra_metadata])

        wrong_timestamp = copy.deepcopy(token)
        wrong_timestamp.start_ts = True
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_english_tokenize_tokens([wrong_timestamp])


class EnglishCorpusTests(unittest.TestCase):
    @staticmethod
    def records(name):
        return [
            json.loads(line)
            for line in (Path("tool/reference/cases") / name)
            .read_text(encoding="utf-8")
            .splitlines()
            if line
        ]

    def test_dialect_corpora_are_mode_only_twins_with_version_coverage(self):
        american = self.records("en_american_espeak_fallback.jsonl")
        british = self.records("en_british_espeak_fallback.jsonl")
        self.assertEqual(len(american), 20)
        self.assertEqual(len(british), 20)
        self.assertEqual(len({case["caseId"] for case in american}), 20)
        self.assertIn("2.0", {case["options"].get("version") for case in american})

        for american_case, british_case in zip(american, british):
            self.assertEqual(american_case.pop("mode"), "american-espeak-fallback")
            self.assertEqual(british_case.pop("mode"), "british-espeak-fallback")
            self.assertEqual(british_case, american_case)

    def test_transformer_corpora_change_only_model_and_dialect_mode(self):
        american_small = self.records("en_american_no_fallback.jsonl")
        british_small = self.records("en_british_no_fallback.jsonl")
        american_trf = self.records("en_american_trf_no_fallback.jsonl")
        british_trf = self.records("en_british_trf_no_fallback.jsonl")

        self.assertEqual(len(american_trf), 38)
        self.assertEqual(len(british_trf), 38)
        self.assertEqual(len({case["caseId"] for case in american_trf}), 38)

        for small_case, transformer_case in zip(
            american_small, american_trf[: len(american_small)]
        ):
            self.assertIs(transformer_case["options"].pop("trf"), True)
            self.assertEqual(transformer_case, small_case)
        for small_case, transformer_case in zip(
            british_small, british_trf[: len(british_small)]
        ):
            self.assertIs(transformer_case["options"].pop("trf"), True)
            self.assertEqual(transformer_case, small_case)

        self.assertEqual(
            [case["caseId"] for case in american_trf[32:]],
            [
                "trf-full-pieces-104",
                "trf-full-pieces-105",
                "trf-full-pieces-144",
                "trf-overlap-emoji-145",
                "trf-full-pieces-208",
                "trf-full-pieces-249",
            ],
        )

        for american_case, british_case in zip(american_trf, british_trf):
            self.assertEqual(american_case.pop("mode"), "american-no-fallback")
            self.assertEqual(british_case.pop("mode"), "british-no-fallback")
            self.assertEqual(british_case, american_case)

    def test_transformer_espeak_corpora_change_only_model_and_dialect_mode(self):
        american_small = self.records("en_american_espeak_fallback.jsonl")
        british_small = self.records("en_british_espeak_fallback.jsonl")
        american_trf = self.records(
            "en_american_trf_espeak_fallback.jsonl"
        )
        british_trf = self.records("en_british_trf_espeak_fallback.jsonl")

        self.assertEqual(len(american_trf), 20)
        self.assertEqual(len(british_trf), 20)
        self.assertEqual(len({case["caseId"] for case in american_trf}), 20)

        for small_case, transformer_case in zip(
            american_small, american_trf
        ):
            self.assertIs(transformer_case["options"].pop("trf"), True)
            self.assertEqual(transformer_case, small_case)
        for small_case, transformer_case in zip(british_small, british_trf):
            self.assertIs(transformer_case["options"].pop("trf"), True)
            self.assertEqual(transformer_case, small_case)

        for american_case, british_case in zip(american_trf, british_trf):
            self.assertEqual(
                american_case.pop("mode"), "american-espeak-fallback"
            )
            self.assertEqual(
                british_case.pop("mode"), "british-espeak-fallback"
            )
            self.assertEqual(british_case, american_case)

    def test_adversarial_corpora_are_mode_only_dialect_twins(self):
        american = self.records(
            "en_american_no_fallback_adversarial.jsonl"
        )
        british = self.records(
            "en_british_no_fallback_adversarial.jsonl"
        )

        self.assertEqual(len(american), 21)
        self.assertEqual(len(british), 21)
        self.assertEqual(len({case["caseId"] for case in american}), 21)
        self.assertTrue(
            all(case["caseId"].startswith("adv-") for case in american)
        )
        for american_case, british_case in zip(american, british):
            self.assertEqual(
                american_case.pop("mode"), "american-no-fallback"
            )
            self.assertEqual(
                british_case.pop("mode"), "british-no-fallback"
            )
            self.assertEqual(british_case, american_case)

    def test_transformer_lock_is_the_exact_curated_model_delta(self):
        def requirements(name):
            return {
                line
                for line in (Path("tool/reference") / name)
                .read_text(encoding="utf-8")
                .splitlines()
                if line and not line.startswith("#")
            }

        small = requirements("requirements-en-no-fallback-py312.txt")
        transformer = requirements("requirements-en-trf-py312.txt")
        small_model = next(
            line for line in small if line.startswith("en-core-web-sm @ ")
        )
        transformer_model = (
            "en-core-web-trf @ "
            "https://github.com/explosion/spacy-models/releases/download/"
            "en_core_web_trf-3.8.0/"
            "en_core_web_trf-3.8.0-py3-none-any.whl"
            "#sha256=272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5"
        )
        self.assertEqual(
            transformer,
            (small - {small_model})
            | {
                "curated-tokenizers==0.0.9",
                "curated-transformers==0.1.1",
                "spacy-curated-transformers==0.3.0",
                transformer_model,
            },
        )

    def test_transformer_espeak_lock_is_the_exact_combined_delta(self):
        def requirements(name):
            return {
                line
                for line in (Path("tool/reference") / name)
                .read_text(encoding="utf-8")
                .splitlines()
                if line and not line.startswith("#")
            }

        small_espeak = requirements("requirements-en-espeak-py312.txt")
        transformer_espeak = requirements(
            "requirements-en-trf-espeak-py312.txt"
        )
        small_include = "-r requirements-en-no-fallback-py312.txt"
        transformer_include = "-r requirements-en-trf-py312.txt"
        self.assertEqual(
            transformer_espeak,
            (small_espeak - {small_include}) | {transformer_include},
        )
        self.assertIn("joblib==1.4.2", transformer_espeak)
        self.assertNotIn("joblib==1.4.0", transformer_espeak)


class KoreanG2pkcModeTests(unittest.TestCase):
    @staticmethod
    def make_runner_without_checkout():
        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        return runner

    @staticmethod
    def make_case(text="한국어"):
        return reference.FixtureCase(
            language="ko",
            mode="g2pkc-default",
            options={},
            input_text=text,
        )

    def test_cached_default_engine_captures_one_mecab_call_per_case(self):
        constructed = []

        class FakeMecab:
            def __init__(self):
                self.calls = 0

            def pos(self, text):
                self.calls += 1
                return [(text, "NNG"), ("를", "JKO")]

        analyzer = FakeMecab()
        cmu = {"game": [["G", "EY1", "M"]]}

        class FakeKOG2P:
            def __init__(self):
                self.g2pk = SimpleNamespace(mecab=analyzer, cmu=cmu)
                constructed.append(self)

            def __call__(self, text):
                key = "game" if text == "한국어" else "missing"
                if key in self.g2pk.cmu:
                    self.g2pk.cmu[key][0]
                tokens = self.g2pk.mecab.pos("정규화:" + text)
                tokens[0] = ("mutated after analysis", "UNKNOWN")
                return "한국어", None

        module = SimpleNamespace(KOG2P=FakeKOG2P)
        download_calls = []

        def original_download(*args, **kwargs):
            download_calls.append((args, kwargs))

        nltk = SimpleNamespace(download=original_download)

        def import_module(name):
            return {"misaki.ko": module, "nltk": nltk}[name]

        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_import_upstream_module", side_effect=import_module
        ), mock.patch.object(
            reference,
            "_require_nltk_cmudict_resource",
            return_value=reference.NLTK_CMUDICT_IDENTITY,
        ):
            first = runner.run(self.make_case("한국어"))
            second = runner.run(self.make_case("한글"))

        self.assertIsInstance(first, reference.ReferenceResult)
        self.assertIsInstance(second, reference.ReferenceResult)
        self.assertEqual(len(constructed), 1)
        self.assertEqual(analyzer.calls, 2)
        self.assertEqual(download_calls, [])
        self.assertIs(nltk.download, original_download)
        self.assertIs(constructed[0].g2pk.mecab, analyzer)
        self.assertIs(constructed[0].g2pk.cmu, cmu)
        self.assertIsNone(first.tokens)
        self.assertEqual(
            first.backend_input,
            {
                "cmuLookups": [
                    {"arpabet": ["G", "EY1", "M"], "key": "game"}
                ],
                "input": "정규화:한국어",
                "kind": reference.KOREAN_BACKEND_INPUT_KIND,
                "schemaVersion": reference.KOREAN_BACKEND_INPUT_SCHEMA_VERSION,
                "tokens": [
                    {"surface": "정규화:한국어", "tag": "NNG"},
                    {"surface": "를", "tag": "JKO"},
                ],
            },
        )
        self.assertEqual(
            second.backend_input["cmuLookups"],
            [{"arpabet": None, "key": "missing"}],
        )

    def test_backend_replay_schema_rejects_untyped_values(self):
        replay = reference.serialize_korean_backend_input(
            "한국어를",
            [("한국어", "NNG"), ("를", "JKO")],
            [
                {"arpabet": ["G", "EY1", "M"], "key": "game"},
                {"arpabet": None, "key": "missing"},
            ],
        )
        self.assertEqual(replay["kind"], reference.KOREAN_BACKEND_INPUT_KIND)
        self.assertEqual(
            replay["tokens"],
            [
                {"surface": "한국어", "tag": "NNG"},
                {"surface": "를", "tag": "JKO"},
            ],
        )
        self.assertEqual(
            replay["cmuLookups"],
            [
                {"arpabet": ["G", "EY1", "M"], "key": "game"},
                {"arpabet": None, "key": "missing"},
            ],
        )

        for invalid in (
            [["한국어", "NNG"]],
            [("한국어",)],
            [("한국어", 1)],
        ):
            with self.assertRaises(reference.InvalidResult):
                reference.serialize_korean_backend_input("한국어", invalid, [])

        for invalid in (
            None,
            [{"key": "game"}],
            [{"arpabet": [], "key": "game"}],
            [{"arpabet": ["G", 1], "key": "game"}],
            [{"arpabet": None, "key": "Game"}],
            [{"arpabet": None, "key": "한글"}],
        ):
            with self.assertRaises(reference.InvalidResult):
                reference.serialize_korean_backend_input("한국어", [], invalid)

    def test_runtime_nltk_download_is_blocked_and_restored(self):
        calls = []

        def original_download(*args, **kwargs):
            calls.append((args, kwargs))

        nltk = SimpleNamespace(download=original_download)

        def import_module(name):
            if name == "nltk":
                return nltk
            nltk.download("cmudict")
            raise AssertionError("the download guard must raise first")

        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_import_upstream_module", side_effect=import_module
        ), mock.patch.object(
            reference,
            "_require_nltk_cmudict_resource",
            return_value=reference.NLTK_CMUDICT_IDENTITY,
        ):
            with self.assertRaises(reference.BackendUnavailable):
                runner.run(self.make_case())

        self.assertEqual(calls, [])
        self.assertIs(nltk.download, original_download)

    def test_missing_cmudict_is_a_stable_backend_failure(self):
        runner = self.make_runner_without_checkout()
        nltk = SimpleNamespace(download=lambda *_args, **_kwargs: None)
        with mock.patch.object(
            reference, "_import_upstream_module", return_value=nltk
        ), mock.patch.object(
            reference,
            "_require_nltk_cmudict_resource",
            side_effect=reference.BackendUnavailable("missing cmudict"),
        ):
            record = reference.build_fixture_record(
                self.make_case(), runner.run, version_provider=lambda _case: {}
            )

        self.assertEqual(record["error"], {"category": "backendUnavailable"})
        self.assertIsNone(record["phonemes"])
        self.assertIsNone(record["tokens"])

    def test_ambiguous_default_mode_is_not_supported(self):
        case = reference.FixtureCase(
            language="ko", mode="default", options={}, input_text="한국어"
        )
        with self.assertRaises(reference.UnsupportedMode):
            self.make_runner_without_checkout().run(case)


class KoreanG2pkcCorpusTests(unittest.TestCase):
    @classmethod
    def cases(cls):
        cases_directory = Path(__file__).resolve().parents[1] / "cases"
        return reference.read_cases(cases_directory / "ko_g2pkc_default.jsonl")

    def test_corpus_is_one_exact_34_case_mode(self):
        cases = self.cases()

        self.assertEqual(len(cases), 34)
        self.assertEqual(len({case.case_id for case in cases}), 34)
        self.assertEqual({case.language for case in cases}, {"ko"})
        self.assertEqual({case.mode for case in cases}, {"g2pkc-default"})
        self.assertEqual({tuple(case.options.items()) for case in cases}, {()})

    def test_expansion_covers_missing_source_branches(self):
        by_id = {case.case_id: case for case in self.cases()}
        required = {
            "idiom-order-units",
            "pos-sensitive-batchim",
            "palatalization-ui",
            "numeral-place-limit",
            "unicode-decimal-digits",
            "counter-boundaries",
            "english-arpabet-branches",
            "english-overlap-case",
            "numeral-set-order",
            "english-adjacent-vowels",
        }
        self.assertTrue(required.issubset(by_id))

        self.assertIn(
            "10,000,000,000,000,000",
            by_id["numeral-place-limit"].input_text,
        )
        self.assertIn("١٢٣", by_id["unicode-decimal-digits"].input_text)
        self.assertIn("𝟙𝟚𝟛", by_id["unicode-decimal-digits"].input_text)
        self.assertIn("1번째", by_id["idiom-order-units"].input_text)
        self.assertIn("3·1절", by_id["idiom-order-units"].input_text)

        english_words = by_id["english-arpabet-branches"].input_text.split()
        self.assertEqual(len(english_words), 8)
        self.assertEqual(len({len(word) for word in english_words}), 8)
        self.assertEqual(
            by_id["english-overlap-case"].input_text,
            "cat scatter Game GAME game friendship",
        )
        self.assertEqual(
            by_id["numeral-set-order"].input_text,
            "1개 1 3개 30개 3 30 3 개 10 100 106 1006",
        )
        self.assertEqual(
            by_id["english-adjacent-vowels"].input_text,
            "abbreviate abiola",
        )


class ChineseOracleModeTests(unittest.TestCase):
    @staticmethod
    def make_runner_without_checkout():
        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        return runner

    @staticmethod
    def make_case(mode="legacy", text="你好", options=None):
        return reference.FixtureCase(
            language="zh",
            mode=mode,
            options={} if options is None else options,
            input_text=text,
        )

    def test_legacy_captures_normalization_segmentation_and_tone3_pinyin(self):
        class Style:
            TONE3 = object()

        normalization_calls = []

        def transform(text, mode):
            normalization_calls.append((text, mode))
            return "两只猫"

        lcut_calls = []

        def lcut(text, cut_all):
            lcut_calls.append((text, cut_all))
            return ["两只", "猫"]

        pinyin_calls = []

        def lazy_pinyin(text, *, style, neutral_tone_with_five):
            pinyin_calls.append((text, style, neutral_tone_with_five))
            return {"两只": ["liang3", "zhi1"], "猫": ["mao1"]}[text]

        cn2an = SimpleNamespace(transform=transform)
        jieba = SimpleNamespace(lcut=lcut)
        constructed = []

        class FakeZHG2P:
            def __init__(self, **kwargs):
                constructed.append(kwargs)

            def __call__(self, text):
                if not text.strip():
                    return "", None
                normalized = cn2an.transform(text, "an2cn")
                output = []
                for word in jieba.lcut(normalized, cut_all=False):
                    values = module.lazy_pinyin(
                        word,
                        style=Style.TONE3,
                        neutral_tone_with_five=True,
                    )
                    output.extend(values)
                    values[0] = "mutated downstream"
                return " ".join(output), None

        module = SimpleNamespace(
            Style=Style,
            ZHG2P=FakeZHG2P,
            cn2an=cn2an,
            jieba=jieba,
            lazy_pinyin=lazy_pinyin,
        )
        runner = self.make_runner_without_checkout()
        original_functions = (cn2an.transform, jieba.lcut, module.lazy_pinyin)
        with mock.patch.object(
            reference, "_require_python_312"
        ), mock.patch.object(
            reference, "_require_chinese_dependency_versions"
        ), mock.patch.object(
            reference,
            "_require_jieba_default_dict_resource",
            return_value=reference.JIEBA_DEFAULT_DICT_IDENTITY,
        ), mock.patch.object(
            reference, "_import_upstream_module", return_value=module
        ):
            result = runner.run(self.make_case(text="2只猫"))
            empty = runner.run(self.make_case(text="\u3000\n"))

        self.assertEqual(len(constructed), 1)
        self.assertEqual(normalization_calls, [("2只猫", "an2cn")])
        self.assertEqual(lcut_calls, [("两只猫", False)])
        self.assertEqual([call[0] for call in pinyin_calls], ["两只", "猫"])
        self.assertIsNone(result.tokens)
        self.assertEqual(
            result.backend_input["normalization"],
            {"input": "2只猫", "mode": "an2cn", "output": "两只猫"},
        )
        self.assertEqual(
            result.backend_input["runs"],
            [
                {
                    "input": "两只猫",
                    "words": [
                        {
                            "pinyin": {
                                "input": "两只",
                                "kind": "pypinyin.lazy_pinyin",
                                "neutralToneWithFive": True,
                                "output": ["liang3", "zhi1"],
                                "stage": "legacy-word",
                                "style": "tone3",
                            },
                            "word": "两只",
                        },
                        {
                            "pinyin": {
                                "input": "猫",
                                "kind": "pypinyin.lazy_pinyin",
                                "neutralToneWithFive": True,
                                "output": ["mao1"],
                                "stage": "legacy-word",
                                "style": "tone3",
                            },
                            "word": "猫",
                        },
                    ],
                }
            ],
        )
        self.assertIsNone(empty.backend_input["normalization"])
        self.assertEqual(empty.backend_input["runs"], [])
        self.assertIs(cn2an.transform, original_functions[0])
        self.assertIs(jieba.lcut, original_functions[1])
        self.assertIs(module.lazy_pinyin, original_functions[2])

    def test_frontend_captures_each_pos_pinyin_and_search_boundary_in_order(self):
        class Style:
            INITIALS = object()
            FINALS_TONE3 = object()

        def transform(text, mode):
            self.assertEqual(mode, "an2cn")
            return text.replace("2", "二")

        def posseg_lcut(text):
            return [(text, "v")]

        def tone_lazy_pinyin(text, *, neutral_tone_with_five, style):
            self.assertTrue(neutral_tone_with_five)
            self.assertIs(style, Style.FINALS_TONE3)
            return ["u4", "a4"]

        def frontend_lazy_pinyin(text, *, neutral_tone_with_five, style):
            self.assertTrue(neutral_tone_with_five)
            if style is Style.INITIALS:
                return ["b", "p"]
            self.assertIs(style, Style.FINALS_TONE3)
            return ["u4", "a4"]

        def cut_for_search(text):
            return iter([text[:1], text[1:]])

        cn2an = SimpleNamespace(transform=transform)
        module_jieba = SimpleNamespace()
        psg = SimpleNamespace(lcut=posseg_lcut)
        tone_jieba = SimpleNamespace(cut_for_search=cut_for_search)
        frontend_module = SimpleNamespace(
            Style=Style, lazy_pinyin=frontend_lazy_pinyin, psg=psg
        )
        tone_module = SimpleNamespace(
            Style=Style, jieba=tone_jieba, lazy_pinyin=tone_lazy_pinyin
        )
        constructed = []

        class FakeZHG2P:
            def __init__(self, **kwargs):
                constructed.append(kwargs)

            @staticmethod
            def frontend(text):
                segments = frontend_module.psg.lcut(text)
                for word, _pos in segments:
                    premerge = tone_module.lazy_pinyin(
                        word,
                        neutral_tone_with_five=True,
                        style=Style.FINALS_TONE3,
                    )
                    list(tone_module.jieba.cut_for_search(word))
                    frontend_module.lazy_pinyin(
                        word,
                        neutral_tone_with_five=True,
                        style=Style.INITIALS,
                    )
                    finals = frontend_module.lazy_pinyin(
                        word,
                        neutral_tone_with_five=True,
                        style=Style.FINALS_TONE3,
                    )
                    premerge[0] = "mutated downstream"
                    finals[0] = "mutated downstream"

            def __call__(self, text):
                if not text.strip():
                    return "", None
                normalized = cn2an.transform(text, "an2cn")
                for chinese in normalized.split("ABC"):
                    if chinese:
                        self.frontend(chinese)
                return "captured", None

        module = SimpleNamespace(
            ZHG2P=FakeZHG2P, cn2an=cn2an, jieba=module_jieba
        )

        def import_module(name):
            return {
                "misaki.zh": module,
                "misaki.zh_frontend": frontend_module,
                "misaki.tone_sandhi": tone_module,
            }[name]

        runner = self.make_runner_without_checkout()
        originals = (
            cn2an.transform,
            psg.lcut,
            frontend_module.lazy_pinyin,
            tone_module.lazy_pinyin,
            tone_jieba.cut_for_search,
        )
        with mock.patch.object(
            reference, "_require_python_312"
        ), mock.patch.object(
            reference, "_require_chinese_dependency_versions"
        ), mock.patch.object(
            reference,
            "_require_jieba_default_dict_resource",
            return_value=reference.JIEBA_DEFAULT_DICT_IDENTITY,
        ), mock.patch.object(
            reference, "_import_upstream_module", side_effect=import_module
        ):
            result = runner.run(
                self.make_case(mode="frontend-1.1", text="不怕ABC很好")
            )

        self.assertEqual(len(constructed), 1)
        self.assertIsNone(result.tokens)
        self.assertEqual(
            result.backend_input["kind"],
            reference.CHINESE_FRONTEND_BACKEND_INPUT_KIND,
        )
        calls = result.backend_input["frontendCalls"]
        self.assertEqual([call["input"] for call in calls], ["不怕", "很好"])
        self.assertEqual(calls[0]["segmentation"], [{"pos": "v", "word": "不怕"}])
        self.assertEqual(
            [call["kind"] for call in calls[0]["externalCalls"]],
            [
                "pypinyin.lazy_pinyin",
                "jieba.cut_for_search",
                "pypinyin.lazy_pinyin",
                "pypinyin.lazy_pinyin",
            ],
        )
        self.assertEqual(
            calls[0]["externalCalls"][0]["output"], ["u4", "a4"]
        )
        self.assertEqual(
            calls[0]["externalCalls"][-1]["output"], ["u4", "a4"]
        )
        self.assertEqual(
            [
                call.get("style")
                for call in calls[0]["externalCalls"]
                if call["kind"] == "pypinyin.lazy_pinyin"
            ],
            ["finals-tone3", "initials", "finals-tone3"],
        )
        self.assertIs(cn2an.transform, originals[0])
        self.assertIs(psg.lcut, originals[1])
        self.assertIs(frontend_module.lazy_pinyin, originals[2])
        self.assertIs(tone_module.lazy_pinyin, originals[3])
        self.assertIs(tone_jieba.cut_for_search, originals[4])

    def test_chinese_serializers_reject_untyped_or_drifted_values(self):
        self.assertEqual(
            reference.serialize_chinese_posseg("你好", [("你好", "l")]),
            {"input": "你好", "segments": [{"pos": "l", "word": "你好"}]},
        )
        for invalid in (["你好"], [("你好",)], [("你好", 1)]):
            with self.assertRaises(reference.InvalidResult):
                reference.serialize_chinese_posseg("你好", invalid)
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_chinese_normalization("2", "cn2an", "二")
        with self.assertRaises(reference.InvalidResult):
            reference.serialize_chinese_pinyin_call(
                "你",
                ["ni3"],
                stage="legacy-word",
                style="tone3",
                neutral_tone_with_five=False,
            )

    def test_offline_guard_blocks_network_and_restores_stdlib(self):
        original_connect = reference.socket.socket.connect
        original_connect_ex = reference.socket.socket.connect_ex
        original_create_connection = reference.socket.create_connection
        original_urlopen = reference.urllib.request.urlopen

        with reference._offline_network_guard():
            with self.assertRaises(reference.BackendUnavailable):
                reference.socket.create_connection(("example.invalid", 443))
            with self.assertRaises(reference.BackendUnavailable):
                reference.urllib.request.urlopen("https://example.invalid")

        self.assertIs(reference.socket.socket.connect, original_connect)
        self.assertIs(reference.socket.socket.connect_ex, original_connect_ex)
        self.assertIs(reference.socket.create_connection, original_create_connection)
        self.assertIs(reference.urllib.request.urlopen, original_urlopen)

    def test_chinese_modes_require_python_312(self):
        with mock.patch.object(reference.sys, "version_info", (3, 11, 9)):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_python_312()

    def test_chinese_modes_require_every_exact_locked_dependency(self):
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: reference.CHINESE_FRONTEND_LOCKED_DISTRIBUTIONS[
                name
            ],
        ):
            reference._require_chinese_dependency_versions("frontend-1.1")
            reference._require_chinese_dependency_versions(
                "frontend-1.1-en-small-no-fallback"
            )

        with mock.patch.object(
            reference.importlib_metadata, "version", return_value="wrong"
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_chinese_dependency_versions("legacy")

    def test_chinese_english_callback_captures_and_validates_one_tokenize_call(self):
        token = FakeToken(
            text="ABC",
            tag="NNP",
            whitespace="",
            phonemes="ˌAbˌisˈi",
            start_ts=None,
            end_ts=None,
            _={"is_head": True, "num_flags": "", "prespace": False},
        )

        class FakeEnglishEngine:
            def tokenize(self, text, source_words, features):
                self.assertions = (text, source_words, features)
                return [token]

            def __call__(self, text, *, preprocess):
                self.preprocess = preprocess
                tokens = self.tokenize(text, [text], {})
                return "ˌAbˌisˈi", tokens

        engine = FakeEnglishEngine()
        callback = reference._CapturingChineseEnglishCallback(engine)
        callback.begin()
        self.assertEqual(callback("ABC"), "ˌAbˌisˈi")
        calls = callback.finish(["ABC"])

        self.assertTrue(engine.preprocess)
        self.assertEqual(engine.assertions, ("ABC", ["ABC"], {}))
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["input"], "ABC")
        self.assertEqual(calls[0]["phonemes"], "ˌAbˌisˈi")
        self.assertEqual(
            calls[0]["backendInput"]["kind"],
            reference.ENGLISH_BACKEND_INPUT_KIND,
        )
        self.assertEqual(calls[0]["tokens"][0]["text"], "ABC")

        callback.begin()
        with self.assertRaises(reference.InvalidResult):
            callback(123)
        callback.abort()

        callback.begin()
        callback("ABC")
        with self.assertRaises(reference.InvalidResult):
            callback.finish(["different"])

    def test_backend_versions_record_locked_closure_and_resource_identity(self):
        installed = {
            "addict": "2.4.0",
            "cn2an": "0.5.23",
            "jieba": "0.42.1",
            "ordered-set": "4.1.0",
            "proces": "0.1.7",
            "pypinyin": "0.53.0",
            "pypinyin-dict": "0.9.0",
            "regex": "2024.11.6",
        }
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ), mock.patch.object(
            reference.importlib, "import_module", return_value=SimpleNamespace()
        ), mock.patch.object(
            reference,
            "_jieba_default_dict_sha256",
            return_value=reference.JIEBA_DEFAULT_DICT_SHA256,
        ), mock.patch.object(
            reference.platform, "python_version", return_value="3.12.11"
        ):
            versions = reference.backend_versions(
                self.make_case(mode="frontend-1.1")
            )

        self.assertEqual(
            versions,
            {
                **installed,
                "jieba-default-dict": reference.JIEBA_DEFAULT_DICT_IDENTITY,
                "python": "3.12.11",
            },
        )

    def test_callback_backend_versions_include_small_english_closure(self):
        installed = {
            **reference.CHINESE_FRONTEND_LOCKED_DISTRIBUTIONS,
            "en-core-web-sm": "3.8.0",
            "num2words": "0.5.14",
            "spacy": "3.8.4",
        }
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ), mock.patch.object(
            reference.importlib, "import_module", return_value=SimpleNamespace()
        ), mock.patch.object(
            reference,
            "_jieba_default_dict_sha256",
            return_value=reference.JIEBA_DEFAULT_DICT_SHA256,
        ), mock.patch.object(
            reference.platform, "python_version", return_value="3.12.11"
        ):
            versions = reference.backend_versions(
                self.make_case(
                    mode="frontend-1.1-en-small-no-fallback",
                    options={
                        "englishDialect": "american",
                        "englishVersion": None,
                    },
                )
            )

        self.assertEqual(
            versions,
            {
                **installed,
                "jieba-default-dict": reference.JIEBA_DEFAULT_DICT_IDENTITY,
                "python": "3.12.11",
            },
        )

    def test_ambiguous_frontend_mode_is_not_supported(self):
        with self.assertRaises(reference.UnsupportedMode):
            self.make_runner_without_checkout().run(
                self.make_case(mode="default")
            )


class ChineseCorpusTests(unittest.TestCase):
    @staticmethod
    def read(name):
        cases_directory = Path(__file__).resolve().parents[1] / "cases"
        return reference.read_cases(cases_directory / name)

    def test_legacy_and_frontend_contracts_are_separate_and_feature_complete(self):
        legacy = self.read("zh_legacy.jsonl")
        frontend = self.read("zh_frontend_1_1.jsonl")

        self.assertEqual(len(legacy), 24)
        self.assertEqual(len(frontend), 26)
        self.assertEqual({case.language for case in legacy + frontend}, {"zh"})
        self.assertEqual({case.mode for case in legacy}, {"legacy"})
        self.assertEqual({case.mode for case in frontend}, {"frontend-1.1"})

        legacy_ids = {case.case_id for case in legacy}
        self.assertTrue(
            {
                "empty",
                "whitespace-only",
                "traditional",
                "fullwidth",
                "polyphones",
                "mixed-english",
                "integer-date",
                "iso-date-time",
                "phone-number",
                "rare-han",
                "variation-selector",
            }
            <= legacy_ids
        )
        frontend_ids = {case.case_id for case in frontend}
        self.assertTrue(
            {
                "empty",
                "whitespace-only",
                "bu-sandhi",
                "yi-sandhi",
                "third-tone-sandhi",
                "neutral-tone",
                "reduplication",
                "must-erhua",
                "not-erhua",
                "polyphones-custom-dict",
                "mixed-english-no-engine",
                "all-english-no-engine",
                "integer-date",
                "iso-date-time-phone",
                "rare-han",
                "variation-selector",
            }
            <= frontend_ids
        )

    def test_frontend_english_callback_corpus_covers_fixed_option_matrix(self):
        cases = self.read("zh_frontend_1_1_en_small_no_fallback.jsonl")

        self.assertEqual(len(cases), 14)
        self.assertEqual({case.language for case in cases}, {"zh"})
        self.assertEqual(
            {case.mode for case in cases},
            {"frontend-1.1-en-small-no-fallback"},
        )
        self.assertEqual(
            {
                (
                    case.options["englishDialect"],
                    case.options["englishVersion"],
                )
                for case in cases
            },
            {
                ("american", None),
                ("american", "2.0"),
                ("british", None),
                ("british", "2.0"),
            },
        )
        self.assertTrue(
            {
                "english-only-american-legacy",
                "english-only-american-v2",
                "english-only-british-legacy",
                "english-only-british-v2",
                "multiple-mixed-segments",
                "punctuation-and-symbol-splitting",
                "apostrophe-and-hyphen",
                "english-context",
                "oov-default-unknown",
                "oov-custom-unknown",
                "fullwidth-ascii-boundary",
                "cn2an-number-boundary",
                "whitespace-only",
                "empty",
            }
            <= {case.case_id for case in cases}
        )


class VietnameseOracleModeTests(unittest.TestCase):
    @staticmethod
    def make_runner_without_checkout():
        runner = object.__new__(reference.UpstreamRunner)
        runner.root = Path("/validated-pinned-misaki")
        runner._engines = {}
        return runner

    @staticmethod
    def make_case(**overrides):
        values = {
            "language": "vi",
            "mode": "north-no-english-fallback",
            "options": {},
            "input_text": "Xin chào",
            "case_id": "greeting",
            "seed": None,
        }
        values.update(overrides)
        return reference.FixtureCase(**values)

    def test_captures_exact_cleaned_tokenizer_input_and_output_once(self):
        constructed = []
        module = SimpleNamespace()

        def tokenize(text):
            self.assertEqual(text, "xin chào")
            return ["xin", "chào"]

        module.tokenize = tokenize

        class FakeVIG2P:
            def __init__(self, **kwargs):
                self.kwargs = kwargs
                self.calls = []
                constructed.append(self)

            def __call__(self, text):
                self.calls.append(text)
                module.tokenize("xin chào")
                return "sin1 caw2", ["token"]

        module.VIG2P = FakeVIG2P
        runner = self.make_runner_without_checkout()
        original_tokenize = module.tokenize
        with mock.patch.object(
            reference, "_require_python_311"
        ) as require_python, mock.patch.object(
            reference, "_require_vietnamese_dependency_versions"
        ) as require_dependencies, mock.patch.object(
            reference,
            "_import_vietnamese_no_english_module",
            return_value=module,
        ):
            first = runner.run(self.make_case())
            second = runner.run(
                self.make_case(input_text="XIN CHÀO", case_id="uppercase")
            )

        self.assertEqual(len(constructed), 1)
        self.assertEqual(constructed[0].calls, ["Xin chào", "XIN CHÀO"])
        self.assertEqual(
            constructed[0].kwargs,
            {
                "cao": False,
                "clean_abbr": True,
                "clean_acronym": True,
                "dialect": "north",
                "enable_en_g2p": False,
                "en_g2p_kwargs": {},
                "glottal": False,
                "palatals": False,
                "pham": False,
                "substr_tokenize": True,
                "tone_type": 0,
            },
        )
        expected_backend = {
            "input": "xin chào",
            "kind": reference.VIETNAMESE_BACKEND_INPUT_KIND,
            "schemaVersion": reference.VIETNAMESE_BACKEND_INPUT_SCHEMA_VERSION,
            "tokens": ["xin", "chào"],
        }
        self.assertEqual(first.backend_input, expected_backend)
        self.assertEqual(second.backend_input, expected_backend)
        self.assertEqual(first.phonemes, "sin1 caw2")
        self.assertEqual(first.tokens, ["token"])
        self.assertIs(module.tokenize, original_tokenize)
        self.assertEqual(require_python.call_args_list, [mock.call("Vietnamese")] * 2)
        self.assertEqual(require_dependencies.call_count, 2)

    def test_tokenizer_capture_schema_rejects_type_and_empty_drift(self):
        self.assertEqual(
            reference.serialize_vietnamese_backend_input("xin", ["xin"]),
            {
                "input": "xin",
                "kind": reference.VIETNAMESE_BACKEND_INPUT_KIND,
                "schemaVersion": 1,
                "tokens": ["xin"],
            },
        )
        for text, tokens in ((1, ["xin"]), ("xin", ("xin",)), ("xin", [""])):
            with self.assertRaises(reference.InvalidResult):
                reference.serialize_vietnamese_backend_input(text, tokens)

    def test_modes_and_option_types_are_strict(self):
        runner = self.make_runner_without_checkout()
        with self.assertRaises(reference.UnsupportedMode):
            runner.run(self.make_case(mode="default"))
        with self.assertRaises(reference.InvalidOptions):
            runner.run(self.make_case(options={"fallback": False}))
        for name in (
            "cao",
            "clean_abbr",
            "clean_acronym",
            "glottal",
            "palatals",
            "pham",
            "substr_tokenize",
        ):
            with self.assertRaises(reference.InvalidOptions):
                runner.run(self.make_case(options={name: 1}))
        for value in (True, 1.5, "1"):
            with self.assertRaises(reference.InvalidOptions):
                runner.run(self.make_case(options={"tone_type": value}))

    def test_python_and_every_locked_dependency_are_preflighted_and_recorded(self):
        installed = dict(reference.VIETNAMESE_LOCKED_DISTRIBUTIONS)
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ), mock.patch.object(
            reference.platform, "python_version", return_value="3.11.13"
        ), mock.patch.object(
            reference.unicodedata, "unidata_version", "14.0.0"
        ):
            reference._require_vietnamese_dependency_versions()
            versions = reference.backend_versions(self.make_case())

        self.assertEqual(
            versions,
            {
                **installed,
                "python": "3.11.13",
                "unicode-data": "14.0.0",
            },
        )

        installed["underthesea"] = "6.9.0"
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_vietnamese_dependency_versions()

        with mock.patch.object(reference.sys, "version_info", (3, 12, 11)):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_python_311("Vietnamese")


class VietnameseCorpusTests(unittest.TestCase):
    @staticmethod
    def read(name):
        cases_directory = Path(__file__).resolve().parents[1] / "cases"
        return reference.read_cases(cases_directory / name)

    def test_three_dialect_corpora_change_only_the_requested_mode(self):
        names = {
            "north-no-english-fallback": "vi_north_no_english_fallback.jsonl",
            "central-no-english-fallback": "vi_central_no_english_fallback.jsonl",
            "south-no-english-fallback": "vi_south_no_english_fallback.jsonl",
        }
        corpora = {mode: self.read(name) for mode, name in names.items()}
        self.assertEqual({len(cases) for cases in corpora.values()}, {33})
        north = corpora["north-no-english-fallback"]
        for mode, cases in corpora.items():
            for baseline, candidate in zip(north, cases):
                self.assertEqual(candidate.language, "vi")
                self.assertEqual(candidate.mode, mode)
                self.assertEqual(candidate.case_id, baseline.case_id)
                self.assertEqual(candidate.options, baseline.options)
                self.assertEqual(candidate.input_text, baseline.input_text)

    def test_corpus_covers_options_cleaning_controls_and_unicode(self):
        cases = self.read("vi_north_no_english_fallback.jsonl")
        by_id = {case.case_id: case for case in cases}
        self.assertTrue(
            {
                "empty",
                "whitespace-only",
                "dialect-finals",
                "six-tones",
                "substring-names",
                "substring-disabled",
                "custom-pronunciation",
                "abbreviations-on",
                "abbreviations-off",
                "acronyms-on",
                "acronyms-off",
                "numbers-and-phone",
                "currency-and-measurement",
                "date-and-time",
                "cao-tone-type",
                "pham-forced-with-cao",
                "cao-forced-with-pham",
                "glottal",
                "palatals",
                "decomposed-unicode",
                "unicode15-ccc-deltas",
                "full-width-forms",
                "emoji",
                "variation-selector",
                "foreign-no-fallback",
            }.issubset(by_id)
        )
        self.assertIn("\u0323", by_id["decomposed-unicode"].input_text)
        unicode15_case = by_id["unicode15-ccc-deltas"].input_text
        for code_point in (
            0x10EFD,
            0x10EFE,
            0x10EFF,
            0x11F41,
            0x11F42,
            0x1E08F,
            0x1E4EC,
            0x1E4ED,
            0x1E4EE,
            0x1E4EF,
        ):
            self.assertIn(chr(code_point), unicode15_case)
        self.assertIn("\ufe0f", by_id["variation-selector"].input_text)


class HebrewModeTests(unittest.TestCase):
    @staticmethod
    def make_runner_without_checkout():
        runner = object.__new__(reference.UpstreamRunner)
        runner._engines = {}
        return runner

    @staticmethod
    def make_case(**overrides):
        values = {
            "language": "he",
            "mode": "default",
            "options": {},
            "input_text": "שָׁלוֹם",
            "case_id": "shalom",
            "seed": None,
        }
        values.update(overrides)
        return reference.FixtureCase(**values)

    def test_cached_engine_receives_exact_text_and_preservation_flags(self):
        constructed = []

        class FakeHEG2P:
            def __init__(self):
                self.calls = []
                constructed.append(self)

            def __call__(
                self, text, *, preserve_punctuation, preserve_stress
            ):
                self.calls.append(
                    (text, preserve_punctuation, preserve_stress)
                )
                return "ʃalˈom" if preserve_stress else "ʃalom"

        module = SimpleNamespace(HEG2P=FakeHEG2P)
        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_require_python_312"
        ) as require_python, mock.patch.object(
            reference, "_require_hebrew_dependency_versions"
        ) as require_dependencies, mock.patch.object(
            reference, "_import_upstream_module", return_value=module
        ):
            default = runner.run(self.make_case())
            unstressed = runner.run(
                self.make_case(
                    options={
                        "preserve_punctuation": False,
                        "preserve_stress": False,
                    }
                )
            )

        self.assertEqual(default, "ʃalˈom")
        self.assertEqual(unstressed, "ʃalom")
        self.assertEqual(len(constructed), 1)
        self.assertEqual(
            constructed[0].calls,
            [
                ("שָׁלוֹם", True, True),
                ("שָׁלוֹם", False, False),
            ],
        )
        self.assertEqual(
            require_python.call_args_list,
            [mock.call("Hebrew"), mock.call("Hebrew")],
        )
        self.assertEqual(require_dependencies.call_count, 2)

    def test_default_result_has_no_tokens_or_backend_input(self):
        module = SimpleNamespace(HEG2P=lambda: lambda _text, **_kwargs: "ʃalˈom")
        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_require_python_312"
        ), mock.patch.object(
            reference, "_require_hebrew_dependency_versions"
        ), mock.patch.object(
            reference, "_import_upstream_module", return_value=module
        ):
            record = reference.build_fixture_record(
                self.make_case(), runner.run, version_provider=lambda _case: {}
            )

        self.assertEqual(record["phonemes"], "ʃalˈom")
        self.assertIsNone(record["tokens"])
        self.assertNotIn("backendInput", record)

    def test_non_string_backend_result_is_rejected(self):
        module = SimpleNamespace(
            HEG2P=lambda: lambda _text, **_kwargs: ("ʃalˈom", None)
        )
        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_require_python_312"
        ), mock.patch.object(
            reference, "_require_hebrew_dependency_versions"
        ), mock.patch.object(
            reference, "_import_upstream_module", return_value=module
        ):
            with self.assertRaises(reference.InvalidResult):
                runner.run(self.make_case())

    def test_import_initialization_and_conversion_are_network_guarded(self):
        class NetworkHEG2P:
            def __init__(self):
                reference.socket.create_connection(("example.invalid", 443))

        runner = self.make_runner_without_checkout()
        with mock.patch.object(
            reference, "_require_python_312"
        ), mock.patch.object(
            reference, "_require_hebrew_dependency_versions"
        ), mock.patch.object(
            reference,
            "_import_upstream_module",
            return_value=SimpleNamespace(HEG2P=NetworkHEG2P),
        ):
            with self.assertRaises(reference.BackendUnavailable):
                runner.run(self.make_case())

    def test_mode_options_and_boolean_types_are_strict(self):
        runner = self.make_runner_without_checkout()
        with self.assertRaises(reference.UnsupportedMode):
            runner.run(self.make_case(mode="legacy"))
        with self.assertRaises(reference.InvalidOptions):
            runner.run(self.make_case(options={"fallback": True}))
        for name in ("preserve_punctuation", "preserve_stress"):
            with self.assertRaises(reference.InvalidOptions):
                runner.run(self.make_case(options={name: 1}))

    def test_python_and_every_locked_dependency_are_preflighted_and_recorded(self):
        installed = dict(reference.HEBREW_LOCKED_DISTRIBUTIONS)
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ), mock.patch.object(
            reference.platform, "python_version", return_value="3.12.11"
        ):
            reference._require_hebrew_dependency_versions()
            versions = reference.backend_versions(self.make_case())

        self.assertEqual(versions, {**installed, "python": "3.12.11"})

        installed["mishkal-hebrew"] = "0.3.7"
        with mock.patch.object(
            reference.importlib_metadata,
            "version",
            side_effect=lambda name: installed[name],
        ):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_hebrew_dependency_versions()

        with mock.patch.object(reference.sys, "version_info", (3, 11, 9)):
            with self.assertRaises(reference.BackendUnavailable):
                reference._require_python_312("Hebrew")


class HebrewCorpusTests(unittest.TestCase):
    @classmethod
    def cases(cls):
        cases_directory = Path(__file__).resolve().parents[1] / "cases"
        return reference.read_cases(cases_directory / "he_default.jsonl")

    def test_corpus_is_one_explicit_mode_with_complete_option_matrix(self):
        cases = self.cases()

        self.assertEqual(len(cases), 28)
        self.assertEqual({case.language for case in cases}, {"he"})
        self.assertEqual({case.mode for case in cases}, {"default"})
        self.assertEqual(
            {tuple(sorted(case.options.items())) for case in cases},
            {
                (),
                (("preserve_punctuation", False),),
                (("preserve_stress", False),),
                (
                    ("preserve_punctuation", False),
                    ("preserve_stress", False),
                ),
                (("preserve_punctuation", True),),
                (("preserve_stress", True),),
            },
        )

    def test_corpus_covers_documented_rules_and_unicode_adversaries(self):
        cases = self.cases()
        by_id = {case.case_id: case for case in cases}

        self.assertTrue(
            {
                "empty",
                "whitespace-only",
                "documented-hello-world",
                "shalom-unpointed",
                "all-basic-vowels",
                "shin-and-sin",
                "dagesh-rafe",
                "final-forms",
                "quotes-geresh-gershayim",
                "cantillation",
                "explicit-hatama",
                "explicit-vocal-shva",
                "numbers",
                "date",
                "mixed-latin",
                "emoji",
                "variation-selector",
                "combining-order",
                "unknown-symbols",
            }.issubset(by_id)
        )
        self.assertIn("\u05ab", by_id["explicit-hatama"].input_text)
        self.assertIn("\u05bd", by_id["explicit-vocal-shva"].input_text)
        self.assertIn("\ufe0f", by_id["variation-selector"].input_text)

    def test_dependency_lock_pins_the_wheel_hash_and_complete_closure(self):
        lock = Path(__file__).resolve().parents[1] / "requirements-he-py312.txt"
        requirements = [
            line
            for raw_line in lock.read_text(encoding="utf-8").splitlines()
            if (line := raw_line.strip()) and not line.startswith("#")
        ]

        self.assertEqual(
            requirements,
            [
                'colorama==0.4.6 ; sys_platform == "win32"',
                "colorlog==6.9.0",
                "docopt==0.6.2",
                "mishkal-hebrew @ https://files.pythonhosted.org/packages/"
                "44/17/9efdef222f2fc8e1ca721d919738d69d8b2358554a99f27b0764905f60fd/"
                "mishkal_hebrew-0.3.2-py3-none-any.whl#sha256="
                "1b25dc61c2ac1ca2898c288adbd8d81399260fd4d82124bbce5f0d031c785997",
                "num2words==0.5.14",
            ],
        )


class UpstreamCheckoutTests(unittest.TestCase):
    @staticmethod
    def completed(returncode=0, stdout=""):
        return SimpleNamespace(returncode=returncode, stdout=stdout, stderr="")

    def test_accepts_clean_tracked_state_and_checks_both_diffs(self):
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            (root / "misaki").mkdir()
            (root / "misaki" / "token.py").touch()
            resolved_root = root.resolve()
            commands = []

            def run(command, **_kwargs):
                commands.append(command)
                if command[-2:] == ["rev-parse", "HEAD"]:
                    return self.completed(stdout=reference.UPSTREAM_COMMIT + "\n")
                return self.completed()

            with mock.patch.object(
                reference.subprocess, "run", side_effect=run
            ), mock.patch.object(
                reference,
                "_read_upstream_version",
                return_value=reference.UPSTREAM_VERSION,
            ):
                actual = reference.verify_upstream_checkout(root)

        self.assertEqual(actual, resolved_root)
        self.assertEqual(
            commands,
            [
                ["git", "-C", str(resolved_root), "rev-parse", "HEAD"],
                [
                    "git",
                    "-C",
                    str(resolved_root),
                    "diff",
                    "--quiet",
                    "HEAD",
                    "--",
                ],
                [
                    "git",
                    "-C",
                    str(resolved_root),
                    "diff",
                    "--cached",
                    "--quiet",
                    "HEAD",
                    "--",
                ],
            ],
        )

    def test_rejects_unstaged_or_staged_tracked_modifications(self):
        for dirty_call in (2, 3):
            with self.subTest(
                dirty_call=dirty_call
            ), tempfile.TemporaryDirectory() as directory_name:
                root = Path(directory_name)
                (root / "misaki").mkdir()
                (root / "misaki" / "token.py").touch()
                calls = 0

                def run(_command, **_kwargs):
                    nonlocal calls
                    calls += 1
                    if calls == 1:
                        return self.completed(stdout=reference.UPSTREAM_COMMIT + "\n")
                    return self.completed(returncode=1 if calls == dirty_call else 0)

                with mock.patch.object(
                    reference.subprocess, "run", side_effect=run
                ):
                    with self.assertRaisesRegex(
                        reference.UpstreamMismatch, "tracked modifications"
                    ):
                        reference.verify_upstream_checkout(root)

    def test_rejects_git_tracked_state_check_errors(self):
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            (root / "misaki").mkdir()
            (root / "misaki" / "token.py").touch()
            results = iter(
                (
                    self.completed(stdout=reference.UPSTREAM_COMMIT + "\n"),
                    self.completed(returncode=2),
                )
            )
            with mock.patch.object(
                reference.subprocess,
                "run",
                side_effect=lambda *_args, **_kwargs: next(results),
            ):
                with self.assertRaisesRegex(
                    reference.UpstreamMismatch, "tracked state"
                ):
                    reference.verify_upstream_checkout(root)


class InputAndFileTests(unittest.TestCase):
    def test_duplicate_json_key_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cases.jsonl"
            path.write_text(
                '{"language":"ja","language":"en","mode":"x","input":"x"}\n',
                encoding="utf-8",
            )
            with self.assertRaises(reference.InvalidInput):
                reference.read_cases(path)

    def test_duplicate_case_id_is_rejected(self):
        line = '{"caseId":"same","language":"ja","mode":"ja-num2kana","input":"0"}\n'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cases.jsonl"
            path.write_text(line + line, encoding="utf-8")
            with self.assertRaises(reference.InvalidInput):
                reference.read_cases(path)

    def test_overwrite_requires_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.jsonl"
            path.write_text("old\n", encoding="utf-8")
            with self.assertRaises(reference.AcceptanceRequired):
                reference.write_fixture(path, "new\n", accept=False)
            self.assertEqual(path.read_text(encoding="utf-8"), "old\n")

    def test_accepted_write_is_exact_utf8(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.jsonl"
            reference.write_fixture(path, "❓\n", accept=True)
            self.assertEqual(path.read_bytes(), "❓\n".encode("utf-8"))

    def test_verification_returns_human_readable_diff(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.jsonl"
            path.write_text("old\n", encoding="utf-8")
            matches, diff = reference.verify_fixture(path, "new\n")
            self.assertFalse(matches)
            self.assertIn("code-point offset 0", diff)
            self.assertIn("U+006F LATIN SMALL LETTER O", diff)
            self.assertIn("U+006E LATIN SMALL LETTER N", diff)
            self.assertIn("-old", diff)
            self.assertIn("+new", diff)

    def test_difference_reports_unicode_names_and_token_index(self):
        expected = reference.canonical_json_line(
            {"phonemes": "café", "tokens": [{"text": "ok"}, {"text": "é"}]}
        )
        actual = reference.canonical_json_line(
            {"phonemes": "cafe", "tokens": [{"text": "ok"}, {"text": "e"}]}
        )

        diagnostic = reference.first_difference_diagnostic(expected, actual)

        self.assertIn("U+00E9 LATIN SMALL LETTER E WITH ACUTE", diagnostic)
        self.assertIn("U+0065 LATIN SMALL LETTER E", diagnostic)
        self.assertIn("JSON token index (zero-based): 1", diagnostic)

    def test_difference_describes_end_of_text(self):
        diagnostic = reference.first_difference_diagnostic("same", "same!")
        self.assertIn("expected: <end of text>", diagnostic)
        self.assertIn("actual:   U+0021 EXCLAMATION MARK", diagnostic)


if __name__ == "__main__":
    unittest.main()
