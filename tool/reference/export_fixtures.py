#!/usr/bin/env python3
"""Generate or verify deterministic JSONL fixtures against pinned Misaki.

The tool itself uses only the Python standard library. Language backends are
loaded lazily from an explicitly supplied checkout of the pinned upstream
repository, so dependency-free stages remain usable without installing the
full set of Misaki extras.
"""

from __future__ import annotations

import argparse
import ast
from collections.abc import Mapping
import copy
import contextlib
from dataclasses import dataclass, fields, is_dataclass
import difflib
from functools import lru_cache
import hashlib
import importlib
from importlib import metadata as importlib_metadata
import io
import json
import math
import os
import platform
from pathlib import Path
import random
import re
import socket
import subprocess
import sys
import tempfile
import types
import unicodedata
import urllib.request
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple


SCHEMA_VERSION = 1
UPSTREAM_REPOSITORY = "hexgrad/misaki"
UPSTREAM_COMMIT = "fba1236595f2d2bf21d414ba6e57d25256afada3"
UPSTREAM_VERSION = "0.9.4"
REQUIRED_HASH_SEED = "0"
MAX_DIFF_LINES = 200


class ReferenceToolError(Exception):
    """Base class for deterministic reference-tool failures."""

    category = "referenceToolError"


class InvalidInput(ReferenceToolError):
    category = "invalidInput"


class InvalidOptions(ReferenceToolError):
    category = "invalidOptions"


class UnsupportedLanguage(ReferenceToolError):
    category = "unsupportedLanguage"


class UnsupportedMode(ReferenceToolError):
    category = "unsupportedMode"


class BackendUnavailable(ReferenceToolError):
    category = "backendUnavailable"


class UpstreamMismatch(ReferenceToolError):
    category = "upstreamMismatch"


class InvalidResult(ReferenceToolError):
    category = "invalidResult"


class SerializationFailure(ReferenceToolError):
    category = "serializationFailure"


class AcceptanceRequired(ReferenceToolError):
    category = "acceptanceRequired"


class UpstreamExecutionFailure(ReferenceToolError):
    """Upstream failure that retains already-captured typed backend input."""

    category = "upstreamFailure"

    def __init__(self, cause: Exception, backend_input: Dict[str, Any]) -> None:
        super().__init__("{}: {}".format(type(cause).__name__, cause))
        self.cause = cause
        self.backend_input = backend_input


@dataclass(frozen=True)
class FixtureCase:
    """One requested upstream conversion."""

    language: str
    mode: str
    options: Dict[str, Any]
    input_text: str
    case_id: Optional[str] = None
    seed: Optional[int] = None


@dataclass(frozen=True)
class ReferenceResult:
    """Normalized upstream result with optional replayable backend input."""

    phonemes: str
    tokens: Optional[List[Any]]
    backend_input: Optional[Dict[str, Any]] = None


_PYOPENJTALK_FRONTEND_STRING_FIELDS = (
    "cform",
    "chain_rule",
    "ctype",
    "orig",
    "pos",
    "pos_group1",
    "pos_group2",
    "pos_group3",
    "pron",
    "read",
    "string",
)
_PYOPENJTALK_FRONTEND_INTEGER_FIELDS = ("acc", "chain_flag", "mora_size")
_PYOPENJTALK_FRONTEND_FIELDS = frozenset(
    _PYOPENJTALK_FRONTEND_STRING_FIELDS + _PYOPENJTALK_FRONTEND_INTEGER_FIELDS
)

CUTLET_BACKEND_INPUT_KIND = "misaki.cutlet.normalized-morphology"
CUTLET_BACKEND_INPUT_SCHEMA_VERSION = 1
CUTLET_JA_WORDS_SHA256 = (
    "a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff"
)
CUTLET_JA_WORDS_SIZE_BYTES = 1_921_140
CUTLET_JA_WORDS_RECORD_COUNT = 147_571
CUTLET_JA_WORDS_IDENTITY = "sha256:{}+bytes:{}+records:{}".format(
    CUTLET_JA_WORDS_SHA256,
    CUTLET_JA_WORDS_SIZE_BYTES,
    CUTLET_JA_WORDS_RECORD_COUNT,
)
CUTLET_UNIDIC_ARCHIVE_SHA256 = (
    "39ea0eae3b1f10ba8986483592cbc83bcc92f1898bb43ecbc607010f2e98cd22"
)
CUTLET_UNIDIC_ARCHIVE_SIZE_BYTES = 524_664_138
CUTLET_UNIDIC_VERSION_MARKER = "unidic-3.1.0+2021-08-31"
CUTLET_UNIDIC_TREE_SHA256 = (
    "95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115"
)
CUTLET_UNIDIC_TREE_FILE_COUNT = 20
CUTLET_UNIDIC_TREE_SIZE_BYTES = 811_662_881
CUTLET_UNIDIC_TREE_IDENTITY = "sha256:{}+files:{}+bytes:{}".format(
    CUTLET_UNIDIC_TREE_SHA256,
    CUTLET_UNIDIC_TREE_FILE_COUNT,
    CUTLET_UNIDIC_TREE_SIZE_BYTES,
)
CUTLET_UNIDIC_DICTIONARY_CHARSET = "utf8"
CUTLET_UNIDIC_DICTIONARY_ENTRY_COUNT = 878_989
CUTLET_UNIDIC_DICTIONARY_BINARY_VERSION = 102
CUTLET_UNIDIC_LIVE_DICTIONARY_IDENTITY = (
    "charset:{}+entries:{}+binary-version:{}".format(
        CUTLET_UNIDIC_DICTIONARY_CHARSET,
        CUTLET_UNIDIC_DICTIONARY_ENTRY_COUNT,
        CUTLET_UNIDIC_DICTIONARY_BINARY_VERSION,
    )
)
CUTLET_LOCKED_DISTRIBUTIONS = {
    "addict": "2.4.0",
    "certifi": "2025.1.31",
    "charset-normalizer": "3.4.1",
    "fugashi": "1.4.0",
    "idna": "3.10",
    "jaconv": "0.4.0",
    "mojimoji": "0.0.13",
    "numpy": "2.2.4",
    "plac": "1.4.5",
    "pyopenjtalk": "0.4.1",
    "requests": "2.32.3",
    "regex": "2024.11.6",
    "tqdm": "4.67.1",
    "unidic": "1.1.0",
    "urllib3": "2.3.0",
    "wasabi": "0.10.1",
}

ENGLISH_BACKEND_INPUT_KIND = "misaki.en.G2P.preprocess-tokenize"
ENGLISH_BACKEND_INPUT_SCHEMA_VERSION = 1
ENGLISH_ESPEAK_BACKEND_INPUT_SCHEMA_VERSION = 2
ENGLISH_MODEL_BACKEND_INPUT_SCHEMA_VERSION = 3
ENGLISH_ESPEAK_LOCKED_DISTRIBUTIONS = {
    "espeakng-loader": "0.2.4",
    "joblib": "1.4.2",
    "phonemizer-fork": "3.3.2",
}
ENGLISH_LOCKED_DISTRIBUTIONS = {
    "num2words": "0.5.14",
    "numpy": "2.2.4",
    "regex": "2024.11.6",
    "spacy": "3.8.4",
}
ENGLISH_TRANSFORMER_LOCKED_DISTRIBUTIONS = {
    "curated-tokenizers": "0.0.9",
    "curated-transformers": "0.1.1",
    "spacy-curated-transformers": "0.3.0",
}
ENGLISH_MODEL_VERSIONS = {
    False: ("en-core-web-sm", "3.8.0"),
    True: ("en-core-web-trf", "3.8.0"),
}
_ENGLISH_RAW_TOKEN_FIELDS = frozenset(
    ("_", "end_ts", "phonemes", "start_ts", "tag", "text", "whitespace")
)
_ENGLISH_RAW_METADATA_REQUIRED_FIELDS = frozenset(
    ("is_head", "num_flags", "prespace")
)
_ENGLISH_RAW_METADATA_OPTIONAL_FIELDS = frozenset(("rating", "stress"))
_ENGLISH_RAW_METADATA_FIELDS = (
    _ENGLISH_RAW_METADATA_REQUIRED_FIELDS | _ENGLISH_RAW_METADATA_OPTIONAL_FIELDS
)

KOREAN_BACKEND_INPUT_KIND = "python-mecab-ko.MeCab.pos"
KOREAN_BACKEND_INPUT_SCHEMA_VERSION = 2
NLTK_CMUDICT_VERSION = "0.7a"
NLTK_CMUDICT_SHA256 = (
    "d07cca47fd72ad32ea9d8ad1219f85301eeaf4568f8b6b73747506a71fb5afd6"
)
NLTK_CMUDICT_IDENTITY = "{}+sha256:{}".format(
    NLTK_CMUDICT_VERSION, NLTK_CMUDICT_SHA256
)

CHINESE_LEGACY_BACKEND_INPUT_KIND = "misaki.zh.legacy.external-stages"
CHINESE_FRONTEND_BACKEND_INPUT_KIND = (
    "misaki.zh.frontend-1.1.external-stages"
)
CHINESE_FRONTEND_ENGLISH_BACKEND_INPUT_KIND = (
    "misaki.zh.frontend-1.1-en-small-no-fallback.external-stages"
)
CHINESE_BACKEND_INPUT_SCHEMA_VERSION = 1
CHINESE_ENGLISH_BACKEND_INPUT_SCHEMA_VERSION = 2
JIEBA_DEFAULT_DICT_SHA256 = (
    "7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8"
)
JIEBA_DEFAULT_DICT_IDENTITY = "sha256:{}".format(JIEBA_DEFAULT_DICT_SHA256)
CHINESE_LOCKED_DISTRIBUTIONS = {
    "addict": "2.4.0",
    "cn2an": "0.5.23",
    "jieba": "0.42.1",
    "ordered-set": "4.1.0",
    "proces": "0.1.7",
    "pypinyin": "0.53.0",
    "regex": "2024.11.6",
}
CHINESE_FRONTEND_LOCKED_DISTRIBUTIONS = {
    **CHINESE_LOCKED_DISTRIBUTIONS,
    "pypinyin-dict": "0.9.0",
}

HEBREW_LOCKED_DISTRIBUTIONS = {
    "colorlog": "6.9.0",
    "docopt": "0.6.2",
    "mishkal-hebrew": "0.3.2",
    "num2words": "0.5.14",
}
HEBREW_WINDOWS_LOCKED_DISTRIBUTIONS = {"colorama": "0.4.6"}

VIETNAMESE_BACKEND_INPUT_KIND = "underthesea.pipeline.word_tokenize.tokenize"
VIETNAMESE_BACKEND_INPUT_SCHEMA_VERSION = 1
VIETNAMESE_LOCKED_DISTRIBUTIONS = {
    "addict": "2.4.0",
    "certifi": "2025.1.31",
    "charset-normalizer": "3.4.1",
    "click": "8.1.8",
    "idna": "3.10",
    "joblib": "1.4.2",
    "nltk": "3.9.1",
    "numpy": "2.2.4",
    "python-crfsuite": "0.9.11",
    "pyyaml": "6.0.2",
    "regex": "2024.11.6",
    "requests": "2.32.3",
    "scikit-learn": "1.6.1",
    "scipy": "1.15.2",
    "threadpoolctl": "3.6.0",
    "tqdm": "4.67.1",
    "underthesea": "6.8.4",
    "underthesea-core": "1.0.4",
    "urllib3": "2.3.0",
    # Latest vietnam-number release available at the pinned Misaki commit.
    # Misaki imports it but omits it from pyproject.toml and uv.lock.
    "vietnam-number": "1.0.3",
}


def serialize_pyopenjtalk_frontend(words: Any) -> Dict[str, Any]:
    """Validate and serialize the raw pyopenjtalk 0.4.1 NJD word stream."""

    if not isinstance(words, list):
        raise InvalidResult("pyopenjtalk.run_frontend must return a list")
    serialized: List[Dict[str, Any]] = []
    for index, word in enumerate(words):
        if not isinstance(word, Mapping):
            raise InvalidResult(
                "pyopenjtalk word {} must be a mapping".format(index)
            )
        keys = set(word)
        if keys != _PYOPENJTALK_FRONTEND_FIELDS:
            missing = sorted(_PYOPENJTALK_FRONTEND_FIELDS - keys)
            extra = sorted(keys - _PYOPENJTALK_FRONTEND_FIELDS)
            raise InvalidResult(
                "pyopenjtalk word {} fields differ; missing={}, extra={}".format(
                    index, missing, extra
                )
            )
        typed_word: Dict[str, Any] = {}
        for field in _PYOPENJTALK_FRONTEND_STRING_FIELDS:
            value = word[field]
            if not isinstance(value, str):
                raise InvalidResult(
                    "pyopenjtalk word {} field {!r} must be a string".format(
                        index, field
                    )
                )
            typed_word[field] = value
        for field in _PYOPENJTALK_FRONTEND_INTEGER_FIELDS:
            value = word[field]
            if isinstance(value, bool) or not isinstance(value, int):
                raise InvalidResult(
                    "pyopenjtalk word {} field {!r} must be an integer".format(
                        index, field
                    )
                )
            typed_word[field] = value
        serialized.append(typed_word)
    return {
        "kind": "pyopenjtalk.run_frontend.words",
        "schemaVersion": 1,
        "words": serialized,
    }


def serialize_cutlet_backend_input(
    normalized_text: Any,
    words: Any,
    kata2hira: Callable[[str], str],
    ja_words: Any,
) -> Dict[str, Any]:
    """Snapshot raw fugashi records and pinned Cutlet grouping decisions."""

    if not isinstance(normalized_text, str):
        raise InvalidResult("Cutlet normalized text must be a string")
    if not isinstance(words, list):
        raise InvalidResult("Cutlet fugashi output must be a list")
    if not callable(kata2hira):
        raise InvalidResult("Cutlet kata2hira converter must be callable")
    if not isinstance(ja_words, (set, frozenset)):
        raise InvalidResult("Cutlet JA_WORDS must be a set")

    records: List[Dict[str, Any]] = []
    effective_types: List[int] = []
    for index, word in enumerate(words):
        surface = getattr(word, "surface", None)
        char_type = getattr(word, "char_type", None)
        is_unknown = getattr(word, "is_unk", None)
        feature = getattr(word, "feature", None)
        if not isinstance(surface, str) or not surface:
            raise InvalidResult(
                "Cutlet word {} surface must be a non-empty string".format(index)
            )
        if isinstance(char_type, bool) or not isinstance(char_type, int):
            raise InvalidResult(
                "Cutlet word {} char_type must be an integer".format(index)
            )
        if char_type < 0:
            raise InvalidResult(
                "Cutlet word {} char_type must be non-negative".format(index)
            )
        if not isinstance(is_unknown, bool):
            raise InvalidResult(
                "Cutlet word {} is_unk must be a boolean".format(index)
            )
        if feature is None:
            raise InvalidResult("Cutlet word {} has no feature record".format(index))
        pronunciation = getattr(feature, "pron", None)
        kana = getattr(feature, "kana", None)
        if pronunciation is not None and not isinstance(pronunciation, str):
            raise InvalidResult(
                "Cutlet word {} pronunciation must be a string or null".format(
                    index
                )
            )
        if kana is not None and not isinstance(kana, str):
            raise InvalidResult(
                "Cutlet word {} kana must be a string or null".format(index)
            )
        reading = pronunciation or kana or surface
        if not isinstance(reading, str):
            raise InvalidResult(
                "Cutlet word {} selected reading must be a string".format(index)
            )
        try:
            hiragana = kata2hira(reading)
        except Exception as error:
            raise InvalidResult(
                "Cutlet word {} reading conversion failed".format(index)
            ) from error
        if not isinstance(hiragana, str) or not hiragana:
            raise InvalidResult(
                "Cutlet word {} hiragana must be a non-empty string".format(index)
            )
        records.append(
            {
                "charType": char_type,
                "hiragana": hiragana,
                "isUnknown": is_unknown,
                "joinWithNext": False,
                "kana": kana,
                "pronunciation": pronunciation,
                "surface": surface,
            }
        )
        effective_types.append(6 if char_type == 7 or not is_unknown else char_type)

    index = 0
    while index < len(records):
        run_end = next(
            (
                candidate
                for candidate in range(index + 1, len(records))
                if effective_types[candidate] != effective_types[index]
            ),
            len(records),
        )
        group_end = next(
            (
                candidate
                for candidate in range(run_end, index, -1)
                if "".join(
                    record["surface"] for record in records[index:candidate]
                )
                in ja_words
            ),
            None,
        )
        if group_end is None:
            index += 1
            continue
        for grouped_index in range(index, group_end - 1):
            records[grouped_index]["joinWithNext"] = True
        index = group_end

    return {
        "kind": CUTLET_BACKEND_INPUT_KIND,
        "normalizedText": normalized_text,
        "schemaVersion": CUTLET_BACKEND_INPUT_SCHEMA_VERSION,
        "words": records,
    }


def serialize_english_preprocess_output(
    text: Any,
    source_words: Any,
    features: Any,
    preprocess_applied: Any,
) -> Dict[str, Any]:
    """Serialize the exact values passed from preprocessing to tokenization."""

    if not isinstance(preprocess_applied, bool):
        raise InvalidResult("English preprocess applied flag must be a boolean")
    if not isinstance(text, str):
        raise InvalidResult("English preprocessed text must be a string")
    if not isinstance(source_words, list) or any(
        not isinstance(word, str) for word in source_words
    ):
        raise InvalidResult("English preprocess source words must be a string list")
    if not isinstance(features, Mapping):
        raise InvalidResult("English preprocess features must be a mapping")

    feature_keys = list(features)
    for source_word_index in feature_keys:
        if isinstance(source_word_index, bool) or not isinstance(
            source_word_index, int
        ):
            raise InvalidResult("English feature keys must be integer source-word indices")

    feature_entries: List[Dict[str, Any]] = []
    for source_word_index in sorted(feature_keys):
        if source_word_index < 0 or source_word_index >= len(source_words):
            raise InvalidResult(
                "English feature index {} is outside {} source words".format(
                    source_word_index, len(source_words)
                )
            )
        value = features[source_word_index]
        if isinstance(value, bool) or not isinstance(value, (str, int, float)):
            raise InvalidResult(
                "English feature {} must be a string, integer, or float".format(
                    source_word_index
                )
            )
        if isinstance(value, float):
            if not math.isfinite(value) or value not in (-0.5, 0.5):
                raise InvalidResult(
                    "English floating feature {} must be -0.5 or 0.5".format(
                        source_word_index
                    )
                )
        feature_entries.append(
            {"sourceWordIndex": source_word_index, "value": value}
        )

    return {
        "applied": preprocess_applied,
        "features": feature_entries,
        "sourceWords": list(source_words),
        "text": text,
    }


def _validate_optional_number(value: Any, path: str) -> None:
    if value is None:
        return
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidResult("{} must be a number or null".format(path))
    if isinstance(value, float) and not math.isfinite(value):
        raise InvalidResult("{} must be finite".format(path))


def serialize_english_tokenize_tokens(tokens: Any) -> List[Dict[str, Any]]:
    """Validate and snapshot raw MToken values returned by G2P.tokenize."""

    if not isinstance(tokens, list):
        raise InvalidResult("English G2P.tokenize must return a list")
    serialized: List[Dict[str, Any]] = []
    for index, token in enumerate(tokens):
        typed_token = serialize_token(token, index)
        keys = set(typed_token)
        if keys != _ENGLISH_RAW_TOKEN_FIELDS:
            missing = sorted(_ENGLISH_RAW_TOKEN_FIELDS - keys)
            extra = sorted(keys - _ENGLISH_RAW_TOKEN_FIELDS)
            raise InvalidResult(
                "English raw token {} fields differ; missing={}, extra={}".format(
                    index, missing, extra
                )
            )
        for field in ("tag", "text", "whitespace"):
            if not isinstance(typed_token[field], str):
                raise InvalidResult(
                    "English raw token {} field {!r} must be a string".format(
                        index, field
                    )
                )
        phonemes = typed_token["phonemes"]
        if phonemes is not None and not isinstance(phonemes, str):
            raise InvalidResult(
                "English raw token {} phonemes must be a string or null".format(index)
            )
        _validate_optional_number(
            typed_token["start_ts"],
            "English raw token {} start_ts".format(index),
        )
        _validate_optional_number(
            typed_token["end_ts"],
            "English raw token {} end_ts".format(index),
        )

        metadata = typed_token["_"]
        if not isinstance(metadata, dict):
            raise InvalidResult(
                "English raw token {} metadata must be an object".format(index)
            )
        metadata_keys = set(metadata)
        if not _ENGLISH_RAW_METADATA_REQUIRED_FIELDS <= metadata_keys:
            raise InvalidResult(
                "English raw token {} metadata is missing {}".format(
                    index,
                    sorted(_ENGLISH_RAW_METADATA_REQUIRED_FIELDS - metadata_keys),
                )
            )
        if not metadata_keys <= _ENGLISH_RAW_METADATA_FIELDS:
            raise InvalidResult(
                "English raw token {} metadata has unexpected fields {}".format(
                    index, sorted(metadata_keys - _ENGLISH_RAW_METADATA_FIELDS)
                )
            )
        for field in ("is_head", "prespace"):
            if not isinstance(metadata[field], bool):
                raise InvalidResult(
                    "English raw token {} metadata {!r} must be a boolean".format(
                        index, field
                    )
                )
        if not isinstance(metadata["num_flags"], str):
            raise InvalidResult(
                "English raw token {} metadata 'num_flags' must be a string".format(
                    index
                )
            )
        if "stress" in metadata:
            stress = metadata["stress"]
            if isinstance(stress, bool) or not isinstance(stress, (int, float)):
                raise InvalidResult(
                    "English raw token {} stress must be a number".format(index)
                )
            if isinstance(stress, float) and (
                not math.isfinite(stress) or stress not in (-0.5, 0.5)
            ):
                raise InvalidResult(
                    "English raw token {} floating stress must be -0.5 or 0.5".format(
                        index
                    )
                )
        if "rating" in metadata and (
            isinstance(metadata["rating"], bool)
            or not isinstance(metadata["rating"], int)
        ):
            raise InvalidResult(
                "English raw token {} rating must be an integer".format(index)
            )
        serialized.append(typed_token)
    return serialized


def serialize_english_backend_input(
    preprocess_output: Dict[str, Any], raw_tokens: Any
) -> Dict[str, Any]:
    """Assemble the versioned replay boundary for the English pure pipeline."""

    return {
        "kind": ENGLISH_BACKEND_INPUT_KIND,
        "preprocess": preprocess_output,
        "schemaVersion": ENGLISH_BACKEND_INPUT_SCHEMA_VERSION,
        "tokens": serialize_english_tokenize_tokens(raw_tokens),
    }


def attach_english_espeak_calls(
    backend_input: Dict[str, Any], calls: Any
) -> Dict[str, Any]:
    """Add exact ordered raw eSpeak calls to an English token snapshot."""

    if backend_input.get("kind") != ENGLISH_BACKEND_INPUT_KIND or backend_input.get(
        "schemaVersion"
    ) != ENGLISH_BACKEND_INPUT_SCHEMA_VERSION:
        raise InvalidResult("English eSpeak calls require a schema-1 token snapshot")
    if not isinstance(calls, list):
        raise InvalidResult("English eSpeak calls must be a list")
    serialized: List[Dict[str, Any]] = []
    for index, call in enumerate(calls):
        if not isinstance(call, dict) or set(call) != {"rawPhones", "text"}:
            raise InvalidResult(
                "English eSpeak call {} must contain rawPhones and text".format(index)
            )
        text = call["text"]
        raw_phones = call["rawPhones"]
        if not isinstance(text, str):
            raise InvalidResult(
                "English eSpeak call {} text must be a string".format(index)
            )
        if raw_phones is not None and not isinstance(raw_phones, str):
            raise InvalidResult(
                "English eSpeak call {} rawPhones must be a string or null".format(
                    index
                )
            )
        serialized.append({"rawPhones": raw_phones, "text": text})
    result = dict(backend_input)
    result["schemaVersion"] = ENGLISH_ESPEAK_BACKEND_INPUT_SCHEMA_VERSION
    result["espeakCalls"] = serialized
    return result


def attach_english_model_calls(
    backend_input: Dict[str, Any], calls: Any
) -> Dict[str, Any]:
    """Add exact ordered BART fallback calls to an English token snapshot.

    This serializer defines the future capture boundary only. It does not
    enable a model mode, load weights, or relax the model-provenance preflight.
    """

    if backend_input.get("kind") != ENGLISH_BACKEND_INPUT_KIND or backend_input.get(
        "schemaVersion"
    ) != ENGLISH_BACKEND_INPUT_SCHEMA_VERSION:
        raise InvalidResult("English model calls require a schema-1 token snapshot")
    if not isinstance(calls, list):
        raise InvalidResult("English model calls must be a list")
    serialized: List[Dict[str, Any]] = []
    for index, call in enumerate(calls):
        if not isinstance(call, dict) or set(call) != {
            "generatedIds",
            "inputIds",
            "phonemes",
            "rating",
            "text",
        }:
            raise InvalidResult(
                "English model call {} must contain generatedIds, inputIds, "
                "phonemes, rating, and text".format(index)
            )
        text = call["text"]
        input_ids = call["inputIds"]
        generated_ids = call["generatedIds"]
        phonemes = call["phonemes"]
        rating = call["rating"]
        if not isinstance(text, str) or not text:
            raise InvalidResult(
                "English model call {} text must be a non-empty string".format(
                    index
                )
            )
        if (
            not isinstance(input_ids, list)
            or len(input_ids) != len(text) + 2
            or input_ids[0] != 1
            or input_ids[-1] != 2
            or any(
                isinstance(token_id, bool)
                or not isinstance(token_id, int)
                or token_id < 0
                for token_id in input_ids
            )
        ):
            raise InvalidResult(
                "English model call {} inputIds must contain one non-negative "
                "integer per grapheme between BOS 1 and EOS 2".format(index)
            )
        if (
            not isinstance(generated_ids, list)
            or not generated_ids
            or any(
                isinstance(token_id, bool)
                or not isinstance(token_id, int)
                or token_id < 0
                for token_id in generated_ids
            )
        ):
            raise InvalidResult(
                "English model call {} generatedIds must be a non-empty array "
                "of non-negative integers".format(index)
            )
        if not isinstance(phonemes, str):
            raise InvalidResult(
                "English model call {} phonemes must be a string".format(index)
            )
        if isinstance(rating, bool) or rating != 1:
            raise InvalidResult(
                "English model call {} rating must equal pinned value 1".format(
                    index
                )
            )
        serialized.append(
            {
                "generatedIds": list(generated_ids),
                "inputIds": list(input_ids),
                "phonemes": phonemes,
                "rating": rating,
                "text": text,
            }
        )
    result = dict(backend_input)
    result["schemaVersion"] = ENGLISH_MODEL_BACKEND_INPUT_SCHEMA_VERSION
    result["modelCalls"] = serialized
    return result


def serialize_korean_backend_input(
    text: Any, tokens: Any, cmu_lookups: Any
) -> Dict[str, Any]:
    """Snapshot Korean MeCab output and ordered CMUdict lookup results."""

    if not isinstance(text, str):
        raise InvalidResult("Korean MeCab input must be a string")
    if not isinstance(tokens, list):
        raise InvalidResult("Korean MeCab.pos must return a list")
    serialized_tokens: List[Dict[str, str]] = []
    for index, token in enumerate(tokens):
        if not isinstance(token, tuple) or len(token) != 2:
            raise InvalidResult(
                "Korean MeCab token {} must be a (surface, tag) tuple".format(index)
            )
        surface, tag = token
        if not isinstance(surface, str) or not isinstance(tag, str):
            raise InvalidResult(
                "Korean MeCab token {} surface and tag must be strings".format(
                    index
                )
            )
        serialized_tokens.append({"surface": surface, "tag": tag})

    if not isinstance(cmu_lookups, list):
        raise InvalidResult("Korean CMUdict lookups must be a list")
    serialized_lookups: List[Dict[str, Any]] = []
    for index, lookup in enumerate(cmu_lookups):
        if not isinstance(lookup, Mapping) or set(lookup) != {"arpabet", "key"}:
            raise InvalidResult(
                "Korean CMUdict lookup {} must contain only key and arpabet".format(
                    index
                )
            )
        key = lookup["key"]
        arpabet = lookup["arpabet"]
        if (
            not isinstance(key, str)
            or not key
            or key != key.lower()
            or any(character < "a" or character > "z" for character in key)
        ):
            raise InvalidResult(
                "Korean CMUdict lookup {} key must be normalized lowercase ASCII".format(
                    index
                )
            )
        if arpabet is not None and (
            not isinstance(arpabet, list)
            or not arpabet
            or any(not isinstance(symbol, str) or not symbol for symbol in arpabet)
        ):
            raise InvalidResult(
                "Korean CMUdict lookup {} arpabet must be null or a non-empty "
                "string list".format(index)
            )
        serialized_lookups.append(
            {"arpabet": None if arpabet is None else list(arpabet), "key": key}
        )
    return {
        "cmuLookups": serialized_lookups,
        "input": text,
        "kind": KOREAN_BACKEND_INPUT_KIND,
        "schemaVersion": KOREAN_BACKEND_INPUT_SCHEMA_VERSION,
        "tokens": serialized_tokens,
    }


def serialize_vietnamese_backend_input(text: Any, tokens: Any) -> Dict[str, Any]:
    """Validate and snapshot the exact underthesea tokenizer boundary."""

    if not isinstance(text, str):
        raise InvalidResult("Vietnamese tokenizer input must be a string")
    if not isinstance(tokens, list):
        raise InvalidResult("Vietnamese tokenizer output must be a list")
    serialized: List[str] = []
    for index, token in enumerate(tokens):
        if not isinstance(token, str) or not token:
            raise InvalidResult(
                "Vietnamese tokenizer token {} must be a non-empty string".format(
                    index
                )
            )
        serialized.append(token)
    return {
        "input": text,
        "kind": VIETNAMESE_BACKEND_INPUT_KIND,
        "schemaVersion": VIETNAMESE_BACKEND_INPUT_SCHEMA_VERSION,
        "tokens": serialized,
    }


def _serialize_string_list(value: Any, path: str) -> List[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise InvalidResult("{} must be a string list".format(path))
    return list(value)


def serialize_chinese_normalization(
    text: Any, mode: Any, normalized: Any
) -> Dict[str, str]:
    """Snapshot the exact cn2an normalization boundary used by ZHG2P."""

    if not isinstance(text, str) or not isinstance(normalized, str):
        raise InvalidResult("Chinese normalization input and output must be strings")
    if mode != "an2cn":
        raise InvalidResult("Chinese normalization mode must be 'an2cn'")
    return {"input": text, "mode": mode, "output": normalized}


def serialize_chinese_posseg(text: Any, segments: Any) -> Dict[str, Any]:
    """Snapshot one jieba.posseg.lcut result without backend object leakage."""

    if not isinstance(text, str):
        raise InvalidResult("Chinese POS-segmentation input must be a string")
    if not isinstance(segments, list):
        raise InvalidResult("jieba.posseg.lcut must return a list")
    serialized: List[Dict[str, str]] = []
    for index, segment in enumerate(segments):
        if isinstance(segment, (str, bytes)):
            raise InvalidResult(
                "Chinese POS segment {} must be a (word, POS) pair".format(index)
            )
        try:
            pair = tuple(segment)
        except TypeError as error:
            raise InvalidResult(
                "Chinese POS segment {} must be iterable".format(index)
            ) from error
        if len(pair) != 2 or any(not isinstance(value, str) for value in pair):
            raise InvalidResult(
                "Chinese POS segment {} must contain two strings".format(index)
            )
        serialized.append({"pos": pair[1], "word": pair[0]})
    return {"input": text, "segments": serialized}


def serialize_chinese_pinyin_call(
    text: Any,
    output: Any,
    *,
    stage: str,
    style: str,
    neutral_tone_with_five: Any,
) -> Dict[str, Any]:
    """Serialize one pypinyin.lazy_pinyin call at a Chinese pipeline boundary."""

    if not isinstance(text, str):
        raise InvalidResult("Chinese pinyin input must be a string")
    if stage not in ("legacy-word", "tone-premerge", "frontend-render"):
        raise InvalidResult("unsupported Chinese pinyin capture stage {!r}".format(stage))
    if style not in ("tone3", "initials", "finals-tone3"):
        raise InvalidResult("unsupported Chinese pinyin style {!r}".format(style))
    if neutral_tone_with_five is not True:
        raise InvalidResult(
            "Chinese pinyin calls must set neutral_tone_with_five=True"
        )
    return {
        "input": text,
        "kind": "pypinyin.lazy_pinyin",
        "neutralToneWithFive": True,
        "output": _serialize_string_list(output, "Chinese pinyin output"),
        "stage": stage,
        "style": style,
    }


def serialize_chinese_search_segments(text: Any, segments: Any) -> Dict[str, Any]:
    """Serialize one jieba.cut_for_search call used by tone sandhi."""

    if not isinstance(text, str):
        raise InvalidResult("Chinese search-segmentation input must be a string")
    return {
        "input": text,
        "kind": "jieba.cut_for_search",
        "output": _serialize_string_list(
            segments, "Chinese search-segmentation output"
        ),
        "stage": "tone-sandhi",
    }


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise BackendUnavailable("cannot read backend resource {!s}".format(path)) from error
    return digest.hexdigest()


def _require_cutlet_ja_words_resource(cutlet_module: Any, ja_words: Any) -> str:
    """Validate the exact grouping resource without redistributing its rows."""

    module_file = getattr(cutlet_module, "__file__", None)
    if not isinstance(module_file, str):
        raise BackendUnavailable("pinned Cutlet module has no source path")
    resource = Path(module_file).resolve().with_name("data") / "ja_words.txt"
    if not resource.is_file() or resource.is_symlink():
        raise BackendUnavailable(
            "pinned Cutlet ja_words.txt is missing or is a symbolic link"
        )
    try:
        payload = resource.read_bytes()
    except OSError as error:
        raise BackendUnavailable("cannot read pinned Cutlet ja_words.txt") from error
    actual_sha256 = hashlib.sha256(payload).hexdigest()
    actual_record_count = len(payload.splitlines())
    if (
        actual_sha256 != CUTLET_JA_WORDS_SHA256
        or len(payload) != CUTLET_JA_WORDS_SIZE_BYTES
        or actual_record_count != CUTLET_JA_WORDS_RECORD_COUNT
    ):
        raise BackendUnavailable(
            "pinned Cutlet ja_words.txt identity is "
            "sha256:{}+bytes:{}+records:{}; expected {}".format(
                actual_sha256,
                len(payload),
                actual_record_count,
                CUTLET_JA_WORDS_IDENTITY,
            )
        )
    if not isinstance(ja_words, (set, frozenset)) or len(ja_words) != (
        CUTLET_JA_WORDS_RECORD_COUNT
    ):
        raise InvalidResult(
            "pinned Cutlet JA_WORDS must contain exactly {} unique records".format(
                CUTLET_JA_WORDS_RECORD_COUNT
            )
        )
    return CUTLET_JA_WORDS_IDENTITY


def _require_cutlet_tagger_dictionary(tagger: Any, dicdir: Path) -> str:
    """Require fugashi's live tagger to use the validated system dictionary."""

    dictionary_info = getattr(tagger, "dictionary_info", None)
    if not isinstance(dictionary_info, list) or len(dictionary_info) != 1:
        raise BackendUnavailable(
            "Japanese Cutlet fugashi tagger must load exactly one dictionary"
        )
    info = dictionary_info[0]
    if not isinstance(info, Mapping):
        raise BackendUnavailable(
            "Japanese Cutlet fugashi dictionary info must be an object"
        )
    expected_fields = {"charset", "filename", "size", "version"}
    if set(info) != expected_fields:
        raise BackendUnavailable(
            "Japanese Cutlet fugashi dictionary info fields differ; "
            "missing={}, extra={}".format(
                sorted(expected_fields - set(info)),
                sorted(set(info) - expected_fields),
            )
        )
    filename = info.get("filename")
    if not isinstance(filename, str):
        raise BackendUnavailable(
            "Japanese Cutlet fugashi dictionary info has no filename"
        )
    expected = (dicdir / "sys.dic").resolve()
    if Path(filename).resolve() != expected:
        raise BackendUnavailable(
            "Japanese Cutlet fugashi loaded {!s}; expected {!s}".format(
                Path(filename).resolve(), expected
            )
        )
    expected_values = {
        "charset": CUTLET_UNIDIC_DICTIONARY_CHARSET,
        "size": CUTLET_UNIDIC_DICTIONARY_ENTRY_COUNT,
        "version": CUTLET_UNIDIC_DICTIONARY_BINARY_VERSION,
    }
    for field, expected_value in expected_values.items():
        if info[field] != expected_value:
            raise BackendUnavailable(
                "Japanese Cutlet fugashi dictionary {!r} is {!r}; "
                "expected {!r}".format(field, info[field], expected_value)
            )
    return CUTLET_UNIDIC_LIVE_DICTIONARY_IDENTITY


@lru_cache(maxsize=4)
def _directory_tree_fingerprint(directory_name: str) -> Tuple[str, int, int]:
    """Hash relative paths, lengths, and bytes for one immutable resource tree."""

    directory = Path(directory_name).expanduser().resolve()
    if not directory.is_dir():
        raise BackendUnavailable(
            "backend resource directory is missing: {!s}".format(directory)
        )
    files: List[Path] = []
    for entry in directory.rglob("*"):
        if entry.is_symlink():
            raise BackendUnavailable(
                "backend resource tree contains a symbolic link: {!s}".format(entry)
            )
        if entry.is_file():
            files.append(entry)
    if not files:
        raise BackendUnavailable(
            "backend resource directory contains no files: {!s}".format(directory)
        )

    digest = hashlib.sha256()
    total_size = 0
    ordered = sorted(files, key=lambda path: path.relative_to(directory).as_posix())
    for path in ordered:
        relative = path.relative_to(directory).as_posix().encode("utf-8")
        size = path.stat().st_size
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(size.to_bytes(8, "big"))
        try:
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
        except OSError as error:
            raise BackendUnavailable(
                "cannot read backend resource {!s}".format(path)
            ) from error
        total_size += size
    return digest.hexdigest(), len(ordered), total_size


def _require_cutlet_unidic_resource(tagger: Any) -> Dict[str, str]:
    """Validate exact UniDic 3.1.0 bytes and the dictionary used by fugashi."""

    try:
        unidic = importlib.import_module("unidic")
    except (ImportError, ModuleNotFoundError) as error:
        raise BackendUnavailable("pinned UniDic package is not installed") from error
    raw_dicdir = getattr(unidic, "DICDIR", None)
    if not isinstance(raw_dicdir, str) or not raw_dicdir:
        raise BackendUnavailable("pinned UniDic package has no DICDIR")
    dicdir = Path(raw_dicdir).expanduser().resolve()
    if not dicdir.is_dir():
        raise BackendUnavailable(
            "pinned UniDic dictionary directory is missing: {!s}".format(dicdir)
        )

    version_path = dicdir / "version"
    if not version_path.is_file() or version_path.is_symlink():
        raise BackendUnavailable(
            "pinned UniDic dictionary has no regular version marker"
        )
    try:
        version_payload = version_path.read_bytes()
    except OSError as error:
        raise BackendUnavailable(
            "cannot read pinned UniDic dictionary version marker"
        ) from error
    try:
        version_marker = version_payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise BackendUnavailable(
            "pinned UniDic dictionary version marker is not UTF-8"
        ) from error
    if version_marker != CUTLET_UNIDIC_VERSION_MARKER:
        raise BackendUnavailable(
            "pinned UniDic dictionary version marker is {!r}; expected {!r}".format(
                version_marker, CUTLET_UNIDIC_VERSION_MARKER
            )
        )

    tree_sha256, tree_files, tree_bytes = _directory_tree_fingerprint(str(dicdir))
    if (
        tree_sha256 != CUTLET_UNIDIC_TREE_SHA256
        or tree_files != CUTLET_UNIDIC_TREE_FILE_COUNT
        or tree_bytes != CUTLET_UNIDIC_TREE_SIZE_BYTES
    ):
        raise BackendUnavailable(
            "pinned UniDic dictionary tree identity is "
            "sha256:{}+files:{}+bytes:{}; expected {}".format(
                tree_sha256,
                tree_files,
                tree_bytes,
                CUTLET_UNIDIC_TREE_IDENTITY,
            )
        )

    live_identity = _require_cutlet_tagger_dictionary(tagger, dicdir)
    return {
        "fugashi-system-dictionary": live_identity,
        "unidic-dictionary-tree": CUTLET_UNIDIC_TREE_IDENTITY,
        "unidic-dictionary-version": CUTLET_UNIDIC_VERSION_MARKER,
    }


def _jieba_default_dict_sha256(jieba: Any) -> Optional[str]:
    module_file = getattr(jieba, "__file__", None)
    if not isinstance(module_file, str):
        return None
    dictionary = Path(module_file).resolve().with_name("dict.txt")
    if not dictionary.is_file():
        return None
    return _sha256_file(dictionary)


def _require_jieba_default_dict_resource(jieba: Any) -> str:
    actual_sha256 = _jieba_default_dict_sha256(jieba)
    if actual_sha256 is None:
        raise BackendUnavailable(
            "jieba 0.42.1 default dict.txt is not installed; provision the "
            "pinned wheel before running Chinese fixtures"
        )
    if actual_sha256 != JIEBA_DEFAULT_DICT_SHA256:
        raise BackendUnavailable(
            "jieba default dict.txt SHA-256 is {}; expected {}".format(
                actual_sha256, JIEBA_DEFAULT_DICT_SHA256
            )
        )
    return JIEBA_DEFAULT_DICT_IDENTITY


def _require_python_312(fixture_family: str = "Chinese") -> None:
    if sys.version_info[:2] != (3, 12):
        raise BackendUnavailable(
            "{} fixtures require the locked Python 3.12 environment; "
            "running {}.{}".format(
                fixture_family, sys.version_info[0], sys.version_info[1]
            )
        )


def _require_python_311(fixture_family: str = "Vietnamese") -> None:
    if sys.version_info[:2] != (3, 11):
        raise BackendUnavailable(
            "{} fixtures require the locked Python 3.11 environment; "
            "running {}.{}".format(
                fixture_family, sys.version_info[0], sys.version_info[1]
            )
        )


def _initialize_cutlet_backend(factory: Callable[[], Any]) -> Any:
    """Convert fugashi/MeCab construction failures into a typed preflight."""

    try:
        return factory()
    except RuntimeError as error:
        raise BackendUnavailable(
            "Japanese Cutlet fugashi/MeCab initialization failed; provision "
            "the exact UniDic resource before running the oracle"
        ) from error


def _require_cutlet_dependency_versions() -> None:
    for distribution, required_version in sorted(
        CUTLET_LOCKED_DISTRIBUTIONS.items()
    ):
        try:
            actual_version = importlib_metadata.version(distribution)
        except importlib_metadata.PackageNotFoundError as error:
            raise BackendUnavailable(
                "Cutlet dependency {!r} is not installed".format(distribution)
            ) from error
        if actual_version != required_version:
            raise BackendUnavailable(
                "Cutlet dependency {!r} is version {}; expected {}".format(
                    distribution, actual_version, required_version
                )
            )


def _require_english_espeak_dependency_versions() -> None:
    _require_python_312("English eSpeak")
    for distribution, required_version in sorted(
        ENGLISH_ESPEAK_LOCKED_DISTRIBUTIONS.items()
    ):
        try:
            actual_version = importlib_metadata.version(distribution)
        except importlib_metadata.PackageNotFoundError as error:
            raise BackendUnavailable(
                "English eSpeak dependency {!r} is not installed".format(
                    distribution
                )
            ) from error
        if actual_version != required_version:
            raise BackendUnavailable(
                "English eSpeak dependency {!r} is version {}; expected {}".format(
                    distribution, actual_version, required_version
                )
            )


def _require_english_dependency_versions(trf: bool) -> None:
    _require_python_312("English")
    expected = dict(ENGLISH_LOCKED_DISTRIBUTIONS)
    if trf:
        expected.update(ENGLISH_TRANSFORMER_LOCKED_DISTRIBUTIONS)
    model_name, model_version = ENGLISH_MODEL_VERSIONS[trf]
    expected[model_name] = model_version
    for distribution, required_version in sorted(expected.items()):
        try:
            actual_version = importlib_metadata.version(distribution)
        except importlib_metadata.PackageNotFoundError as error:
            raise BackendUnavailable(
                "English dependency {!r} is not installed".format(distribution)
            ) from error
        if actual_version != required_version:
            raise BackendUnavailable(
                "English dependency {!r} is version {}; expected {}".format(
                    distribution, actual_version, required_version
                )
            )


def _require_chinese_dependency_versions(mode: str) -> None:
    expected = (
        CHINESE_FRONTEND_LOCKED_DISTRIBUTIONS
        if mode in ("frontend-1.1", "frontend-1.1-en-small-no-fallback")
        else CHINESE_LOCKED_DISTRIBUTIONS
    )
    for distribution, required_version in sorted(expected.items()):
        try:
            actual_version = importlib_metadata.version(distribution)
        except importlib_metadata.PackageNotFoundError as error:
            raise BackendUnavailable(
                "Chinese dependency {!r} is not installed".format(distribution)
            ) from error
        if actual_version != required_version:
            raise BackendUnavailable(
                "Chinese dependency {!r} is version {}; expected {}".format(
                    distribution, actual_version, required_version
                )
            )


def _require_hebrew_dependency_versions() -> None:
    expected = dict(HEBREW_LOCKED_DISTRIBUTIONS)
    if sys.platform == "win32":
        expected.update(HEBREW_WINDOWS_LOCKED_DISTRIBUTIONS)
    for distribution, required_version in sorted(expected.items()):
        try:
            actual_version = importlib_metadata.version(distribution)
        except importlib_metadata.PackageNotFoundError as error:
            raise BackendUnavailable(
                "Hebrew dependency {!r} is not installed".format(distribution)
            ) from error
        if actual_version != required_version:
            raise BackendUnavailable(
                "Hebrew dependency {!r} is version {}; expected {}".format(
                    distribution, actual_version, required_version
                )
            )


def _require_vietnamese_dependency_versions() -> None:
    for distribution, required_version in sorted(
        VIETNAMESE_LOCKED_DISTRIBUTIONS.items()
    ):
        try:
            actual_version = importlib_metadata.version(distribution)
        except importlib_metadata.PackageNotFoundError as error:
            raise BackendUnavailable(
                "Vietnamese dependency {!r} is not installed".format(distribution)
            ) from error
        if actual_version != required_version:
            raise BackendUnavailable(
                "Vietnamese dependency {!r} is version {}; expected {}".format(
                    distribution, actual_version, required_version
                )
            )


@contextlib.contextmanager
def _offline_network_guard(fixture_family: str = "Chinese") -> Iterable[None]:
    """Reject network I/O throughout guarded imports, setup, and conversion."""

    original_connect = socket.socket.connect
    original_connect_ex = socket.socket.connect_ex
    original_create_connection = socket.create_connection
    original_urlopen = urllib.request.urlopen

    def reject_network(*_args: Any, **_kwargs: Any) -> Any:
        raise BackendUnavailable(
            "{} oracle attempted network access; provision all pinned "
            "packages and resources before regeneration or verification".format(
                fixture_family
            )
        )

    socket.socket.connect = reject_network
    socket.socket.connect_ex = reject_network
    socket.create_connection = reject_network
    urllib.request.urlopen = reject_network
    try:
        yield
    finally:
        urllib.request.urlopen = original_urlopen
        socket.create_connection = original_create_connection
        socket.socket.connect_ex = original_connect_ex
        socket.socket.connect = original_connect


def _nltk_cmudict_sha256(nltk: Any) -> Optional[str]:
    try:
        resource = nltk.data.find("corpora/cmudict.zip")
    except LookupError:
        return None
    path = Path(str(resource))
    if not path.is_file():
        return None
    return _sha256_file(path)


def _require_nltk_cmudict_resource(nltk: Any) -> str:
    actual_sha256 = _nltk_cmudict_sha256(nltk)
    if actual_sha256 is None:
        raise BackendUnavailable(
            "NLTK CMUdict {} zip is not installed; provision the pinned resource "
            "before running Korean fixtures".format(NLTK_CMUDICT_VERSION)
        )
    if actual_sha256 != NLTK_CMUDICT_SHA256:
        raise BackendUnavailable(
            "NLTK CMUdict zip SHA-256 is {}; expected {}".format(
                actual_sha256, NLTK_CMUDICT_SHA256
            )
        )
    return NLTK_CMUDICT_IDENTITY


def _reject_json_constant(value: str) -> None:
    raise InvalidInput("non-finite JSON number {!r} is not allowed".format(value))


def _object_without_duplicate_keys(pairs: Sequence[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidInput("duplicate JSON object key {!r}".format(key))
        result[key] = value
    return result


def parse_case(value: Any, line_number: int) -> FixtureCase:
    if not isinstance(value, dict):
        raise InvalidInput("line {} must contain a JSON object".format(line_number))

    allowed = {"caseId", "input", "language", "mode", "options", "seed"}
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise InvalidInput(
            "line {} has unknown keys: {}".format(line_number, ", ".join(unknown))
        )

    for key in ("language", "mode", "input"):
        if not isinstance(value.get(key), str):
            raise InvalidInput("line {} field {!r} must be a string".format(line_number, key))

    options = value.get("options", {})
    if not isinstance(options, dict):
        raise InvalidInput("line {} field 'options' must be an object".format(line_number))

    case_id = value.get("caseId")
    if case_id is not None and not isinstance(case_id, str):
        raise InvalidInput("line {} field 'caseId' must be a string".format(line_number))

    seed = value.get("seed")
    if seed is not None and (isinstance(seed, bool) or not isinstance(seed, int)):
        raise InvalidInput("line {} field 'seed' must be an integer".format(line_number))

    return FixtureCase(
        language=value["language"],
        mode=value["mode"],
        options=options,
        input_text=value["input"],
        case_id=case_id,
        seed=seed,
    )


def read_cases(path: Path) -> List[FixtureCase]:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise InvalidInput("cannot read UTF-8 input {!s}: {}".format(path, error)) from error

    cases: List[FixtureCase] = []
    case_ids: Set[str] = set()
    for line_number, line in enumerate(source.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            value = json.loads(
                line,
                object_pairs_hook=_object_without_duplicate_keys,
                parse_constant=_reject_json_constant,
            )
        except ReferenceToolError:
            raise
        except json.JSONDecodeError as error:
            raise InvalidInput(
                "invalid JSON on line {} at column {}".format(line_number, error.colno)
            ) from error
        case = parse_case(value, line_number)
        if case.case_id is not None:
            if case.case_id in case_ids:
                raise InvalidInput("duplicate caseId {!r}".format(case.case_id))
            case_ids.add(case.case_id)
        cases.append(case)

    if not cases:
        raise InvalidInput("input JSONL contains no cases")
    return cases


def canonicalize(value: Any, path: str = "$") -> Any:
    """Convert supported Python values to deterministic JSON-compatible data."""

    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise SerializationFailure("{} contains a non-finite float".format(path))
        return value
    if isinstance(value, Mapping):
        result: Dict[str, Any] = {}
        if any(not isinstance(key, str) for key in value):
            raise SerializationFailure("{} contains a non-string mapping key".format(path))
        for key in sorted(value):
            result[key] = canonicalize(value[key], "{}.{}".format(path, key))
        return result
    if isinstance(value, (list, tuple)):
        return [canonicalize(item, "{}[{}]".format(path, index)) for index, item in enumerate(value)]
    if isinstance(value, (set, frozenset)):
        items = [canonicalize(item, path + "[]") for item in value]
        return sorted(items, key=_canonical_json_fragment)
    if is_dataclass(value) and not isinstance(value, type):
        return serialize_dataclass(value, path)
    raise SerializationFailure(
        "{} has unsupported value type {}.{}".format(
            path, type(value).__module__, type(value).__qualname__
        )
    )


def _canonical_json_fragment(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def serialize_dataclass(value: Any, path: str = "$") -> Dict[str, Any]:
    """Serialize declared dataclass fields and any upstream dynamic fields."""

    declared = [field.name for field in fields(value)]
    result = {
        name: canonicalize(getattr(value, name), "{}.{}".format(path, name))
        for name in declared
    }
    attributes = getattr(value, "__dict__", {})
    for name in sorted(set(attributes) - set(declared)):
        result[name] = canonicalize(attributes[name], "{}.{}".format(path, name))
    return result


def serialize_token(token: Any, index: int = 0) -> Dict[str, Any]:
    if not is_dataclass(token) or isinstance(token, type):
        raise InvalidResult("token {} is not an upstream dataclass instance".format(index))
    return serialize_dataclass(token, "$.tokens[{}]".format(index))


def canonical_json_line(record: Dict[str, Any]) -> str:
    return _canonical_json_fragment(canonicalize(record)) + "\n"


def _read_upstream_version(upstream_root: Path) -> str:
    init_path = upstream_root / "misaki" / "__init__.py"
    try:
        module = ast.parse(init_path.read_text(encoding="utf-8"), filename=str(init_path))
    except (OSError, SyntaxError, UnicodeError) as error:
        raise UpstreamMismatch("cannot inspect {!s}: {}".format(init_path, error)) from error
    for node in module.body:
        if not isinstance(node, ast.Assign):
            continue
        if any(isinstance(target, ast.Name) and target.id == "__version__" for target in node.targets):
            try:
                value = ast.literal_eval(node.value)
            except (ValueError, TypeError) as error:
                raise UpstreamMismatch("upstream __version__ is not a string literal") from error
            if isinstance(value, str):
                return value
    raise UpstreamMismatch("upstream checkout does not declare misaki.__version__")


def verify_upstream_checkout(upstream_root: Path) -> Path:
    root = upstream_root.expanduser().resolve()
    if not (root / "misaki" / "token.py").is_file():
        raise UpstreamMismatch("{!s} is not a Misaki source checkout".format(root))
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as error:
        raise UpstreamMismatch("git is required to validate the upstream pin") from error
    commit = completed.stdout.strip() if completed.returncode == 0 else ""
    if commit != UPSTREAM_COMMIT:
        raise UpstreamMismatch(
            "upstream commit is {!r}; expected {!r}".format(commit, UPSTREAM_COMMIT)
        )
    tracked_state_commands = (
        ["git", "-C", str(root), "diff", "--quiet", "HEAD", "--"],
        [
            "git",
            "-C",
            str(root),
            "diff",
            "--cached",
            "--quiet",
            "HEAD",
            "--",
        ],
    )
    for command in tracked_state_commands:
        try:
            tracked_state = subprocess.run(
                command,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except OSError as error:
            raise UpstreamMismatch(
                "git is required to validate the upstream pin"
            ) from error
        if tracked_state.returncode == 1:
            raise UpstreamMismatch(
                "upstream checkout has tracked modifications; use a clean "
                "checkout of the pinned commit"
            )
        if tracked_state.returncode != 0:
            raise UpstreamMismatch(
                "git could not validate the upstream checkout's tracked state"
            )
    version = _read_upstream_version(root)
    if version != UPSTREAM_VERSION:
        raise UpstreamMismatch(
            "upstream version is {!r}; expected {!r}".format(version, UPSTREAM_VERSION)
        )
    return root


def _path_is_within(path: Path, directory: Path) -> bool:
    try:
        path.relative_to(directory)
    except ValueError:
        return False
    return True


def _import_upstream_module(name: str) -> Any:
    try:
        return importlib.import_module(name)
    except (ImportError, ModuleNotFoundError) as error:
        raise BackendUnavailable("cannot import {!r}".format(name)) from error


def _pinned_english_link_pattern(upstream_root: Path) -> str:
    """Read only LINK_REGEX from pinned en.py for the no-English VI mode."""

    path = upstream_root / "misaki" / "en.py"
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (OSError, UnicodeError, SyntaxError) as error:
        raise UpstreamMismatch("cannot inspect pinned English LINK_REGEX") from error
    patterns: List[str] = []
    for node in tree.body:
        if (
            isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id == "LINK_REGEX"
            and isinstance(node.value, ast.Call)
            and isinstance(node.value.func, ast.Attribute)
            and isinstance(node.value.func.value, ast.Name)
            and node.value.func.value.id == "re"
            and node.value.func.attr == "compile"
            and len(node.value.args) == 1
            and not node.value.keywords
        ):
            pattern = ast.literal_eval(node.value.args[0])
            if isinstance(pattern, str):
                patterns.append(pattern)
    if len(patterns) != 1:
        raise UpstreamMismatch(
            "pinned en.py must contain exactly one literal LINK_REGEX"
        )
    return patterns[0]


def _import_vietnamese_no_english_module(upstream_root: Path) -> Any:
    """Import pinned vi.py without initializing its unused English stack.

    Pinned vi.py imports G2P and LINK_REGEX unconditionally even when
    enable_en_g2p=False. Its declared `vi` extra does not include the
    transformers packages imported by en.py. This temporary module supplies
    the exact regex literal read from pinned en.py and a rejecting G2P class;
    the selected modes never construct G2P.
    """

    existing = sys.modules.get("misaki.vi")
    if existing is not None:
        return existing

    package = _import_upstream_module("misaki")
    pattern = _pinned_english_link_pattern(upstream_root)
    stub = types.ModuleType("misaki.en")
    stub.__package__ = "misaki"
    stub.LINK_REGEX = re.compile(pattern)

    class RejectingG2P:
        def __init__(self, *_args: Any, **_kwargs: Any) -> None:
            raise InvalidResult(
                "Vietnamese no-English-fallback mode constructed English G2P"
            )

    stub.G2P = RejectingG2P
    sentinel = object()
    previous_module = sys.modules.get("misaki.en", sentinel)
    previous_attribute = getattr(package, "en", sentinel)
    if previous_module is not sentinel:
        module_file = getattr(previous_module, "__file__", None)
        if not isinstance(module_file, str) or not _path_is_within(
            Path(module_file).resolve(), upstream_root
        ):
            raise UpstreamMismatch("a different misaki.en module is already imported")
        return _import_upstream_module("misaki.vi")

    sys.modules["misaki.en"] = stub
    setattr(package, "en", stub)
    try:
        return _import_upstream_module("misaki.vi")
    finally:
        if sys.modules.get("misaki.en") is stub:
            del sys.modules["misaki.en"]
        if previous_attribute is sentinel:
            if getattr(package, "en", sentinel) is stub:
                delattr(package, "en")
        else:
            setattr(package, "en", previous_attribute)


class _DisabledFallback:
    """Truthy constructor sentinel that prevents upstream model fallback setup."""

    def __call__(self, _token: Any) -> Tuple[None, None]:
        return None, None


class _CapturingChineseEnglishCallback:
    """Capture one exact English G2P result and tokenizer stream per ZH call."""

    _INPUT_PATTERN = re.compile(r"[A-Za-z '\-]*[A-Za-z][A-Za-z '\-]*\Z")

    def __init__(self, engine: Any) -> None:
        self.engine = engine
        self._calls: Optional[List[Dict[str, Any]]] = None

    def begin(self) -> None:
        if self._calls is not None:
            raise InvalidResult("Chinese English callback capture is already active")
        self._calls = []

    def finish(self, expected_inputs: List[str]) -> List[Dict[str, Any]]:
        calls = self._calls
        self._calls = None
        if calls is None:
            raise InvalidResult("Chinese English callback capture is not active")
        actual_inputs = [call["input"] for call in calls]
        if actual_inputs != expected_inputs:
            raise InvalidResult(
                "Chinese English callback inputs differ; actual={}, expected={}".format(
                    actual_inputs, expected_inputs
                )
            )
        return calls

    def abort(self) -> List[Dict[str, Any]]:
        calls = self._calls
        self._calls = None
        return [] if calls is None else calls

    def __call__(self, text: Any) -> str:
        if self._calls is None:
            raise InvalidResult("Chinese English callback ran outside one active case")
        if not isinstance(text, str) or not text or self._INPUT_PATTERN.fullmatch(text) is None:
            raise InvalidResult(
                "Chinese English callback input must be one non-empty pinned ASCII segment"
            )

        original_tokenize = self.engine.tokenize
        instance_attributes = vars(self.engine)
        had_instance_tokenize = "tokenize" in instance_attributes
        previous_instance_tokenize = instance_attributes.get("tokenize")
        tokenize_calls = 0
        backend_input: Optional[Dict[str, Any]] = None

        def capture_tokenize(
            preprocessed_text: Any, source_words: Any, features: Any
        ) -> Any:
            nonlocal tokenize_calls, backend_input
            tokenize_calls += 1
            if tokenize_calls != 1:
                raise InvalidResult(
                    "Chinese English callback invoked G2P.tokenize more than once"
                )
            preprocess_output = serialize_english_preprocess_output(
                preprocessed_text, source_words, features, True
            )
            raw_tokens = original_tokenize(
                preprocessed_text, source_words, features
            )
            backend_input = serialize_english_backend_input(
                preprocess_output, raw_tokens
            )
            return raw_tokens

        self.engine.tokenize = capture_tokenize
        try:
            result = self.engine(text, preprocess=True)
        finally:
            if had_instance_tokenize:
                self.engine.tokenize = previous_instance_tokenize
            else:
                del self.engine.tokenize

        if tokenize_calls != 1 or backend_input is None:
            raise InvalidResult(
                "Chinese English callback must invoke G2P.tokenize exactly once"
            )
        if not isinstance(result, tuple) or len(result) != 2:
            raise InvalidResult("Chinese English callback must return (phonemes, tokens)")
        phonemes, tokens = result
        if not isinstance(phonemes, str) or not isinstance(tokens, list):
            raise InvalidResult(
                "Chinese English callback must return a string and token list"
            )
        self._calls.append(
            {
                "backendInput": backend_input,
                "input": text,
                "phonemes": phonemes,
                "tokens": [
                    serialize_token(token, index)
                    for index, token in enumerate(tokens)
                ],
            }
        )
        return phonemes


class UpstreamRunner:
    """Lazy, cached dispatcher for the pinned upstream implementation."""

    def __init__(self, upstream_root: Path) -> None:
        if os.environ.get("PYTHONHASHSEED") != REQUIRED_HASH_SEED:
            raise InvalidInput(
                "set PYTHONHASHSEED={} before invoking the reference tool".format(
                    REQUIRED_HASH_SEED
                )
            )
        self.root = verify_upstream_checkout(upstream_root)
        loaded = sys.modules.get("misaki")
        if loaded is not None:
            loaded_file = getattr(loaded, "__file__", None)
            if loaded_file is None or not _path_is_within(Path(loaded_file).resolve(), self.root):
                raise UpstreamMismatch("a different misaki package is already imported")
        root_string = str(self.root)
        if root_string not in sys.path:
            sys.path.insert(0, root_string)
        self._engines: Dict[str, Any] = {}

    def run(self, case: FixtureCase) -> Any:
        if case.seed is not None:
            self._seed(case.seed)
        dispatch = {
            "en": self._run_english,
            "he": self._run_hebrew,
            "ja": self._run_japanese,
            "ko": self._run_korean,
            "vi": self._run_vietnamese,
            "zh": self._run_chinese,
        }
        try:
            run = dispatch[case.language]
        except KeyError as error:
            raise UnsupportedLanguage(case.language) from error
        return run(case)

    @staticmethod
    def _seed(seed: int) -> None:
        random.seed(seed)
        numpy = sys.modules.get("numpy")
        if numpy is not None and hasattr(numpy, "random"):
            numpy.random.seed(seed)
        torch = sys.modules.get("torch")
        if torch is not None and hasattr(torch, "manual_seed"):
            torch.manual_seed(seed)

    def _engine(self, key: str, factory: Callable[[], Any]) -> Any:
        if key not in self._engines:
            self._engines[key] = factory()
        return self._engines[key]

    def _run_japanese(self, case: FixtureCase) -> Any:
        if case.mode == "ja-num2kana":
            _check_options(case.options, {"dictionary"})
            dictionary = case.options.get("dictionary", "hiragana")
            if dictionary not in ("hiragana", "kanji", "romaji"):
                raise InvalidOptions("dictionary must be hiragana, kanji, or romaji")
            module = _import_upstream_module("misaki.num2kana")
            return module.Convert(case.input_text, dictionary), None
        if case.mode == "ja-kanji-number":
            _check_options(case.options, set())
            module = _import_upstream_module("misaki.num2kana")
            return module.ConvertKanji(case.input_text), None
        if case.mode not in ("cutlet", "pyopenjtalk"):
            raise UnsupportedMode("ja/{}".format(case.mode))
        _check_options(case.options, {"unk"})
        unk = _string_option(case.options, "unk", "❓")
        if case.mode == "cutlet":
            return self._run_cutlet(case, unk)
        module = _import_upstream_module("misaki.ja")
        key = "ja:{}:{}".format(case.mode, canonical_json_line(case.options))
        engine = self._engine(key, lambda: module.JAG2P(version=case.mode, unk=unk))

        original_frontend = module.pyopenjtalk.run_frontend
        raw_words = original_frontend(case.input_text)
        backend_input = serialize_pyopenjtalk_frontend(raw_words)

        def replay_frontend(text: str) -> Any:
            if text != case.input_text:
                raise InvalidResult("pyopenjtalk replay input changed during conversion")
            return copy.deepcopy(raw_words)

        module.pyopenjtalk.run_frontend = replay_frontend
        try:
            try:
                result = engine(case.input_text)
            except Exception as error:
                raise UpstreamExecutionFailure(error, backend_input) from error
        finally:
            module.pyopenjtalk.run_frontend = original_frontend
        if not isinstance(result, tuple) or len(result) != 2:
            raise InvalidResult("Japanese upstream call must return (phonemes, tokens)")
        return ReferenceResult(
            phonemes=result[0], tokens=result[1], backend_input=backend_input
        )

    def _run_cutlet(self, case: FixtureCase, unk: str) -> Any:
        _require_python_312("Japanese Cutlet")
        _require_cutlet_dependency_versions()
        with _offline_network_guard("Japanese Cutlet"):
            module = _import_upstream_module("misaki.ja")
            cutlet_module = _import_upstream_module("misaki.cutlet")
            key = "ja:cutlet:{}".format(canonical_json_line(case.options))
            engine = _initialize_cutlet_backend(
                lambda: self._engine(
                    key, lambda: module.JAG2P(version="cutlet", unk=unk)
                )
            )
            cutlet = getattr(engine, "cutlet", None)
            original_tagger = getattr(cutlet, "tagger", None)
            if cutlet is None or not callable(original_tagger):
                raise InvalidResult(
                    "Japanese cutlet mode must expose a callable Cutlet.tagger"
                )
            _require_cutlet_unidic_resource(original_tagger)
            jaconv = getattr(cutlet_module, "jaconv", None)
            kata2hira = getattr(jaconv, "kata2hira", None)
            ja_words = getattr(cutlet_module, "JA_WORDS", None)
            if not callable(kata2hira):
                raise InvalidResult("pinned Cutlet must expose jaconv.kata2hira")
            _require_cutlet_ja_words_resource(cutlet_module, ja_words)

            tagger_calls = 0
            backend_input: Optional[Dict[str, Any]] = None

            def capture_tagger(normalized_text: Any) -> Any:
                nonlocal tagger_calls, backend_input
                tagger_calls += 1
                if tagger_calls != 1:
                    raise InvalidResult(
                        "Cutlet.tagger was called more than once for one case"
                    )
                raw_words = list(original_tagger(normalized_text))
                backend_input = serialize_cutlet_backend_input(
                    normalized_text, raw_words, kata2hira, ja_words
                )
                return raw_words

            cutlet.tagger = capture_tagger
            try:
                try:
                    result = engine(case.input_text)
                except ReferenceToolError:
                    raise
                except Exception as error:
                    if backend_input is not None:
                        raise UpstreamExecutionFailure(error, backend_input) from error
                    raise
            finally:
                cutlet.tagger = original_tagger

            expected_tagger_calls = 0 if not case.input_text else 1
            if tagger_calls != expected_tagger_calls:
                raise InvalidResult(
                    "Cutlet.tagger call count is {}; expected {}".format(
                        tagger_calls, expected_tagger_calls
                    )
                )
            if backend_input is None:
                backend_input = serialize_cutlet_backend_input(
                    "", [], kata2hira, ja_words
                )
            if not isinstance(result, tuple) or len(result) != 2:
                raise InvalidResult(
                    "Japanese Cutlet upstream call must return (phonemes, tokens)"
                )
            if result[1] is not None:
                raise InvalidResult("Japanese Cutlet must return a null token list")
            return ReferenceResult(result[0], result[1], backend_input)

    def _run_english(self, case: FixtureCase) -> Any:
        modes = {
            "american-no-fallback": (False, "none"),
            "british-no-fallback": (True, "none"),
            "american-espeak-fallback": (False, "espeak"),
            "british-espeak-fallback": (True, "espeak"),
        }
        try:
            british, fallback_kind = modes[case.mode]
        except KeyError as error:
            raise UnsupportedMode("en/{}".format(case.mode)) from error
        _check_options(case.options, {"preprocess", "trf", "unk", "version"})
        preprocess = _bool_option(case.options, "preprocess", True)
        trf = _bool_option(case.options, "trf", False)
        unk = _string_option(case.options, "unk", "❓")
        version = case.options.get("version")
        if version is not None and not isinstance(version, str):
            raise InvalidOptions("version must be a string or null")
        _require_english_dependency_versions(trf)
        if fallback_kind == "espeak":
            _require_english_espeak_dependency_versions()
            _english_espeak_resource_identities()

        module = _import_upstream_module("misaki.en")
        model_name = "en_core_web_{}".format("trf" if trf else "sm")
        if not module.spacy.util.is_package(model_name):
            raise BackendUnavailable(
                "spaCy model {!r} must be installed before fixture generation".format(model_name)
            )

        def build() -> Any:
            if fallback_kind == "none":
                fallback: Any = _DisabledFallback()
            else:
                with _offline_network_guard("English eSpeak"):
                    espeak = _import_upstream_module("misaki.espeak")
                    fallback = espeak.EspeakFallback(
                        british=british, version=version
                    )
            engine = module.G2P(
                version=version,
                trf=trf,
                british=british,
                fallback=fallback,
                unk=unk,
            )
            if fallback_kind == "none":
                engine.fallback = None
            return engine

        constructor_options = dict(case.options)
        constructor_options.pop("preprocess", None)
        key = "en:{}:{}".format(case.mode, canonical_json_line(constructor_options))
        engine = self._engine(key, build)
        original_tokenize = engine.tokenize
        instance_attributes = vars(engine)
        had_instance_tokenize = "tokenize" in instance_attributes
        previous_instance_tokenize = instance_attributes.get("tokenize")
        tokenize_calls = 0
        backend_input: Optional[Dict[str, Any]] = None
        espeak_calls: Optional[List[Dict[str, Any]]] = None
        original_espeak_backend: Any = None

        if fallback_kind == "espeak":
            configured_fallback = getattr(engine, "fallback", None)
            original_espeak_backend = getattr(configured_fallback, "backend", None)
            if original_espeak_backend is None or not callable(
                getattr(original_espeak_backend, "phonemize", None)
            ):
                raise InvalidResult(
                    "English eSpeak fallback must expose backend.phonemize"
                )
            espeak_calls = []

            class CapturingEspeakBackend:
                def phonemize(self, texts: Any) -> Any:
                    if (
                        not isinstance(texts, list)
                        or len(texts) != 1
                        or not isinstance(texts[0], str)
                    ):
                        raise InvalidResult(
                            "English eSpeak backend must receive one string"
                        )
                    results = original_espeak_backend.phonemize(texts)
                    if not isinstance(results, list) or len(results) > 1 or any(
                        not isinstance(result, str) for result in results
                    ):
                        raise InvalidResult(
                            "English eSpeak backend must return zero or one string"
                        )
                    espeak_calls.append(
                        {
                            "rawPhones": results[0] if results else None,
                            "text": texts[0],
                        }
                    )
                    return results

            configured_fallback.backend = CapturingEspeakBackend()

        def capture_tokenize(text: Any, source_words: Any, features: Any) -> Any:
            nonlocal tokenize_calls, backend_input
            tokenize_calls += 1
            if tokenize_calls != 1:
                raise InvalidResult(
                    "English G2P.tokenize was called more than once for one case"
                )
            preprocess_output = serialize_english_preprocess_output(
                text, source_words, features, preprocess
            )
            raw_tokens = original_tokenize(text, source_words, features)
            backend_input = serialize_english_backend_input(
                preprocess_output, raw_tokens
            )
            return raw_tokens

        engine.tokenize = capture_tokenize
        try:
            try:
                guard = (
                    _offline_network_guard("English eSpeak")
                    if fallback_kind == "espeak"
                    else contextlib.nullcontext()
                )
                with guard:
                    result = engine(case.input_text, preprocess=preprocess)
            except ReferenceToolError:
                raise
            except Exception as error:
                if backend_input is not None:
                    if espeak_calls is not None:
                        backend_input = attach_english_espeak_calls(
                            backend_input, espeak_calls
                        )
                    raise UpstreamExecutionFailure(error, backend_input) from error
                raise
        finally:
            if had_instance_tokenize:
                engine.tokenize = previous_instance_tokenize
            else:
                del engine.tokenize
            if fallback_kind == "espeak":
                engine.fallback.backend = original_espeak_backend

        if tokenize_calls != 1 or backend_input is None:
            raise InvalidResult(
                "English upstream call must invoke G2P.tokenize exactly once"
            )
        if espeak_calls is not None:
            backend_input = attach_english_espeak_calls(backend_input, espeak_calls)
        if not isinstance(result, tuple) or len(result) != 2:
            raise InvalidResult("English upstream call must return (phonemes, tokens)")
        return ReferenceResult(
            phonemes=result[0], tokens=result[1], backend_input=backend_input
        )

    def _run_korean(self, case: FixtureCase) -> Any:
        if case.mode != "g2pkc-default":
            raise UnsupportedMode("ko/{}".format(case.mode))
        _check_options(case.options, set())
        nltk = _import_upstream_module("nltk")
        _require_nltk_cmudict_resource(nltk)

        original_download = nltk.download

        def reject_runtime_download(*_args: Any, **_kwargs: Any) -> None:
            raise BackendUnavailable(
                "Korean oracle attempted an NLTK runtime download; provision "
                "all resources before fixture generation"
            )

        nltk.download = reject_runtime_download
        try:
            module = _import_upstream_module("misaki.ko")
            engine = self._engine("ko:g2pkc-default", module.KOG2P)
            g2pk = getattr(engine, "g2pk", None)
            original_mecab = getattr(g2pk, "mecab", None)
            if original_mecab is None or not callable(
                getattr(original_mecab, "pos", None)
            ):
                raise InvalidResult(
                    "Korean KOG2P must expose g2pk.mecab.pos for replay capture"
                )
            original_cmu = getattr(g2pk, "cmu", None)
            if (
                original_cmu is None
                or not hasattr(original_cmu, "__contains__")
                or not hasattr(original_cmu, "__getitem__")
            ):
                raise InvalidResult(
                    "Korean KOG2P must expose a CMUdict-compatible g2pk.cmu mapping"
                )

            analyze_calls = 0
            backend_input: Optional[Dict[str, Any]] = None
            cmu_lookups: List[Dict[str, Any]] = []

            class CapturingCmu:
                def __contains__(self, key: Any) -> bool:
                    if not isinstance(key, str):
                        raise InvalidResult(
                            "Korean CMUdict lookup key must be a string"
                        )
                    present = key in original_cmu
                    first_pronunciation: Optional[List[str]] = None
                    if present:
                        pronunciations = original_cmu[key]
                        if (
                            not isinstance(pronunciations, list)
                            or not pronunciations
                            or not isinstance(pronunciations[0], list)
                            or not pronunciations[0]
                            or any(
                                not isinstance(symbol, str) or not symbol
                                for symbol in pronunciations[0]
                            )
                        ):
                            raise InvalidResult(
                                "Korean CMUdict entry {!r} must contain a non-empty "
                                "first ARPABET pronunciation".format(key)
                            )
                        first_pronunciation = list(pronunciations[0])
                    cmu_lookups.append(
                        {"arpabet": first_pronunciation, "key": key}
                    )
                    return present

                def __getitem__(self, key: Any) -> Any:
                    return original_cmu[key]

            class CapturingMecab:
                def pos(self, text: Any) -> Any:
                    nonlocal analyze_calls, backend_input
                    analyze_calls += 1
                    if analyze_calls != 1:
                        raise InvalidResult(
                            "Korean MeCab.pos was called more than once for one case"
                        )
                    tokens = original_mecab.pos(text)
                    backend_input = serialize_korean_backend_input(
                        text, tokens, cmu_lookups
                    )
                    return tokens

            g2pk.mecab = CapturingMecab()
            g2pk.cmu = CapturingCmu()
            try:
                try:
                    with contextlib.redirect_stdout(io.StringIO()):
                        result = engine(case.input_text)
                except ReferenceToolError:
                    raise
                except Exception as error:
                    if backend_input is not None:
                        raise UpstreamExecutionFailure(error, backend_input) from error
                    raise
            finally:
                g2pk.cmu = original_cmu
                g2pk.mecab = original_mecab
        finally:
            nltk.download = original_download

        if analyze_calls != 1 or backend_input is None:
            raise InvalidResult(
                "Korean upstream call must invoke MeCab.pos exactly once"
            )
        if not isinstance(result, tuple) or len(result) != 2:
            raise InvalidResult("Korean upstream call must return (phonemes, tokens)")
        if result[1] is not None:
            raise InvalidResult("Korean KOG2P must return a null token list")
        return ReferenceResult(
            phonemes=result[0], tokens=result[1], backend_input=backend_input
        )

    def _run_chinese(self, case: FixtureCase) -> Any:
        callback_mode = case.mode == "frontend-1.1-en-small-no-fallback"
        versions = {
            "legacy": None,
            "frontend-1.1": "1.1",
            "frontend-1.1-en-small-no-fallback": "1.1",
        }
        try:
            version = versions[case.mode]
        except KeyError as error:
            raise UnsupportedMode("zh/{}".format(case.mode)) from error
        allowed_options = (
            {"englishDialect", "englishVersion", "unk"}
            if callback_mode
            else {"unk"}
        )
        _check_options(case.options, allowed_options)
        unk = _string_option(case.options, "unk", "❓")
        english_dialect: Optional[str] = None
        english_version: Optional[str] = None
        if callback_mode:
            english_dialect = _string_option(
                case.options, "englishDialect", "american"
            )
            if english_dialect not in ("american", "british"):
                raise InvalidOptions(
                    "englishDialect must be american or british"
                )
            english_version = case.options.get("englishVersion")
            if english_version not in (None, "2.0"):
                raise InvalidOptions("englishVersion must be null or 2.0")
        _require_python_312()
        _require_chinese_dependency_versions(case.mode)
        if callback_mode:
            _require_english_dependency_versions(False)

        with _offline_network_guard():
            module = _import_upstream_module("misaki.zh")
            _require_jieba_default_dict_resource(module.jieba)
            key = "zh:{}:{}".format(case.mode, canonical_json_line(case.options))

            def build() -> Any:
                english_callback: Optional[_CapturingChineseEnglishCallback] = None
                if callback_mode:
                    english_module = _import_upstream_module("misaki.en")
                    if not english_module.spacy.util.is_package("en_core_web_sm"):
                        raise BackendUnavailable(
                            "spaCy model 'en_core_web_sm' must be installed before "
                            "Chinese callback fixture generation"
                        )
                    english_engine = english_module.G2P(
                        version=english_version,
                        trf=False,
                        british=english_dialect == "british",
                        fallback=_DisabledFallback(),
                        unk=unk,
                    )
                    english_engine.fallback = None
                    english_callback = _CapturingChineseEnglishCallback(
                        english_engine
                    )
                with contextlib.redirect_stdout(io.StringIO()):
                    chinese_engine = module.ZHG2P(
                        version=version,
                        unk=unk,
                        en_callable=english_callback,
                    )
                return chinese_engine, english_callback

            engine, english_callback = self._engine(key, build)
            if case.mode == "legacy":
                return self._run_chinese_legacy(case, module, engine)
            frontend_module = _import_upstream_module("misaki.zh_frontend")
            tone_module = _import_upstream_module("misaki.tone_sandhi")
            if not callback_mode:
                return self._run_chinese_frontend(
                    case, module, frontend_module, tone_module, engine
                )
            if not isinstance(english_callback, _CapturingChineseEnglishCallback):
                raise InvalidResult(
                    "Chinese English callback mode has no callback capture"
                )
            english_callback.begin()
            try:
                result = self._run_chinese_frontend(
                    case, module, frontend_module, tone_module, engine
                )
            except Exception:
                english_callback.abort()
                raise

            backend_input = result.backend_input
            if not isinstance(backend_input, dict):
                english_callback.abort()
                raise InvalidResult(
                    "Chinese English callback mode has no frontend backend input"
                )
            normalization = backend_input.get("normalization")
            expected_inputs: List[str] = []
            if normalization is not None:
                if not isinstance(normalization, dict) or not isinstance(
                    normalization.get("output"), str
                ):
                    english_callback.abort()
                    raise InvalidResult(
                        "Chinese English callback normalization is malformed"
                    )
                mapped = module.ZHG2P.map_punctuation(normalization["output"])
                for english, chinese in re.findall(
                    r"([A-Za-z '\-]*[A-Za-z][A-Za-z '\-]*)|([^A-Za-z]+)",
                    mapped,
                ):
                    english, chinese = english.strip(), chinese.strip()
                    if not chinese:
                        expected_inputs.append(english)
            calls = english_callback.finish(expected_inputs)
            backend_input["english"] = {
                "calls": calls,
                "dialect": english_dialect,
                "fallback": "none",
                "model": "en_core_web_sm",
                "preprocess": True,
                "version": english_version,
            }
            backend_input["kind"] = CHINESE_FRONTEND_ENGLISH_BACKEND_INPUT_KIND
            backend_input[
                "schemaVersion"
            ] = CHINESE_ENGLISH_BACKEND_INPUT_SCHEMA_VERSION
            return result

    @staticmethod
    def _run_chinese_legacy(case: FixtureCase, module: Any, engine: Any) -> Any:
        backend_input: Dict[str, Any] = {
            "kind": CHINESE_LEGACY_BACKEND_INPUT_KIND,
            "normalization": None,
            "runs": [],
            "schemaVersion": CHINESE_BACKEND_INPUT_SCHEMA_VERSION,
        }
        normalization_calls = 0
        pending_words: List[Dict[str, Any]] = []
        original_transform = module.cn2an.transform
        original_lcut = module.jieba.lcut
        original_lazy_pinyin = module.lazy_pinyin

        def capture_transform(
            text: Any, mode: Any, *args: Any, **kwargs: Any
        ) -> Any:
            nonlocal normalization_calls
            normalization_calls += 1
            if normalization_calls != 1:
                raise InvalidResult(
                    "Chinese cn2an.transform was called more than once"
                )
            if args or kwargs:
                raise InvalidResult(
                    "Chinese cn2an.transform received unexpected arguments"
                )
            normalized = original_transform(text, mode)
            backend_input["normalization"] = serialize_chinese_normalization(
                text, mode, normalized
            )
            return normalized

        def capture_lcut(text: Any, *args: Any, **kwargs: Any) -> Any:
            if not isinstance(text, str):
                raise InvalidResult("legacy Chinese jieba.lcut input must be a string")
            if args or kwargs != {"cut_all": False}:
                raise InvalidResult(
                    "legacy Chinese jieba.lcut must use cut_all=False"
                )
            raw_words = original_lcut(text, *args, **kwargs)
            words = _serialize_string_list(
                raw_words, "legacy Chinese jieba.lcut output"
            )
            run = {"input": text, "words": []}
            for word in words:
                word_record: Dict[str, Any] = {"pinyin": None, "word": word}
                run["words"].append(word_record)
                pending_words.append(word_record)
            backend_input["runs"].append(run)
            return raw_words

        def capture_lazy_pinyin(
            text: Any, *args: Any, **kwargs: Any
        ) -> Any:
            if args or set(kwargs) != {"neutral_tone_with_five", "style"}:
                raise InvalidResult(
                    "legacy Chinese lazy_pinyin arguments differ from the pin"
                )
            if kwargs["style"] != module.Style.TONE3:
                raise InvalidResult("legacy Chinese lazy_pinyin must use TONE3")
            if not pending_words:
                raise InvalidResult(
                    "legacy Chinese lazy_pinyin ran without a queued jieba word"
                )
            word_record = pending_words.pop(0)
            if text != word_record["word"]:
                raise InvalidResult(
                    "legacy Chinese pinyin word order differs from jieba output"
                )
            output = original_lazy_pinyin(text, *args, **kwargs)
            word_record["pinyin"] = serialize_chinese_pinyin_call(
                text,
                output,
                stage="legacy-word",
                style="tone3",
                neutral_tone_with_five=kwargs["neutral_tone_with_five"],
            )
            return output

        module.cn2an.transform = capture_transform
        module.jieba.lcut = capture_lcut
        module.lazy_pinyin = capture_lazy_pinyin
        try:
            try:
                result = engine(case.input_text)
            except ReferenceToolError:
                raise
            except Exception as error:
                raise UpstreamExecutionFailure(error, backend_input) from error
        finally:
            module.lazy_pinyin = original_lazy_pinyin
            module.jieba.lcut = original_lcut
            module.cn2an.transform = original_transform

        expected_normalization_calls = 1 if case.input_text.strip() else 0
        if normalization_calls != expected_normalization_calls:
            raise InvalidResult(
                "legacy Chinese normalization call count is {}; expected {}".format(
                    normalization_calls, expected_normalization_calls
                )
            )
        if pending_words:
            raise InvalidResult(
                "legacy Chinese pipeline did not request pinyin for every jieba word"
            )
        if not isinstance(result, tuple) or len(result) != 2:
            raise InvalidResult("Chinese upstream call must return (phonemes, tokens)")
        if result[1] is not None:
            raise InvalidResult("legacy Chinese ZHG2P must return a null token list")
        return ReferenceResult(result[0], result[1], backend_input)

    @staticmethod
    def _run_chinese_frontend(
        case: FixtureCase,
        module: Any,
        frontend_module: Any,
        tone_module: Any,
        engine: Any,
    ) -> Any:
        backend_input: Dict[str, Any] = {
            "frontendCalls": [],
            "kind": CHINESE_FRONTEND_BACKEND_INPUT_KIND,
            "normalization": None,
            "schemaVersion": CHINESE_BACKEND_INPUT_SCHEMA_VERSION,
        }
        normalization_calls = 0
        active_call: Optional[Dict[str, Any]] = None
        original_transform = module.cn2an.transform
        original_posseg_lcut = frontend_module.psg.lcut
        original_frontend_lazy_pinyin = frontend_module.lazy_pinyin
        original_tone_lazy_pinyin = tone_module.lazy_pinyin
        original_cut_for_search = tone_module.jieba.cut_for_search

        def capture_transform(
            text: Any, mode: Any, *args: Any, **kwargs: Any
        ) -> Any:
            nonlocal normalization_calls
            normalization_calls += 1
            if normalization_calls != 1:
                raise InvalidResult(
                    "Chinese cn2an.transform was called more than once"
                )
            if args or kwargs:
                raise InvalidResult(
                    "Chinese cn2an.transform received unexpected arguments"
                )
            normalized = original_transform(text, mode)
            backend_input["normalization"] = serialize_chinese_normalization(
                text, mode, normalized
            )
            return normalized

        def capture_posseg_lcut(text: Any, *args: Any, **kwargs: Any) -> Any:
            nonlocal active_call
            if args or kwargs:
                raise InvalidResult(
                    "Chinese frontend jieba.posseg.lcut arguments differ from the pin"
                )
            segments = original_posseg_lcut(text, *args, **kwargs)
            serialized = serialize_chinese_posseg(text, segments)
            active_call = {
                "externalCalls": [],
                "input": serialized["input"],
                "segmentation": serialized["segments"],
            }
            backend_input["frontendCalls"].append(active_call)
            return segments

        def require_active_call() -> Dict[str, Any]:
            if active_call is None:
                raise InvalidResult(
                    "Chinese frontend backend ran before POS segmentation"
                )
            return active_call

        def capture_tone_lazy_pinyin(
            text: Any, *args: Any, **kwargs: Any
        ) -> Any:
            if args or set(kwargs) != {"neutral_tone_with_five", "style"}:
                raise InvalidResult(
                    "tone-sandhi lazy_pinyin arguments differ from the pin"
                )
            if kwargs["style"] != tone_module.Style.FINALS_TONE3:
                raise InvalidResult(
                    "tone-sandhi lazy_pinyin must use FINALS_TONE3"
                )
            output = original_tone_lazy_pinyin(text, *args, **kwargs)
            require_active_call()["externalCalls"].append(
                serialize_chinese_pinyin_call(
                    text,
                    output,
                    stage="tone-premerge",
                    style="finals-tone3",
                    neutral_tone_with_five=kwargs["neutral_tone_with_five"],
                )
            )
            return output

        def capture_frontend_lazy_pinyin(
            text: Any, *args: Any, **kwargs: Any
        ) -> Any:
            if args or set(kwargs) != {"neutral_tone_with_five", "style"}:
                raise InvalidResult(
                    "frontend lazy_pinyin arguments differ from the pin"
                )
            style_value = kwargs["style"]
            if style_value == frontend_module.Style.INITIALS:
                style = "initials"
            elif style_value == frontend_module.Style.FINALS_TONE3:
                style = "finals-tone3"
            else:
                raise InvalidResult(
                    "frontend lazy_pinyin used an unexpected pinyin style"
                )
            output = original_frontend_lazy_pinyin(text, *args, **kwargs)
            require_active_call()["externalCalls"].append(
                serialize_chinese_pinyin_call(
                    text,
                    output,
                    stage="frontend-render",
                    style=style,
                    neutral_tone_with_five=kwargs["neutral_tone_with_five"],
                )
            )
            return output

        def capture_cut_for_search(
            text: Any, *args: Any, **kwargs: Any
        ) -> Any:
            if args or kwargs:
                raise InvalidResult(
                    "Chinese jieba.cut_for_search arguments differ from the pin"
                )
            segments = list(original_cut_for_search(text, *args, **kwargs))
            require_active_call()["externalCalls"].append(
                serialize_chinese_search_segments(text, segments)
            )
            return iter(segments)

        module.cn2an.transform = capture_transform
        frontend_module.psg.lcut = capture_posseg_lcut
        frontend_module.lazy_pinyin = capture_frontend_lazy_pinyin
        tone_module.lazy_pinyin = capture_tone_lazy_pinyin
        tone_module.jieba.cut_for_search = capture_cut_for_search
        try:
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    result = engine(case.input_text)
            except ReferenceToolError:
                raise
            except Exception as error:
                raise UpstreamExecutionFailure(error, backend_input) from error
        finally:
            tone_module.jieba.cut_for_search = original_cut_for_search
            tone_module.lazy_pinyin = original_tone_lazy_pinyin
            frontend_module.lazy_pinyin = original_frontend_lazy_pinyin
            frontend_module.psg.lcut = original_posseg_lcut
            module.cn2an.transform = original_transform

        expected_normalization_calls = 1 if case.input_text.strip() else 0
        if normalization_calls != expected_normalization_calls:
            raise InvalidResult(
                "Chinese frontend normalization call count is {}; expected {}".format(
                    normalization_calls, expected_normalization_calls
                )
            )
        if not isinstance(result, tuple) or len(result) != 2:
            raise InvalidResult("Chinese upstream call must return (phonemes, tokens)")
        if result[1] is not None:
            raise InvalidResult(
                "Chinese frontend-1.1 ZHG2P must return a null token list"
            )
        return ReferenceResult(result[0], result[1], backend_input)

    def _run_vietnamese(self, case: FixtureCase) -> Any:
        modes = {
            "north-no-english-fallback": "north",
            "central-no-english-fallback": "central",
            "south-no-english-fallback": "south",
        }
        try:
            dialect = modes[case.mode]
        except KeyError as error:
            raise UnsupportedMode("vi/{}".format(case.mode)) from error
        allowed = {
            "cao",
            "clean_abbr",
            "clean_acronym",
            "glottal",
            "palatals",
            "pham",
            "substr_tokenize",
            "tone_type",
        }
        _check_options(case.options, allowed)
        kwargs = {
            "cao": _bool_option(case.options, "cao", False),
            "clean_abbr": _bool_option(case.options, "clean_abbr", True),
            "clean_acronym": _bool_option(case.options, "clean_acronym", True),
            "dialect": dialect,
            "enable_en_g2p": False,
            "en_g2p_kwargs": {},
            "glottal": _bool_option(case.options, "glottal", False),
            "palatals": _bool_option(case.options, "palatals", False),
            "pham": _bool_option(case.options, "pham", False),
            "substr_tokenize": _bool_option(
                case.options, "substr_tokenize", True
            ),
        }
        tone_type = case.options.get("tone_type", 0)
        if isinstance(tone_type, bool) or not isinstance(tone_type, int):
            raise InvalidOptions("tone_type must be an integer")
        kwargs["tone_type"] = tone_type

        _require_python_311("Vietnamese")
        _require_vietnamese_dependency_versions()
        with _offline_network_guard("Vietnamese"):
            module = _import_vietnamese_no_english_module(self.root)
        key = "vi:{}:{}".format(case.mode, canonical_json_line(case.options))
        with _offline_network_guard("Vietnamese"):
            engine = self._engine(key, lambda: module.VIG2P(**kwargs))

            original_tokenize = module.tokenize
            backend_input: Optional[Dict[str, Any]] = None
            call_count = 0

            def capture_tokenize(text: Any) -> Any:
                nonlocal backend_input, call_count
                call_count += 1
                if call_count != 1:
                    raise InvalidResult(
                        "Vietnamese conversion called underthesea tokenizer more than once"
                    )
                tokens = original_tokenize(text)
                backend_input = serialize_vietnamese_backend_input(text, tokens)
                return tokens

            module.tokenize = capture_tokenize
            try:
                result = engine(case.input_text)
            except ReferenceToolError:
                raise
            except Exception as error:
                if backend_input is not None:
                    raise UpstreamExecutionFailure(error, backend_input) from error
                raise
            finally:
                module.tokenize = original_tokenize

        if call_count != 1 or backend_input is None:
            raise InvalidResult(
                "Vietnamese conversion must call underthesea tokenizer exactly once"
            )
        if not isinstance(result, tuple) or len(result) != 2:
            raise InvalidResult("Vietnamese upstream call must return (phonemes, tokens)")
        if result[1] is None:
            raise InvalidResult("Vietnamese upstream call must return a token list")
        return ReferenceResult(result[0], result[1], backend_input)

    def _run_hebrew(self, case: FixtureCase) -> Any:
        if case.mode != "default":
            raise UnsupportedMode("he/{}".format(case.mode))
        _check_options(case.options, {"preserve_punctuation", "preserve_stress"})
        preserve_punctuation = _bool_option(
            case.options, "preserve_punctuation", True
        )
        preserve_stress = _bool_option(case.options, "preserve_stress", True)
        _require_python_312("Hebrew")
        _require_hebrew_dependency_versions()
        with _offline_network_guard("Hebrew"):
            module = _import_upstream_module("misaki.he")
            with contextlib.redirect_stdout(io.StringIO()):
                engine = self._engine("he:default", module.HEG2P)
                result = engine(
                    case.input_text,
                    preserve_punctuation=preserve_punctuation,
                    preserve_stress=preserve_stress,
                )
        if not isinstance(result, str):
            raise InvalidResult("Hebrew HEG2P must return a string")
        return result


def _check_options(options: Dict[str, Any], allowed: Set[str]) -> None:
    unknown = sorted(set(options) - allowed)
    if unknown:
        raise InvalidOptions("unknown options: {}".format(", ".join(unknown)))


def _bool_option(options: Dict[str, Any], name: str, default: bool) -> bool:
    value = options.get(name, default)
    if not isinstance(value, bool):
        raise InvalidOptions("{} must be a boolean".format(name))
    return value


def _string_option(options: Dict[str, Any], name: str, default: str) -> str:
    value = options.get(name, default)
    if not isinstance(value, str):
        raise InvalidOptions("{} must be a string".format(name))
    return value


_BACKEND_DISTRIBUTIONS = {
    "en": ("num2words", "spacy"),
    "he": tuple(HEBREW_LOCKED_DISTRIBUTIONS),
    "ko": ("jamo", "nltk", "python-mecab-ko", "python-mecab-ko-dic"),
    "vi": tuple(VIETNAMESE_LOCKED_DISTRIBUTIONS),
    "zh": (
        "addict",
        "cn2an",
        "jieba",
        "ordered-set",
        "proces",
        "pypinyin",
        "regex",
    ),
}


@lru_cache(maxsize=1)
def _english_espeak_resource_identities() -> Tuple[str, str]:
    with _offline_network_guard("English eSpeak"):
        loader = importlib.import_module("espeakng_loader")
        library_path = Path(loader.get_library_path()).resolve()
        data_path = Path(loader.get_data_path()).resolve()
    if not library_path.is_file():
        raise BackendUnavailable("eSpeak-ng library file is missing")
    library_identity = "sha256:{}+bytes:{}".format(
        _sha256_file(library_path), library_path.stat().st_size
    )
    data_sha256, data_files, data_bytes = _directory_tree_fingerprint(
        str(data_path)
    )
    data_identity = "sha256:{}+files:{}+bytes:{}".format(
        data_sha256, data_files, data_bytes
    )
    return library_identity, data_identity


def backend_versions(case: FixtureCase) -> Dict[str, Optional[str]]:
    distributions = list(_BACKEND_DISTRIBUTIONS.get(case.language, ()))
    if case.language == "en":
        distributions.append(
            "en-core-web-trf" if case.options.get("trf", False) else "en-core-web-sm"
        )
        if "espeak" in case.mode:
            distributions.extend(ENGLISH_ESPEAK_LOCKED_DISTRIBUTIONS)
    elif case.language == "he" and sys.platform == "win32":
        distributions.extend(HEBREW_WINDOWS_LOCKED_DISTRIBUTIONS)
    elif case.language == "ja" and case.mode == "cutlet":
        distributions.extend(CUTLET_LOCKED_DISTRIBUTIONS)
    elif case.language == "ja" and case.mode == "pyopenjtalk":
        distributions.append("pyopenjtalk")
    elif case.language == "zh" and case.mode in (
        "frontend-1.1",
        "frontend-1.1-en-small-no-fallback",
    ):
        distributions.append("pypinyin-dict")
        if case.mode == "frontend-1.1-en-small-no-fallback":
            distributions.extend(("en-core-web-sm", "num2words", "spacy"))

    versions: Dict[str, Optional[str]] = {}
    for distribution in sorted(set(distributions)):
        try:
            versions[distribution] = importlib_metadata.version(distribution)
        except importlib_metadata.PackageNotFoundError:
            versions[distribution] = None
    if case.language == "en" and "espeak" in case.mode:
        versions["python"] = platform.python_version()
        try:
            library_identity, data_identity = (
                _english_espeak_resource_identities()
            )
        except (ImportError, ModuleNotFoundError, OSError, BackendUnavailable):
            library_identity = None
            data_identity = None
        versions["espeakng-library"] = library_identity
        versions["espeakng-data"] = data_identity
    elif case.language == "ko":
        try:
            nltk = importlib.import_module("nltk")
            cmudict_sha256 = _nltk_cmudict_sha256(nltk)
        except (ImportError, ModuleNotFoundError, BackendUnavailable):
            cmudict_sha256 = None
        if cmudict_sha256 is None:
            versions["nltk-cmudict"] = None
        elif cmudict_sha256 == NLTK_CMUDICT_SHA256:
            versions["nltk-cmudict"] = NLTK_CMUDICT_IDENTITY
        else:
            versions["nltk-cmudict"] = "unexpected-sha256:{}".format(
                cmudict_sha256
            )
    elif case.language == "zh":
        versions["python"] = platform.python_version()
        try:
            with _offline_network_guard():
                jieba = importlib.import_module("jieba")
                jieba_sha256 = _jieba_default_dict_sha256(jieba)
        except (ImportError, ModuleNotFoundError, BackendUnavailable):
            jieba_sha256 = None
        if jieba_sha256 is None:
            versions["jieba-default-dict"] = None
        elif jieba_sha256 == JIEBA_DEFAULT_DICT_SHA256:
            versions["jieba-default-dict"] = JIEBA_DEFAULT_DICT_IDENTITY
        else:
            versions["jieba-default-dict"] = "unexpected-sha256:{}".format(
                jieba_sha256
            )
    elif case.language == "he":
        versions["python"] = platform.python_version()
    elif case.language == "vi":
        versions["python"] = platform.python_version()
        versions["unicode-data"] = unicodedata.unidata_version
    elif case.language == "ja" and case.mode == "cutlet":
        versions["python"] = platform.python_version()
        versions["unicode-data"] = unicodedata.unidata_version
        try:
            cutlet_module = importlib.import_module("misaki.cutlet")
            versions["misaki-ja-words"] = _require_cutlet_ja_words_resource(
                cutlet_module, getattr(cutlet_module, "JA_WORDS", None)
            )
        except (
            ImportError,
            ModuleNotFoundError,
            BackendUnavailable,
            InvalidResult,
        ):
            versions["misaki-ja-words"] = None
        try:
            cutlet_module = importlib.import_module("misaki.cutlet")
            tagger_factory = getattr(cutlet_module, "Tagger", None)
            if not callable(tagger_factory):
                raise BackendUnavailable(
                    "pinned Cutlet module has no fugashi Tagger constructor"
                )
            tagger = _initialize_cutlet_backend(tagger_factory)
            versions.update(_require_cutlet_unidic_resource(tagger))
        except (
            ImportError,
            ModuleNotFoundError,
            OSError,
            BackendUnavailable,
            InvalidResult,
        ):
            versions["fugashi-system-dictionary"] = None
            versions["unidic-dictionary-tree"] = None
            versions["unidic-dictionary-version"] = None
    return versions


def _normalize_result(
    result: Any,
) -> Tuple[str, Optional[List[Any]], Optional[Dict[str, Any]]]:
    backend_input: Optional[Dict[str, Any]] = None
    if isinstance(result, ReferenceResult):
        phonemes, tokens = result.phonemes, result.tokens
        backend_input = result.backend_input
    elif isinstance(result, str):
        phonemes, tokens = result, None
    elif isinstance(result, tuple) and len(result) == 2:
        phonemes, tokens = result
    else:
        raise InvalidResult("upstream call must return a string or (phonemes, tokens)")
    if not isinstance(phonemes, str):
        raise InvalidResult("upstream phonemes must be a string")
    if tokens is not None and not isinstance(tokens, list):
        raise InvalidResult("upstream tokens must be null or a list")
    if backend_input is not None and not isinstance(backend_input, dict):
        raise InvalidResult("backend input must be a JSON object")
    return phonemes, tokens, backend_input


def error_category(error: Exception) -> str:
    if isinstance(error, ReferenceToolError):
        return error.category
    if isinstance(error, (ImportError, ModuleNotFoundError, FileNotFoundError, OSError)):
        return BackendUnavailable.category
    return "upstreamFailure"


def build_fixture_record(
    case: FixtureCase,
    run: Callable[[FixtureCase], Any],
    version_provider: Callable[[FixtureCase], Dict[str, Optional[str]]] = backend_versions,
    error_reporter: Optional[Callable[[FixtureCase, Exception, str], None]] = None,
) -> Dict[str, Any]:
    record: Dict[str, Any] = {
        "backendVersions": version_provider(case),
        "input": case.input_text,
        "language": case.language,
        "mode": case.mode,
        "options": case.options,
        "schemaVersion": SCHEMA_VERSION,
        "upstreamCommit": UPSTREAM_COMMIT,
        "upstreamRepository": UPSTREAM_REPOSITORY,
        "upstreamVersion": UPSTREAM_VERSION,
    }
    if case.case_id is not None:
        record["caseId"] = case.case_id
    if case.seed is not None:
        record["seed"] = case.seed

    try:
        phonemes, tokens, backend_input = _normalize_result(run(case))
        serialized_tokens = (
            None
            if tokens is None
            else [serialize_token(token, index) for index, token in enumerate(tokens)]
        )
        record["phonemes"] = phonemes
        record["tokens"] = serialized_tokens
        if backend_input is not None:
            record["backendInput"] = canonicalize(backend_input, "$.backendInput")
    except Exception as error:  # One bad oracle case must not erase the corpus.
        category = error_category(error)
        if isinstance(error, UpstreamExecutionFailure):
            record["backendInput"] = canonicalize(
                error.backend_input, "$.backendInput"
            )
        record["error"] = {"category": category}
        record["phonemes"] = None
        record["tokens"] = None
        if error_reporter is not None:
            error_reporter(case, error, category)
    return record


def render_cases(
    cases: Iterable[FixtureCase],
    run: Callable[[FixtureCase], Any],
    version_provider: Callable[[FixtureCase], Dict[str, Optional[str]]] = backend_versions,
    error_reporter: Optional[Callable[[FixtureCase, Exception, str], None]] = None,
) -> str:
    return "".join(
        canonical_json_line(
            build_fixture_record(case, run, version_provider, error_reporter)
        )
        for case in cases
    )


def write_fixture(path: Path, content: str, accept: bool) -> None:
    destination = path.expanduser().resolve()
    if destination.exists() and not accept:
        raise AcceptanceRequired(
            "refusing to overwrite {!s} without --accept".format(destination)
        )
    if not destination.parent.is_dir():
        raise InvalidInput("output directory does not exist: {!s}".format(destination.parent))

    temporary_name: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="",
            dir=str(destination.parent),
            prefix=".reference-",
            suffix=".jsonl",
            delete=False,
        ) as temporary:
            temporary_name = temporary.name
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, destination)
        temporary_name = None
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def verify_fixture(expected_path: Path, actual: str) -> Tuple[bool, str]:
    try:
        expected_bytes = expected_path.read_bytes()
    except OSError as error:
        raise InvalidInput("cannot read expected fixture {!s}".format(expected_path)) from error
    actual_bytes = actual.encode("utf-8")
    if expected_bytes == actual_bytes:
        return True, ""
    try:
        expected = expected_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise InvalidInput("expected fixture is not UTF-8: {!s}".format(expected_path)) from error
    diff = "".join(
        difflib.unified_diff(
            expected.splitlines(keepends=True),
            actual.splitlines(keepends=True),
            fromfile=str(expected_path),
            tofile="generated-reference",
        )
    )
    diagnostic = first_difference_diagnostic(expected, actual)
    return False, diagnostic + "\n" + diff


def _first_difference_offset(expected: str, actual: str) -> int:
    shared_length = min(len(expected), len(actual))
    for index in range(shared_length):
        if expected[index] != actual[index]:
            return index
    return shared_length


def _describe_code_point(text: str, index: int) -> str:
    if index >= len(text):
        return "<end of text>"
    character = text[index]
    name = unicodedata.name(character, "NO UNICODE NAME")
    return "U+{:04X} {} ({!r})".format(ord(character), name, character)


def _surrounding_context(text: str, index: int, radius: int = 16) -> str:
    start = max(0, index - radius)
    end = min(len(text), index + radius + 1)
    before = text[start:index]
    differing = "<EOF>" if index >= len(text) else text[index]
    after = "" if index >= len(text) else text[index + 1 : end]
    marked = before + "⟦" + differing + "⟧" + after
    return json.dumps(marked, ensure_ascii=False)


def _jsonl_record(text: str, record_index: int) -> Optional[Dict[str, Any]]:
    lines = text.splitlines()
    if record_index >= len(lines):
        return None
    try:
        value = json.loads(lines[record_index])
    except (json.JSONDecodeError, TypeError):
        return None
    return value if isinstance(value, dict) else None


def _differing_token_index(
    expected: str, actual: str, record_index: int
) -> Optional[int]:
    expected_record = _jsonl_record(expected, record_index)
    actual_record = _jsonl_record(actual, record_index)
    if expected_record is None or actual_record is None:
        return None
    expected_tokens = expected_record.get("tokens")
    actual_tokens = actual_record.get("tokens")
    if not isinstance(expected_tokens, list) or not isinstance(actual_tokens, list):
        return None
    shared_length = min(len(expected_tokens), len(actual_tokens))
    for index in range(shared_length):
        if expected_tokens[index] != actual_tokens[index]:
            return index
    if len(expected_tokens) != len(actual_tokens):
        return shared_length
    return None


def first_difference_diagnostic(expected: str, actual: str) -> str:
    """Describe the first exact code-point difference in two JSONL strings."""

    offset = _first_difference_offset(expected, actual)
    expected_record_index = expected[:offset].count("\n")
    actual_record_index = actual[:offset].count("\n")
    record_index = min(expected_record_index, actual_record_index)
    token_index = _differing_token_index(expected, actual, record_index)
    lines = [
        "first difference at code-point offset {} (JSONL record {}):".format(
            offset, record_index + 1
        ),
        "  expected: {}; context={}".format(
            _describe_code_point(expected, offset),
            _surrounding_context(expected, offset),
        ),
        "  actual:   {}; context={}".format(
            _describe_code_point(actual, offset),
            _surrounding_context(actual, offset),
        ),
    ]
    if token_index is not None:
        lines.append("  JSON token index (zero-based): {}".format(token_index))
    return "\n".join(lines)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common(command: argparse.ArgumentParser) -> None:
        command.add_argument("--input", required=True, type=Path)
        command.add_argument("--upstream-root", required=True, type=Path)
        command.add_argument("--verbose-errors", action="store_true")

    verify = subparsers.add_parser("verify", help="compare without writing")
    add_common(verify)
    verify.add_argument("--expected", required=True, type=Path)

    regenerate = subparsers.add_parser(
        "regenerate", help="write an explicitly accepted fixture"
    )
    add_common(regenerate)
    regenerate.add_argument("--output", required=True, type=Path)
    regenerate.add_argument(
        "--accept",
        action="store_true",
        help="confirm that fixture creation or replacement is intentional",
    )
    return parser


def _same_path(left: Path, right: Path) -> bool:
    return left.expanduser().resolve() == right.expanduser().resolve()


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "regenerate":
            if not args.accept:
                raise AcceptanceRequired("regenerate requires --accept")
            if _same_path(args.input, args.output):
                raise InvalidInput("input and output paths must be different")
        elif _same_path(args.input, args.expected):
            raise InvalidInput("input and expected paths must be different")

        cases = read_cases(args.input)
        runner = UpstreamRunner(args.upstream_root)

        def report(case: FixtureCase, error: Exception, category: str) -> None:
            if args.verbose_errors:
                label = case.case_id or "{}/{}".format(case.language, case.mode)
                print(
                    "{}: {}: {}: {}".format(
                        label, category, type(error).__name__, str(error)
                    ),
                    file=sys.stderr,
                )

        rendered = render_cases(cases, runner.run, error_reporter=report)
        if args.command == "regenerate":
            write_fixture(args.output, rendered, accept=args.accept)
            print("wrote {} cases to {}".format(len(cases), args.output))
            return 0

        matches, diff = verify_fixture(args.expected, rendered)
        if matches:
            print("verified {} cases against {}".format(len(cases), args.expected))
            return 0
        diff_lines = diff.splitlines()
        for line in diff_lines[:MAX_DIFF_LINES]:
            print(line, file=sys.stderr)
        if len(diff_lines) > MAX_DIFF_LINES:
            print(
                "... diff truncated after {} lines ({} more)".format(
                    MAX_DIFF_LINES, len(diff_lines) - MAX_DIFF_LINES
                ),
                file=sys.stderr,
            )
        return 1
    except ReferenceToolError as error:
        print("{}: {}".format(error.category, error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
