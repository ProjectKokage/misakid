#!/usr/bin/env python3
"""Serve exact Open JTalk mobile parity resources on host loopback only.

This is provisioned test infrastructure, not a runtime resource loader. It
validates the complete Open JTalk 1.11 dictionary and committed fixture before
listening, then exposes only fixed authenticated routes to the mobile test.
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


DICTIONARY_NAME = "open_jtalk_dic_utf_8-1.11"
DICTIONARY_TREE_SHA256 = (
    "8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc"
)
DICTIONARY_TOTAL_BYTES = 107_304_813
DICTIONARY_FILES = {
    "COPYING": (
        5_865,
        "f4eca42ebd930e2c6e57fca58319d989bebcd1510cb7714b149c50f5425135ea",
    ),
    "char.bin": (
        262_496,
        "888ee94c5a8a7a26d24ab3f1b7155441351954fd51ea06b4a2f78bd742492b2f",
    ),
    "left-id.def": (
        77_672,
        "db1adac8a7f9e5854cd82ea044c85115249206c8181b9d88cf92ae2ee5e87b84",
    ),
    "matrix.bin": (
        3_792_262,
        "62fd16b4f64c851d5dc352ef0d5740c5fc83ddc7c203b2b0b1fc5271969a14ce",
    ),
    "pos-id.def": (
        1_923,
        "3460aa742053085af47cdfc889a1e0e6f557e89b406e501ba81c9ccc286de0c7",
    ),
    "rewrite.def": (
        7_457,
        "7f7c8dfbfe24092e8a149a9b6e0a3a7f1c2cf37d6c3dc29d1cccc6c004da9c1c",
    ),
    "right-id.def": (
        77_672,
        "db1adac8a7f9e5854cd82ea044c85115249206c8181b9d88cf92ae2ee5e87b84",
    ),
    "sys.dic": (
        103_073_776,
        "ca57d9029691a70a5dfb99afc2844180256161d7130da65b1a867510e129b9a6",
    ),
    "unk.dic": (
        5_690,
        "ce97851ecda075914fa3ffe7294a1ab34ee4f6d56ba6bf9197d74143b5dffbfe",
    ),
}
FIXTURE_SIZE = 77_134
FIXTURE_SHA256 = (
    "fb9832f6f4a62187d119f7acceca8e432004d1c069326fb239899a752b5e2b7e"
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
        raise ResourceError(f"Open JTalk dictionary must be a real directory: {root}")
    actual_files: set[str] = set()
    for path in root.iterdir():
        if path.is_symlink():
            raise ResourceError(f"Open JTalk dictionary contains a link: {path}")
        if not path.is_file():
            raise ResourceError(
                f"Open JTalk dictionary contains a non-file entry: {path}"
            )
        actual_files.add(path.name)
    expected_files = set(DICTIONARY_FILES)
    if actual_files != expected_files:
        raise ResourceError(
            "Open JTalk dictionary file set differs: "
            f"missing={sorted(expected_files - actual_files)}, "
            f"extra={sorted(actual_files - expected_files)}"
        )
    if sum(size for size, _ in DICTIONARY_FILES.values()) != DICTIONARY_TOTAL_BYTES:
        raise AssertionError("internal Open JTalk byte manifest is inconsistent")
    tree_records = b"".join(
        name.encode("utf-8") + b"\0" + sha256.encode("ascii") + b"\n"
        for name, (_, sha256) in sorted(DICTIONARY_FILES.items())
    )
    if hashlib.sha256(tree_records).hexdigest() != DICTIONARY_TREE_SHA256:
        raise AssertionError("internal Open JTalk tree manifest is inconsistent")
    return {
        name: _validate_file(
            root / name,
            size,
            sha256,
            f"Open JTalk dictionary {name}",
        )
        for name, (size, sha256) in sorted(DICTIONARY_FILES.items())
    }


def _build_resources(
    dictionary: Path,
    fixture: Path,
) -> tuple[dict[str, Resource], bytes]:
    dictionary_files = _validate_dictionary(dictionary)
    fixture = _validate_file(
        fixture,
        FIXTURE_SIZE,
        FIXTURE_SHA256,
        "pinned ja_pyopenjtalk.jsonl",
    )

    resources: dict[str, Resource] = {}
    dictionary_manifest = []
    for name, source in dictionary_files.items():
        size, sha256 = DICTIONARY_FILES[name]
        url = f"/v1/dictionary/{quote(name, safe='')}"
        resources[url] = Resource(
            source=source,
            size=size,
            sha256=sha256,
            media_type="application/octet-stream",
        )
        dictionary_manifest.append(
            {"path": name, "url": url, "bytes": size, "sha256": sha256}
        )

    fixture_url = "/v1/fixture"
    resources[fixture_url] = Resource(
        source=fixture,
        size=FIXTURE_SIZE,
        sha256=FIXTURE_SHA256,
        media_type="application/x-ndjson; charset=utf-8",
    )
    manifest = {
        "schemaVersion": 1,
        "dictionary": {
            "name": DICTIONARY_NAME,
            "version": "1.11",
            "treeSha256": DICTIONARY_TREE_SHA256,
            "bytes": DICTIONARY_TOTAL_BYTES,
            "files": dictionary_manifest,
        },
        "fixture": {
            "url": fixture_url,
            "bytes": FIXTURE_SIZE,
            "sha256": FIXTURE_SHA256,
            "cases": 24,
            "records": 155,
            "successes": 23,
            "failures": 1,
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
                f"openjtalk-resource-server: {self.client_address[0]} {format % args}",
                file=sys.stderr,
                flush=True,
            )

    return ResourceHandler


def _parse_arguments(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionary", type=Path, required=True)
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
            f"openjtalk-resource-server: ready on 127.0.0.1:{server.server_port}",
            flush=True,
        )
        server.serve_forever(poll_interval=0.25)
    except (OSError, ResourceError) as error:
        print(f"openjtalk-resource-server failed: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
