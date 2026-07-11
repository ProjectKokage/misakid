# Native source manifest

`libmisakid_espeak_en` is compiled only from the package-owned Apache-2.0
files below:

- `native/include/misakid_espeak_en.h`
- `native/src/misakid_espeak_en.cpp`
- `native/CMakeLists.txt`

It uses `dlopen`/`dlsym` against the caller-supplied eSpeak NG library at
runtime. No eSpeak NG or phonemizer source, header, data, model, voice, binary,
or generated artifact is compiled into or linked by the shim.

The owned-result-v2 source validates the caller's exact runtime library and
complete 37-directory/364-file data tree again inside the native boundary.
Its CMake build is pinned to macOS 11 arm64, maps source paths out of debug
metadata, and produces byte-identical dylibs in independent clean builds with
the same Apple toolchain.
