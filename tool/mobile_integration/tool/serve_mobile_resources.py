#!/usr/bin/env python3
"""Serve exact external Japanese parity resources on host loopback only.

This is test infrastructure, not a runtime resource loader. It validates every
source file before listening and exposes only the fixed manifest and resources
needed by the provisioned Flutter integration test.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote, urlsplit


DICTIONARY_TREE_SHA256 = (
    "95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115"
)
DICTIONARY_TOTAL_BYTES = 811_662_881
DICTIONARY_FILES = {
    "README": (
        4_490,
        "8b9c0e67caf2b1e838d63dca5a2b7ff34fa8faafe461e942ca1469f90f126e9a",
    ),
    "char.bin": (
        262_496,
        "dd31396563d8924645b80fd3c9aa7b13ca089d7748f25553a1d6bc3f9b511ae8",
    ),
    "char.def": (
        4_292,
        "0790db12ab4f4d742b39b1737b9cce2a00c92220139a5bea9f0e8874898726e5",
    ),
    "dicrc": (
        1_785,
        "9b7bd3dbfdb381a078375cdcccb1e69f60256d510a5c84a3e343ae20f98dc2ce",
    ),
    "feature.def": (
        8_715,
        "b50a047e6caa8a7e4158fa736728e8de46cf009bbe575b239c33312e8b30cd14",
    ),
    "left-id.def": (
        1_556_924,
        "6e7fb23dda28ef49db733b56bc9217c39536df6ee5aa8c33d720e3d711a6baa6",
    ),
    "licenses/AUTHORS": (
        22,
        "a05bfdd3a9db36d9c64495f4a3d1824d05b95fbb4fc6dc07c660e91bc191c481",
    ),
    "licenses/BSD": (
        1_515,
        "770a75de30705439084f869dbcb0bc4ebcffcb7c7124c0d74f5083170318a9bb",
    ),
    "licenses/COPYING": (
        210,
        "d44b49398a72590a675e55f8f7a7dbf57bb5b71a9e20ba250f09c0cc5986bef1",
    ),
    "licenses/GPL": (
        17_991,
        "a137434196f5e39d8836de895866fcfea074ad1b28243174ca1c4a585a1229b0",
    ),
    "licenses/LGPL": (
        26_428,
        "512d2d21b6b3384ba64781abb0208a1b87740bc31e2df48e2b206ddb7e4d5779",
    ),
    "matrix.bin": (
        480_905_780,
        "dd9ee6bc6bb137298cc88673e9c2143ddcf0808805c81becdd2ae5d08a869f90",
    ),
    "mecabrc": (
        23,
        "8a9eb27c98dce111d8544fa8fcaaf387efc5e345efe991918363c2a5d1b7ffbc",
    ),
    "model.bin": (
        83_718_788,
        "409efa3e3de09d8822a3443d4f97c7fda77c4f8fc991f7abc064f685e346b1c9",
    ),
    "rewrite.def": (
        5_076,
        "0ff0d86c7640997258ecce5468916f9eff3f2c5e5be5d43d372c0e62828deefe",
    ),
    "right-id.def": (
        1_767_025,
        "2ec747f614eb3e8a6378f42bfbc877dfeb37fe8a331f70d9f50e0c096d4b182d",
    ),
    "sys.dic": (
        243_373_840,
        "f019f95838242cd614953a25201ad0b623b9c1cbca90de2507df4510db1b192c",
    ),
    "unk.def": (
        1_977,
        "4b40b5158f6bab29d3c0d3fd871055538241c7103406ba8e89e7d741ccf22dbc",
    ),
    "unk.dic": (
        5_481,
        "a8e1067721cfd5cd7d4a17ddb53c77fb07f77fa20143b4589d7934c88f67d7e8",
    ),
    "version": (
        23,
        "3240727150c25bace5f1c7e8df0208da3d01ba67121aed0ff689c0724a83d44a",
    ),
}
WORD_LIST_SIZE = 1_921_140
WORD_LIST_SHA256 = (
    "a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff"
)
FIXTURE_SIZE = 47_945
FIXTURE_SHA256 = (
    "c599ac58455263a9c9e100f175e9eaa07d1b9e77194a075dea6d02d3a1627a48"
)


class ResourceError(RuntimeError):
    """A local test resource does not have its pinned identity."""


@dataclass(frozen=True)
class Resource:
    source: Path
    size: int
    sha256: str
    media_type: str


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_file(path: Path, size: int, sha256: str, label: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise ResourceError(f"{label} must be a regular file: {path}")
    stat = path.stat()
    if stat.st_size != size:
        raise ResourceError(
            f"{label} has {stat.st_size} bytes; expected {size}: {path}"
        )
    actual_sha256 = _sha256(path)
    if actual_sha256 != sha256:
        raise ResourceError(
            f"{label} has SHA-256 {actual_sha256}; expected {sha256}: {path}"
        )
    return path.resolve(strict=True)


def _validate_dictionary(root: Path) -> dict[str, Path]:
    if root.is_symlink() or not root.is_dir():
        raise ResourceError(f"UniDic must be a real directory: {root}")
    actual_files: set[str] = set()
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ResourceError(f"UniDic contains a symbolic link: {path}")
        if path.is_file():
            actual_files.add(path.relative_to(root).as_posix())
        elif not path.is_dir():
            raise ResourceError(f"UniDic contains a non-file entry: {path}")
    expected_files = set(DICTIONARY_FILES)
    if actual_files != expected_files:
        raise ResourceError(
            "UniDic file set differs: "
            f"missing={sorted(expected_files - actual_files)}, "
            f"extra={sorted(actual_files - expected_files)}"
        )
    if sum(size for size, _ in DICTIONARY_FILES.values()) != DICTIONARY_TOTAL_BYTES:
        raise AssertionError("internal UniDic byte manifest is inconsistent")
    return {
        relative: _validate_file(
            root / relative,
            size,
            sha256,
            f"UniDic {relative}",
        )
        for relative, (size, sha256) in sorted(DICTIONARY_FILES.items())
    }


def _build_resources(
    dictionary: Path,
    word_list: Path,
    fixture: Path,
) -> tuple[dict[str, Resource], bytes]:
    dictionary_files = _validate_dictionary(dictionary)
    word_list = _validate_file(
        word_list,
        WORD_LIST_SIZE,
        WORD_LIST_SHA256,
        "pinned ja_words.txt",
    )
    fixture = _validate_file(
        fixture,
        FIXTURE_SIZE,
        FIXTURE_SHA256,
        "pinned ja_cutlet.jsonl",
    )

    resources: dict[str, Resource] = {}
    dictionary_manifest = []
    for relative, source in dictionary_files.items():
        size, sha256 = DICTIONARY_FILES[relative]
        url = f"/v1/dictionary/{quote(relative, safe='/')}"
        resources[url] = Resource(
            source=source,
            size=size,
            sha256=sha256,
            media_type="application/octet-stream",
        )
        dictionary_manifest.append(
            {"path": relative, "url": url, "bytes": size, "sha256": sha256}
        )

    word_list_url = "/v1/word-list"
    fixture_url = "/v1/fixture"
    resources[word_list_url] = Resource(
        source=word_list,
        size=WORD_LIST_SIZE,
        sha256=WORD_LIST_SHA256,
        media_type="text/plain; charset=utf-8",
    )
    resources[fixture_url] = Resource(
        source=fixture,
        size=FIXTURE_SIZE,
        sha256=FIXTURE_SHA256,
        media_type="application/x-ndjson; charset=utf-8",
    )
    manifest = {
        "schemaVersion": 1,
        "dictionary": {
            "name": "unidic-cwj",
            "version": "3.1.0+2021-08-31",
            "treeSha256": DICTIONARY_TREE_SHA256,
            "bytes": DICTIONARY_TOTAL_BYTES,
            "files": dictionary_manifest,
        },
        "wordList": {
            "url": word_list_url,
            "bytes": WORD_LIST_SIZE,
            "sha256": WORD_LIST_SHA256,
            "records": 147_571,
        },
        "fixture": {
            "url": fixture_url,
            "bytes": FIXTURE_SIZE,
            "sha256": FIXTURE_SHA256,
            "cases": 27,
            "records": 126,
        },
    }
    manifest_bytes = json.dumps(
        manifest,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return resources, manifest_bytes


def _handler(
    resources: dict[str, Resource], manifest: bytes, token: str
) -> type[BaseHTTPRequestHandler]:
    class ResourceHandler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if self.headers.get("Authorization") != f"Bearer {token}":
                self.send_error(HTTPStatus.UNAUTHORIZED)
                return
            parsed = urlsplit(self.path)
            if parsed.query or parsed.fragment:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            if parsed.path == "/v1/manifest.json":
                self._send_bytes(manifest, "application/json; charset=utf-8")
                return
            resource = resources.get(parsed.path)
            if resource is None:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", resource.media_type)
            self.send_header("Content-Length", str(resource.size))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                with resource.source.open("rb") as stream:
                    shutil.copyfileobj(stream, self.wfile, length=1024 * 1024)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def _send_bytes(self, data: bytes, media_type: str) -> None:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", media_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format: str, *args: object) -> None:
            print(
                f"resource-server: {self.client_address[0]} {format % args}",
                file=sys.stderr,
                flush=True,
            )

    return ResourceHandler


def _parse_arguments(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionary", type=Path, required=True)
    parser.add_argument("--word-list", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--ready-file", type=Path, required=True)
    parser.add_argument("--port", type=int, default=0)
    arguments = parser.parse_args(argv)
    if not arguments.token or any(character.isspace() for character in arguments.token):
        parser.error("--token must be non-empty and contain no whitespace")
    if not 0 <= arguments.port <= 65_535:
        parser.error("--port must be between 0 and 65535")
    return arguments


def main(argv: list[str] | None = None) -> int:
    arguments = _parse_arguments(argv)
    try:
        resources, manifest = _build_resources(
            arguments.dictionary,
            arguments.word_list,
            arguments.fixture,
        )
        server = ThreadingHTTPServer(
            ("127.0.0.1", arguments.port),
            _handler(resources, manifest, arguments.token),
        )
        server.daemon_threads = True
        ready_file = arguments.ready_file
        if ready_file.exists() or ready_file.is_symlink():
            raise ResourceError(f"ready file already exists: {ready_file}")
        ready_file.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(
            {"host": "127.0.0.1", "port": server.server_port},
            sort_keys=True,
        )
        temporary = ready_file.with_name(f".{ready_file.name}.{os.getpid()}.tmp")
        temporary.write_text(payload, encoding="utf-8")
        temporary.replace(ready_file)
        print(
            f"resource-server: ready on 127.0.0.1:{server.server_port}",
            flush=True,
        )
        server.serve_forever(poll_interval=0.25)
    except (OSError, ResourceError) as error:
        print(f"resource-server failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
