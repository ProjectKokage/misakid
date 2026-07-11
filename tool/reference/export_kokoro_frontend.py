#!/usr/bin/env python3
"""Export Kokoro 0.9.4 frontend chunks from its pinned pipeline.py.

The exporter installs stdlib-only in-memory stubs for optional model and G2P
dependencies, then executes the unmodified pinned KPipeline implementation.
Synthetic deterministic G2P results isolate Kokoro's own configuration,
splitting, chunking, truncation, token, and text-index behavior.
"""

from __future__ import annotations

import argparse
import contextlib
from dataclasses import dataclass
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import subprocess
import sys
import types
from typing import Iterator, Mapping, Sequence
import unicodedata


UPSTREAM_REPOSITORY = "hexgrad/kokoro"
UPSTREAM_COMMIT = "dfb907a02bba8152ca444717ca5d78747ccb4bec"
UPSTREAM_VERSION = "0.9.4"
PIPELINE_SHA256 = "499982bbc23a1019681cdb4c327c1d911e7034e240721b95686ff1a8f15c2a9a"
_STUB_PACKAGE = "_misakid_pinned_kokoro"
_MISSING = object()


class ExportError(ValueError):
    """The pinned source or deterministic case corpus is invalid."""


@dataclass
class _MToken:
    text: str
    tag: str
    whitespace: str
    phonemes: str | None = None
    start_ts: float | None = None
    end_ts: float | None = None


class _ConfiguredEnglishG2p:
    initializations: list[dict[str, object]] = []

    def __init__(self, **options: object) -> None:
        type(self).initializations.append(dict(options))


class _NoOp:
    def __init__(self, *args: object, **kwargs: object) -> None:
        del args, kwargs


class _Logger:
    def debug(self, *args: object, **kwargs: object) -> None:
        del args, kwargs

    warning = debug
    error = debug


class _Tensor:
    pass


class _KModel:
    class Output:
        pass


def _unavailable(*args: object, **kwargs: object) -> object:
    del args, kwargs
    raise RuntimeError("optional dependency use is forbidden in the oracle")


def _module(name: str, **attributes: object) -> types.ModuleType:
    result = types.ModuleType(name)
    for key, value in attributes.items():
        setattr(result, key, value)
    return result


@contextlib.contextmanager
def _stubbed_imports(upstream: Path) -> Iterator[None]:
    package = _module(_STUB_PACKAGE)
    package.__path__ = [str(upstream / "kokoro")]
    model = _module(f"{_STUB_PACKAGE}.model", KModel=_KModel)
    en = _module("misaki.en", MToken=_MToken, G2P=_ConfiguredEnglishG2p)
    espeak = _module(
        "misaki.espeak",
        EspeakFallback=_NoOp,
        EspeakG2P=_NoOp,
    )
    ja = _module("misaki.ja", JAG2P=_NoOp)
    misaki = _module("misaki", en=en, espeak=espeak, ja=ja)
    torch = _module(
        "torch",
        FloatTensor=_Tensor,
        LongTensor=_Tensor,
        cuda=types.SimpleNamespace(is_available=lambda: False),
        backends=types.SimpleNamespace(
            mps=types.SimpleNamespace(is_available=lambda: False)
        ),
        load=_unavailable,
        mean=_unavailable,
        stack=_unavailable,
    )
    replacements = {
        _STUB_PACKAGE: package,
        f"{_STUB_PACKAGE}.model": model,
        "huggingface_hub": _module(
            "huggingface_hub", hf_hub_download=_unavailable
        ),
        "loguru": _module("loguru", logger=_Logger()),
        "misaki": misaki,
        "misaki.en": en,
        "misaki.espeak": espeak,
        "misaki.ja": ja,
        "torch": torch,
    }
    previous = {
        name: sys.modules.get(name, _MISSING) for name in replacements
    }
    sys.modules.update(replacements)
    try:
        yield
    finally:
        for name, value in previous.items():
            if value is _MISSING:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = value  # type: ignore[assignment]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _git_head(repository: Path) -> str:
    process = subprocess.run(
        ["git", "-C", str(repository), "rev-parse", "HEAD"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if process.returncode != 0:
        raise ExportError(
            f"cannot inspect upstream Git checkout: {process.stderr.strip()}"
        )
    return process.stdout.strip()


def _load_pipeline(upstream: Path) -> types.ModuleType:
    if _git_head(upstream) != UPSTREAM_COMMIT:
        raise ExportError(f"upstream checkout must be at {UPSTREAM_COMMIT}")
    source = upstream / "kokoro" / "pipeline.py"
    if _sha256(source) != PIPELINE_SHA256:
        raise ExportError("pinned kokoro/pipeline.py checksum mismatch")
    spec = importlib.util.spec_from_file_location(
        f"{_STUB_PACKAGE}.pipeline", source
    )
    if spec is None or spec.loader is None:
        raise ExportError("cannot create a module spec for pipeline.py")
    module = importlib.util.module_from_spec(spec)
    with _stubbed_imports(upstream):
        sys.modules[spec.name] = module
        try:
            spec.loader.exec_module(module)
        finally:
            sys.modules.pop(spec.name, None)
    return module


def _object(value: object, location: str) -> dict[str, object]:
    if not isinstance(value, dict) or not all(
        isinstance(key, str) for key in value
    ):
        raise ExportError(f"{location} must be an object")
    return value


def _string(value: object, location: str) -> str:
    if not isinstance(value, str):
        raise ExportError(f"{location} must be a string")
    return value


def _expand_text(value: object, location: str) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "".join(
            _expand_text(part, f"{location}[{index}]")
            for index, part in enumerate(value)
        )
    repeat = _object(value, location)
    if set(repeat) != {"count", "repeat"}:
        raise ExportError(
            f"{location} repeat specs require only 'count' and 'repeat'"
        )
    count = repeat["count"]
    if isinstance(count, bool) or not isinstance(count, int) or count < 0:
        raise ExportError(f"{location}.count must be a non-negative integer")
    return _string(repeat["repeat"], f"{location}.repeat") * count


def _read_cases(path: Path) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    source = path.read_bytes().decode("utf-8")
    if not source.endswith("\n") or "\r" in source:
        raise ExportError("case corpus must use LF and end with a newline")
    for line_number, line in enumerate(source[:-1].split("\n"), start=1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ExportError(f"{path}:{line_number}: {error}") from error
        records.append(_object(value, f"{path}:{line_number}"))
    if len(records) != 11:
        raise ExportError("the accepted Kokoro frontend corpus must have 11 cases")
    return records


def _expand_token(value: object, location: str) -> dict[str, object]:
    token = _object(value, location)
    if set(token) != {"phonemes", "tag", "text", "whitespace"}:
        raise ExportError(f"{location} has unexpected token fields")
    phonemes = token["phonemes"]
    return {
        "phonemes": None
        if phonemes is None
        else _expand_text(phonemes, f"{location}.phonemes"),
        "tag": _string(token["tag"], f"{location}.tag"),
        "text": _expand_text(token["text"], f"{location}.text"),
        "whitespace": _string(
            token["whitespace"], f"{location}.whitespace"
        ),
    }


def _expand_engine_results(
    value: object, kind: str, location: str
) -> list[dict[str, object]]:
    if not isinstance(value, list):
        raise ExportError(f"{location} must be a list")
    output: list[dict[str, object]] = []
    for index, raw_result in enumerate(value):
        result_location = f"{location}[{index}]"
        result = _object(raw_result, result_location)
        if kind == "english":
            if set(result) != {"input", "tokens"}:
                raise ExportError(f"{result_location} has unexpected fields")
            raw_tokens = result["tokens"]
            if not isinstance(raw_tokens, list):
                raise ExportError(f"{result_location}.tokens must be a list")
            output.append(
                {
                    "input": _expand_text(
                        result["input"], f"{result_location}.input"
                    ),
                    "tokens": [
                        _expand_token(
                            token, f"{result_location}.tokens[{token_index}]"
                        )
                        for token_index, token in enumerate(raw_tokens)
                    ],
                }
            )
        else:
            if set(result) != {"input", "phonemes"}:
                raise ExportError(f"{result_location} has unexpected fields")
            output.append(
                {
                    "input": _expand_text(
                        result["input"], f"{result_location}.input"
                    ),
                    "phonemes": _expand_text(
                        result["phonemes"], f"{result_location}.phonemes"
                    ),
                }
            )
    if len({result["input"] for result in output}) != len(output):
        raise ExportError(f"{location} contains duplicate engine inputs")
    return output


class _SyntheticG2p:
    def __init__(
        self, kind: str, results: Sequence[Mapping[str, object]]
    ) -> None:
        self.kind = kind
        self.results = {result["input"]: result for result in results}
        self.inputs: list[str] = []

    def __call__(self, text: str) -> tuple[str, object]:
        self.inputs.append(text)
        try:
            result = self.results[text]
        except KeyError as error:
            raise ExportError(f"unexpected synthetic G2P input {text!r}") from error
        if self.kind == "english":
            raw_tokens = result["tokens"]
            assert isinstance(raw_tokens, list)
            return "", [
                _MToken(
                    text=str(token["text"]),
                    tag=str(token["tag"]),
                    whitespace=str(token["whitespace"]),
                    phonemes=token["phonemes"],
                )
                for token in raw_tokens
                if isinstance(token, dict)
            ]
        return str(result["phonemes"]), None


def _serialize_token(token: _MToken) -> dict[str, object]:
    return {
        "endTimeSeconds": token.end_ts,
        "phonemes": token.phonemes,
        "startTimeSeconds": token.start_ts,
        "tag": token.tag,
        "text": token.text,
        "whitespace": token.whitespace,
    }


def _serialize_result(result: object) -> dict[str, object]:
    tokens = result.tokens
    return {
        "graphemes": result.graphemes,
        "phonemes": result.phonemes,
        "textIndex": result.text_index,
        "tokens": None
        if tokens is None
        else [_serialize_token(token) for token in tokens],
    }


def _export_case(
    module: types.ModuleType, case: Mapping[str, object], case_number: int
) -> dict[str, object]:
    location = f"case {case_number}"
    if set(case) != {"caseId", "engineResults", "input", "kind"}:
        raise ExportError(f"{location} has unexpected fields")
    case_id = _string(case["caseId"], f"{location}.caseId")
    kind = _string(case["kind"], f"{location}.kind")
    if kind not in {"english", "nonEnglish"}:
        raise ExportError(f"{location}.kind is unsupported")
    text = _expand_text(case["input"], f"{location}.input")
    engine_results = _expand_engine_results(
        case["engineResults"], kind, f"{location}.engineResults"
    )
    _ConfiguredEnglishG2p.initializations.clear()
    pipeline = module.KPipeline(
        lang_code="a" if kind == "english" else "j",
        repo_id="hexgrad/Kokoro-82M",
        model=False,
    )
    configured_unknown_marker: str | None = None
    if kind == "english":
        if len(_ConfiguredEnglishG2p.initializations) != 1:
            raise ExportError("KPipeline did not initialize exactly one English G2P")
        marker = _ConfiguredEnglishG2p.initializations[0].get("unk")
        if marker != "":
            raise ExportError("pinned KPipeline no longer configures unk=''")
        configured_unknown_marker = marker
    synthetic = _SyntheticG2p(kind, engine_results)
    pipeline.g2p = synthetic
    chunks = list(pipeline(text))
    return {
        "backendInput": {
            "configuredUnknownMarker": configured_unknown_marker,
            "kind": "kokoro.synthetic-g2p",
            "results": engine_results,
            "schemaVersion": 1,
        },
        "backendVersions": {
            "python": platform.python_version(),
            "unicodeData": unicodedata.unidata_version,
        },
        "caseId": case_id,
        "chunks": [_serialize_result(chunk) for chunk in chunks],
        "engineInputs": synthetic.inputs,
        "input": text,
        "language": "en" if kind == "english" else "nonEnglish",
        "mode": "kokoro-0.9.4-default-string",
        "options": {},
        "schemaVersion": 1,
        "upstreamCommit": UPSTREAM_COMMIT,
        "upstreamRepository": UPSTREAM_REPOSITORY,
        "upstreamVersion": UPSTREAM_VERSION,
    }


def _encode_jsonl(records: Sequence[Mapping[str, object]]) -> bytes:
    output = bytearray()
    for record in records:
        line = json.dumps(
            record,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
        output.extend(line.encode("utf-8", errors="backslashreplace"))
        output.append(0x0A)
    return bytes(output)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream-repository", required=True, type=Path)
    parser.add_argument("--cases", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--accept",
        action="store_true",
        help="write the generated fixture; without this flag, verify it",
    )
    args = parser.parse_args(argv)

    upstream = args.upstream_repository.resolve()
    cases = _read_cases(args.cases.resolve())
    with _stubbed_imports(upstream):
        module = _load_pipeline(upstream)
        records = [
            _export_case(module, case, index)
            for index, case in enumerate(cases, start=1)
        ]
    generated = _encode_jsonl(records)
    if args.accept:
        previous = args.output.read_bytes() if args.output.is_file() else None
        args.output.write_bytes(generated)
        action = "unchanged" if previous == generated else "accepted"
        print(
            f"{action} {len(records)} pinned Kokoro frontend cases at "
            f"{args.output}"
        )
        return 0
    if not args.output.is_file():
        raise ExportError(
            f"fixture does not exist for verification: {args.output}; "
            "pass --accept to create it"
        )
    if args.output.read_bytes() != generated:
        raise ExportError(
            f"generated fixture differs from {args.output}; review the diff "
            "and rerun with --accept only after explicit approval"
        )
    print(f"verified {len(records)} pinned Kokoro frontend cases at {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
