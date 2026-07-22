#!/usr/bin/env python3
"""Verify the mobile harness source policy and packaged native code assets."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path


ANDROID_PAGE_SIZE = 16 * 1024
IOS_MINIMUM_VERSION = (13, 0)
ANDROID_ABIS = {
    "armeabi-v7a": (1, 40),
    "arm64-v8a": (2, 183),
    "x86_64": (2, 62),
}
FORBIDDEN_RESOURCE_NAMES = {
    "char.bin",
    "dicrc",
    "ja_words.txt",
    "matrix.bin",
    "sys.dic",
    "unk.dic",
}


class VerificationError(RuntimeError):
    """A deterministic mobile integration invariant failed."""


@dataclass(frozen=True)
class NativeAsset:
    """Expected mobile packaging identity for one native-code asset."""

    name: str
    export_manifest_name: str
    expected_export_count: int

    @property
    def asset_id(self) -> str:
        return f"package:{self.name}/{self.name}"

    @property
    def android_library(self) -> str:
        return f"lib{self.name}.so"

    @property
    def ios_framework(self) -> str:
        return f"{self.name}.framework"

    @property
    def ios_install_name(self) -> str:
        return f"@rpath/{self.ios_manifest_target}"

    @property
    def ios_manifest_target(self) -> str:
        return f"{self.ios_framework}/{self.name}"

    @property
    def expected_exports(self) -> frozenset[str]:
        path = Path(__file__).with_name(self.export_manifest_name)
        lines = path.read_text(encoding="utf-8").splitlines()
        exports = frozenset(lines)
        _require(
            len(lines) == self.expected_export_count
            and len(exports) == self.expected_export_count
            and all(name.startswith(f"{self.name}_") for name in lines),
            f"{path.name} must contain exactly {self.expected_export_count} "
            f"unique {self.name}_ symbols.",
        )
        return exports


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


NATIVE_ASSETS = (
    NativeAsset("misakid_mecab_ja", "expected_native_exports.txt", 24),
    NativeAsset("misakid_openjtalk", "expected_openjtalk_exports.txt", 23),
)


def verify_source_tree(root: Path) -> None:
    """Reject bundled resources and validate both adapter path dependencies."""

    root = root.resolve()
    pubspec = root / "pubspec.yaml"
    _require(pubspec.is_file(), f"Missing Flutter pubspec: {pubspec}")
    pubspec_text = pubspec.read_text(encoding="utf-8")
    _require(
        pubspec_text.count("misakid:\n    path: ../..") == 2,
        "The harness must use the repository root through a path dependency.",
    )
    for asset in NATIVE_ASSETS:
        dependency = f"{asset.name}:\n    path: ../../packages/{asset.name}"
        _require(
            pubspec_text.count(dependency) == 1,
            f"The harness must use {asset.name} through one path dependency.",
        )
    _require(
        re.search(r"^\s+assets\s*:", pubspec_text, re.MULTILINE) is None,
        "The harness pubspec must not bundle application assets.",
    )

    android_app_gradle = (
        root / "android" / "app" / "build.gradle.kts"
    ).read_text(encoding="utf-8")
    _require(
        'id("org.jetbrains.kotlin.android")' in android_app_gradle,
        "The Android app must apply the Kotlin plugin used by MainActivity.kt.",
    )
    android_settings = (root / "android" / "settings.gradle.kts").read_text(
        encoding="utf-8"
    )
    _require(
        'id("com.android.application") version "8.11.1" apply false'
        in android_settings
        and 'id("org.jetbrains.kotlin.android") version "2.2.20" apply false'
        in android_settings,
        "The Android app must use the reviewed stable AGP/Kotlin versions.",
    )
    gradle_wrapper = (
        root / "android" / "gradle" / "wrapper" / "gradle-wrapper.properties"
    ).read_text(encoding="utf-8")
    _require(
        "distributionUrl=https\\://services.gradle.org/distributions/"
        "gradle-8.14-all.zip"
        in gradle_wrapper,
        "The Android app must use the reviewed stable Gradle wrapper.",
    )
    repository_root = root.parent.parent
    for workflow_name in (
        "mobile_integration.yml",
        "mobile_runtime_parity.yml",
    ):
        workflow = (
            repository_root / ".github" / "workflows" / workflow_name
        ).read_text(encoding="utf-8")
        _require(
            "FLUTTER_VERSION: 3.41.7" in workflow,
            f"{workflow_name} must use the locally verified Flutter version.",
        )

    forbidden: list[Path] = []
    oversized: list[Path] = []
    ignored_parts = {".dart_tool", "build"}
    for path in root.rglob("*"):
        if not path.is_file() or ignored_parts.intersection(path.parts):
            continue
        if path.name.lower() in FORBIDDEN_RESOURCE_NAMES:
            forbidden.append(path.relative_to(root))
        if path.stat().st_size > 5 * 1024 * 1024:
            oversized.append(path.relative_to(root))
    _require(not forbidden, f"Forbidden linguistic resources: {forbidden}")
    _require(not oversized, f"Unexpected large harness files: {oversized}")

    for asset in NATIVE_ASSETS:
        package_manifest = (
            repository_root
            / "packages"
            / asset.name
            / "native"
            / "expected_exports_macos.txt"
        )
        _require(
            package_manifest.is_file(),
            f"Missing adapter export manifest: {package_manifest}",
        )
        package_lines = package_manifest.read_text(encoding="utf-8").splitlines()
        package_exports = {line.removeprefix("_") for line in package_lines}
        _require(
            len(package_lines) == asset.expected_export_count
            and len(package_exports) == asset.expected_export_count
            and all(line.startswith(f"_{asset.name}_") for line in package_lines)
            and package_exports == asset.expected_exports,
            f"Harness and {asset.name} native export manifests differ.",
        )

    debug_plist = _read_plist(
        root / "ios" / "Runner" / "Info-Debug.plist",
        "debug application Info.plist",
    )
    production_plist = _read_plist(
        root / "ios" / "Runner" / "Info.plist",
        "production application Info.plist",
    )
    scene_manifest = debug_plist.get("UIApplicationSceneManifest")
    _require(isinstance(scene_manifest, dict), "Debug plist has no scene manifest.")
    scene_configurations = scene_manifest.get("UISceneConfigurations")
    _require(
        isinstance(scene_configurations, dict),
        "Debug plist has no scene configurations.",
    )
    application_scenes = scene_configurations.get(
        "UIWindowSceneSessionRoleApplication"
    )
    _require(
        isinstance(application_scenes, list)
        and len(application_scenes) == 1
        and isinstance(application_scenes[0], dict),
        "Debug plist must declare exactly one application scene.",
    )
    application_scene = application_scenes[0]
    _require(
        application_scene.get("UISceneClassName") == "UIWindowScene",
        "Debug plist UISceneClassName must remain UIWindowScene.",
    )
    _require(
        application_scene.get("UISceneDelegateClassName")
        == "$(PRODUCT_MODULE_NAME).SceneDelegate",
        "Debug plist scene delegate differs from the Flutter template.",
    )
    transport_security = debug_plist.get("NSAppTransportSecurity")
    _require(
        isinstance(transport_security, dict)
        and transport_security.get("NSAllowsLocalNetworking") is True,
        "Debug plist must allow only the provisioned local-network test path.",
    )
    _require(
        "NSAppTransportSecurity" not in production_plist
        and "NSLocalNetworkUsageDescription" not in production_plist,
        "Local test networking must not leak into the production plist.",
    )
    print(
        "source: both adapter path dependencies/export manifests and "
        "external-resource policy verified"
    )


def _elf_details(data: bytes) -> tuple[int, int, list[int]]:
    _require(data[:4] == b"\x7fELF", "Native Android asset is not ELF.")
    _require(len(data) >= 64, "Truncated ELF header.")
    elf_class = data[4]
    byte_order = data[5]
    _require(elf_class in (1, 2), f"Unsupported ELF class {elf_class}.")
    _require(byte_order in (1, 2), f"Unsupported ELF byte order {byte_order}.")
    endian = "<" if byte_order == 1 else ">"
    machine = struct.unpack_from(f"{endian}H", data, 18)[0]

    if elf_class == 1:
        program_offset = struct.unpack_from(f"{endian}I", data, 28)[0]
        entry_size = struct.unpack_from(f"{endian}H", data, 42)[0]
        entry_count = struct.unpack_from(f"{endian}H", data, 44)[0]
        alignment_offset = 28
        alignment_format = "I"
        minimum_entry_size = 32
    else:
        program_offset = struct.unpack_from(f"{endian}Q", data, 32)[0]
        entry_size = struct.unpack_from(f"{endian}H", data, 54)[0]
        entry_count = struct.unpack_from(f"{endian}H", data, 56)[0]
        alignment_offset = 48
        alignment_format = "Q"
        minimum_entry_size = 56

    _require(entry_size >= minimum_entry_size, "Malformed ELF program header size.")
    alignments: list[int] = []
    for index in range(entry_count):
        offset = program_offset + index * entry_size
        _require(offset + entry_size <= len(data), "Truncated ELF program headers.")
        program_type = struct.unpack_from(f"{endian}I", data, offset)[0]
        if program_type == 1:  # PT_LOAD
            alignments.append(
                struct.unpack_from(
                    f"{endian}{alignment_format}",
                    data,
                    offset + alignment_offset,
                )[0]
            )
    _require(alignments, "ELF asset has no loadable segments.")
    return elf_class, machine, alignments


def _zip_data_offset(apk: Path, info: zipfile.ZipInfo) -> int:
    with apk.open("rb") as stream:
        stream.seek(info.header_offset)
        header = stream.read(30)
    _require(len(header) == 30, f"Truncated ZIP local header for {info.filename}.")
    fields = struct.unpack("<I5H3I2H", header)
    _require(fields[0] == 0x04034B50, f"Invalid ZIP local header for {info.filename}.")
    file_name_length = fields[-2]
    extra_length = fields[-1]
    return info.header_offset + 30 + file_name_length + extra_length


def _android_sdk() -> Path:
    value = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    _require(value is not None, "ANDROID_HOME or ANDROID_SDK_ROOT is required.")
    sdk = Path(value).resolve()
    _require(sdk.is_dir(), f"Android SDK does not exist: {sdk}")
    return sdk


def _android_ndk_tool(sdk: Path, name: str) -> Path:
    ndk_version = os.environ.get("ANDROID_NDK_VERSION")
    ndk_root = sdk / "ndk" / ndk_version if ndk_version else sdk / "ndk"
    candidates = sorted(
        ndk_root.glob(f"*/toolchains/llvm/prebuilt/*/bin/{name}")
    )
    if ndk_version:
        candidates = sorted(
            ndk_root.glob(f"toolchains/llvm/prebuilt/*/bin/{name}")
        )
    _require(candidates, f"Could not locate NDK {name} below {ndk_root}.")
    return candidates[-1]


def _android_nm(sdk: Path) -> Path:
    return _android_ndk_tool(sdk, "llvm-nm")


def _android_readelf(sdk: Path) -> Path:
    return _android_ndk_tool(sdk, "llvm-readelf")


def _zipalign(sdk: Path) -> Path:
    candidates = sorted(sdk.glob("build-tools/*/zipalign"))
    _require(candidates, f"Could not locate zipalign below {sdk}.")
    return candidates[-1]


def _adapter_exports(tool: Path, binary: Path, *, elf: bool) -> set[str]:
    command = (
        [str(tool), "-D", "--defined-only", "-j", str(binary)]
        if elf
        else [str(tool), "-gjU", str(binary)]
    )
    result = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    exports: set[str] = set()
    for line in result.stdout.splitlines():
        symbol = line.strip()
        if not elf and symbol.startswith("_"):
            symbol = symbol[1:]
        if symbol:
            exports.add(symbol)
    return exports


def _android_needed_libraries(tool: Path, binary: Path) -> set[str]:
    result = subprocess.run(
        [str(tool), "-d", str(binary)],
        check=True,
        capture_output=True,
        text=True,
    )
    return set(
        re.findall(r"\(NEEDED\)\s+Shared library: \[([^]]+)\]", result.stdout)
    )


def verify_android(apk: Path) -> None:
    """Verify both bundled libraries, ABIs, exports, and alignment."""

    apk = apk.resolve()
    _require(apk.is_file(), f"Missing release APK: {apk}")
    sdk = _android_sdk()
    subprocess.run(
        [str(_zipalign(sdk)), "-c", "-P", "16", "4", str(apk)],
        check=True,
    )
    nm = _android_nm(sdk)
    readelf = _android_readelf(sdk)
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        manifest_names = [
            name for name in names if name.endswith("NativeAssetsManifest.json")
        ]
        _require(
            len(manifest_names) == 1,
            f"APK must contain one NativeAssetsManifest.json: {manifest_names}.",
        )
        manifest_name = manifest_names[0]
        try:
            value = json.loads(archive.read(manifest_name))
        except (UnicodeError, json.JSONDecodeError) as error:
            raise VerificationError(
                f"Invalid native-assets manifest in APK: {manifest_name}."
            ) from error
        _require(isinstance(value, dict), "APK native-assets manifest is not a map.")
        native_assets = value.get("native-assets")
        _require(
            isinstance(native_assets, dict),
            "APK native-assets manifest has no native-assets map.",
        )
        expected_architectures = {"android_arm", "android_arm64", "android_x64"}
        _require(
            set(native_assets) == expected_architectures,
            f"APK native-assets architectures differ: {sorted(native_assets)}.",
        )
        expected_asset_ids = {asset.asset_id for asset in NATIVE_ASSETS}
        for architecture in sorted(expected_architectures):
            table = native_assets[architecture]
            _require(
                isinstance(table, dict) and set(table) == expected_asset_ids,
                f"APK native-assets table differs for {architecture}: {table!r}.",
            )
            for asset in NATIVE_ASSETS:
                _require(
                    table[asset.asset_id] == ["absolute", asset.android_library],
                    f"APK mapping differs for {asset.asset_id} on "
                    f"{architecture}: {table[asset.asset_id]!r}.",
                )

        for asset in NATIVE_ASSETS:
            packaged_abis: set[str] = set()
            expected_exports = asset.expected_exports
            for abi, (expected_class, expected_machine) in ANDROID_ABIS.items():
                name = f"lib/{abi}/{asset.android_library}"
                _require(name in names, f"APK is missing {name}.")
                packaged_abis.add(abi)
                info = archive.getinfo(name)
                _require(
                    info.compress_type == zipfile.ZIP_STORED,
                    f"{name} must be stored uncompressed.",
                )
                data_offset = _zip_data_offset(apk, info)
                _require(
                    data_offset % ANDROID_PAGE_SIZE == 0,
                    f"{name} data offset {data_offset} is not 16-KiB aligned.",
                )
                data = archive.read(name)
                with tempfile.TemporaryDirectory(
                    prefix=f"{asset.name}-android-"
                ) as temp:
                    binary = Path(temp) / asset.android_library
                    binary.write_bytes(data)
                    exports = _adapter_exports(nm, binary, elf=True)
                    needed_libraries = _android_needed_libraries(readelf, binary)
                _require(
                    exports == expected_exports,
                    f"{name} adapter exports differ: "
                    f"missing={sorted(expected_exports - exports)}, "
                    f"extra={sorted(exports - expected_exports)}.",
                )
                _require(
                    needed_libraries == {"libc.so", "libdl.so", "libm.so"},
                    f"{name} dynamic dependencies differ: "
                    f"{sorted(needed_libraries)}.",
                )
                elf_class, machine, alignments = _elf_details(data)
                _require(
                    (elf_class, machine) == (expected_class, expected_machine),
                    f"{name} has ELF class/machine "
                    f"{(elf_class, machine)}, expected "
                    f"{(expected_class, expected_machine)}.",
                )
                _require(
                    all(
                        alignment >= ANDROID_PAGE_SIZE
                        for alignment in alignments
                    ),
                    f"{name} load alignment is below 16 KiB: {alignments}.",
                )

            discovered = {
                name.split("/")[1]
                for name in names
                if name.startswith("lib/")
                and name.endswith(f"/{asset.android_library}")
            }
            _require(
                discovered == packaged_abis,
                f"Unexpected {asset.name} Android ABI set "
                f"{sorted(discovered)}.",
            )
    print(
        "android: 2 libraries x 3 ABIs, libc/libdl/libm, Cutlet 24/Open "
        "JTalk 23 exact exports, both manifests, and 16-KiB alignment verified"
    )


def _macho_architectures(data: bytes) -> set[str]:
    cpu_names = {
        0x01000007: "x86_64",
        0x0100000C: "arm64",
    }
    magic = data[:4]
    thin_endian = {
        b"\xce\xfa\xed\xfe": "<",
        b"\xcf\xfa\xed\xfe": "<",
        b"\xfe\xed\xfa\xce": ">",
        b"\xfe\xed\xfa\xcf": ">",
    }.get(magic)
    if thin_endian is not None:
        _require(len(data) >= 8, "Truncated Mach-O header.")
        cpu_type = struct.unpack_from(f"{thin_endian}I", data, 4)[0]
        _require(cpu_type in cpu_names, f"Unsupported Mach-O CPU {cpu_type:#x}.")
        return {cpu_names[cpu_type]}

    fat_formats = {
        b"\xca\xfe\xba\xbe": (">", 20),
        b"\xca\xfe\xba\xbf": (">", 32),
        b"\xbe\xba\xfe\xca": ("<", 20),
        b"\xbf\xba\xfe\xca": ("<", 32),
    }
    fat = fat_formats.get(magic)
    _require(fat is not None, "Native iOS asset is not Mach-O.")
    endian, entry_size = fat
    _require(len(data) >= 8, "Truncated universal Mach-O header.")
    count = struct.unpack_from(f"{endian}I", data, 4)[0]
    _require(0 < count <= 32, f"Invalid universal Mach-O architecture count {count}.")
    architectures: set[str] = set()
    for index in range(count):
        offset = 8 + index * entry_size
        _require(offset + entry_size <= len(data), "Truncated universal Mach-O table.")
        cpu_type = struct.unpack_from(f"{endian}I", data, offset)[0]
        _require(cpu_type in cpu_names, f"Unsupported Mach-O CPU {cpu_type:#x}.")
        architectures.add(cpu_names[cpu_type])
    return architectures


def _tool_output(command: list[str]) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return result.stdout


def _version(value: str, label: str) -> tuple[int, ...]:
    try:
        result = tuple(int(part) for part in value.split("."))
    except ValueError as error:
        raise VerificationError(f"Invalid {label} version {value!r}.") from error
    _require(result and all(part >= 0 for part in result), f"Invalid {label} {value!r}.")
    return result


def _verify_ios_build_version(binary: Path) -> None:
    output = _tool_output(["xcrun", "vtool", "-show-build", str(binary)])
    platforms = re.findall(r"^\s*platform\s+(\S+)\s*$", output, re.MULTILINE)
    minimums = re.findall(r"^\s*minos\s+(\S+)\s*$", output, re.MULTILINE)
    _require(platforms == ["IOS"], f"Expected one IOS LC_BUILD_VERSION: {platforms}.")
    _require(len(minimums) == 1, f"Expected one iOS minimum version: {minimums}.")
    minimum = _version(minimums[0], "LC_BUILD_VERSION minimum")
    _require(
        minimum >= IOS_MINIMUM_VERSION,
        f"Native framework minimum iOS {minimums[0]} is below 13.0.",
    )


def _otool_values(binary: Path, option: str) -> list[str]:
    output = _tool_output(["xcrun", "otool", option, str(binary)])
    values: list[str] = []
    for line in output.splitlines():
        stripped = line.strip()
        if not stripped or stripped.endswith(":"):
            continue
        if " (architecture " in stripped and stripped.endswith(":"):
            continue
        values.append(stripped.split(" (compatibility version", maxsplit=1)[0])
    return values


def _macho_rpaths(binary: Path) -> set[str]:
    lines = _tool_output(["xcrun", "otool", "-l", str(binary)]).splitlines()
    rpaths: set[str] = set()
    for index, line in enumerate(lines):
        if line.strip() != "cmd LC_RPATH":
            continue
        for candidate in lines[index + 1 : index + 5]:
            stripped = candidate.strip()
            if stripped.startswith("path "):
                rpaths.add(stripped.removeprefix("path ").split(" (offset", 1)[0])
                break
    return rpaths


def _read_plist(path: Path, label: str) -> dict[str, object]:
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise VerificationError(f"Could not read {label}: {path}.") from error
    _require(isinstance(value, dict), f"{label} is not a dictionary: {path}.")
    return value


def _verify_ios_manifest(app: Path, binary: Path, asset: NativeAsset) -> None:
    manifests = list(app.rglob("NativeAssetsManifest.json"))
    _require(manifests, "iOS app has no NativeAssetsManifest.json.")
    matches: list[tuple[Path, str, object]] = []
    for manifest in manifests:
        try:
            value = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise VerificationError(f"Invalid native-assets manifest: {manifest}.") from error
        if not isinstance(value, dict):
            continue
        native_assets = value.get("native-assets")
        if not isinstance(native_assets, dict):
            continue
        for architecture, table in native_assets.items():
            if isinstance(table, dict) and asset.asset_id in table:
                matches.append(
                    (manifest, str(architecture), table[asset.asset_id])
                )
    _require(
        len(matches) == 1,
        f"Expected one iOS mapping for {asset.asset_id}, found {matches}.",
    )
    manifest, architecture, target = matches[0]
    _require(
        architecture == "ios_arm64",
        f"Native asset uses {architecture!r}, expected 'ios_arm64': {manifest}.",
    )
    _require(
        target == ["absolute", asset.ios_manifest_target],
        f"{asset.name} native asset target differs in {manifest}: {target!r}.",
    )
    resolved = app / "Frameworks" / asset.ios_manifest_target
    _require(
        resolved.resolve() == binary.resolve(),
        f"{asset.name} native-assets mapping does not resolve to {binary}.",
    )


def verify_ios(app: Path) -> None:
    """Verify both bundled native frameworks in an unsigned device app."""

    app = app.resolve()
    _require(app.is_dir(), f"Missing iOS application bundle: {app}")
    binaries: list[tuple[NativeAsset, Path]] = []
    for asset in NATIVE_ASSETS:
        framework = app / "Frameworks" / asset.ios_framework
        binary = framework / asset.name
        _require(binary.is_file(), f"Missing bundled iOS native asset: {binary}")
        framework_plist_path = framework / "Info.plist"
        _require(
            framework_plist_path.is_file(),
            f"{asset.name} iOS framework has no Info.plist.",
        )
        data = binary.read_bytes()
        exports = _adapter_exports(Path("/usr/bin/nm"), binary, elf=False)
        expected_exports = asset.expected_exports
        _require(
            exports == expected_exports,
            f"{asset.name} iOS exports differ: "
            f"missing={sorted(expected_exports - exports)}, "
            f"extra={sorted(exports - expected_exports)}.",
        )
        architectures = _macho_architectures(data)
        _require(
            architectures == {"arm64"},
            f"{asset.name} iOS asset has architectures "
            f"{sorted(architectures)}.",
        )
        _verify_ios_build_version(binary)
        install_names = _otool_values(binary, "-D")
        _require(
            install_names == [asset.ios_install_name],
            f"{asset.name} framework install name differs: {install_names}.",
        )
        linked = _otool_values(binary, "-L")
        _require(
            linked
            == [
                asset.ios_install_name,
                "/usr/lib/libc++.1.dylib",
                "/usr/lib/libSystem.B.dylib",
            ],
            f"{asset.name} framework linkage differs: {linked}.",
        )
        framework_plist = _read_plist(
            framework_plist_path,
            f"{asset.name} framework Info.plist",
        )
        _require(
            framework_plist.get("CFBundleExecutable") == asset.name
            and framework_plist.get("CFBundlePackageType") == "FMWK",
            f"{asset.name} framework Info.plist identity differs.",
        )
        plist_minimum = framework_plist.get("MinimumOSVersion")
        _require(
            isinstance(plist_minimum, str)
            and _version(plist_minimum, "framework plist minimum")
            >= IOS_MINIMUM_VERSION,
            f"{asset.name} framework Info.plist minimum differs: "
            f"{plist_minimum!r}.",
        )
        binaries.append((asset, binary))

    app_plist = _read_plist(app / "Info.plist", "application Info.plist")
    executable_name = app_plist.get("CFBundleExecutable")
    _require(
        isinstance(executable_name, str) and executable_name,
        "Application Info.plist has no CFBundleExecutable.",
    )
    executable = app / executable_name
    _require(executable.is_file(), f"Missing application executable: {executable}.")
    rpaths = _macho_rpaths(executable)
    _require(
        "@executable_path/Frameworks" in rpaths,
        f"Application cannot resolve bundled frameworks; rpaths={sorted(rpaths)}.",
    )
    for asset, binary in binaries:
        _verify_ios_manifest(app, binary, asset)
    print(
        "ios: 2 arm64 IOS frameworks, iOS 13+ minimum, install names/linkage/"
        "rpath, both native-asset mappings, and Cutlet 24/Open JTalk 23 exact "
        "exports verified"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command, help_text in (
        ("source", "verify path dependencies and resource exclusions"),
        ("android", "verify a release APK"),
        ("ios", "verify an unsigned iOS .app bundle"),
    ):
        subparser = subparsers.add_parser(command, help=help_text)
        subparser.add_argument("path", type=Path)
    arguments = parser.parse_args(argv)

    try:
        if arguments.command == "source":
            verify_source_tree(arguments.path)
        elif arguments.command == "android":
            verify_android(arguments.path)
        else:
            verify_ios(arguments.path)
    except (
        OSError,
        subprocess.CalledProcessError,
        VerificationError,
        zipfile.BadZipFile,
    ) as error:
        print(f"verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
