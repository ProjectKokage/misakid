# Native source manifest

The native adapter is built from an explicitly supplied, extracted official
MeCab-ko archive. The package performs no download.

## Source release

- Project: Eunjeon MeCab-ko
- Version: `0.996/ko-0.9.2`
- Release tag: `release-0.9.2`
- Tagged commit: `908db8de3cb5f4931b4e3a7a5a3894daefb98c37`
- Archive: `mecab-0.996-ko-0.9.2.tar.gz`
- Archive size: 1,414,979 bytes
- Archive SHA-256:
  `d0e0f696fc33c2183307d4eb87ec3b17845f90b81bf843bd0981e574ee3c38cb`
- URL:
  `https://bitbucket.org/eunjeon/mecab-ko/downloads/mecab-0.996-ko-0.9.2.tar.gz`
- `COPYING` SHA-256:
  `9ed8a017f2226b6f0d6dd6a1d25404800374a12c70e14a56ca9613176f78778e`
- selected `BSD` SHA-256:
  `62f4b23450a9ad40e4db8063d45c1d13c78d07ca27c9ada62c4ca9c11c1f3e7b`

The source verifier recursively enumerates real files, rejects links and
special entries, sorts relative POSIX paths, and hashes records of:

```text
UTF-8 relative path, NUL, lowercase file SHA-256, newline
```

The accepted unmodified tree is exactly 236 files, 7,840,684 bytes, and
aggregate SHA-256
`9b870a921e8d80fa11eec1066d21c0960916fa617e77a8c83758223dfe28827f`.
The clean tree was also compared byte-for-byte with the tagged commit.

## Compiled runtime

`native/CMakeLists.txt` compiles only the MeCab runtime and new adapter C ABI,
not the command-line executable, dictionary compiler, training programs, or
Python binding. It generates `config.h` in the build tree, pins macOS arm64
and a macOS 11 deployment target, hides every upstream symbol, and exports
only the versioned Misakid ABI. The adapter passes fixed argv entries
`--rcfile`, `/dev/null`, `--dicdir`, and the caller-validated directory; it
does not consult `$HOME`, `MECABRC`, or a shell.

Compiler prefix mapping removes source and package paths. Two independent
clean builds produced byte-identical 217,384-byte dylibs with SHA-256
`30794f21cc6c7be98cbe84f669c867bfe6947c87cf611152d306caa9ef32b8cd`.
The library has an `@rpath` install name, macOS 11 minimum, arm64 Mach-O
architecture, and links only `libiconv`, `libc++`, and `libSystem`.

## Misakid safety patch set v1

The upstream `src/common.h` implementation of `CHECK_DIE` writes a diagnostic
to process-global stderr and calls `exit(-1)`. After proving the unmodified
tree identity, the build tool applies three exact context-checked edits to
that file:

1. add `<stdexcept>`;
2. replace the terminating `die` helper with an `ostringstream`-backed object
   whose destructor throws `std::runtime_error`; and
3. route `CHECK_DIE`'s stream chain through that helper instead of
   `std::cerr`.

The new C ABI catches the exception and returns a bounded diagnostic without
input text or configured paths. The valid upstream branch is unchanged, and
all 34 captured morphology streams remain exact. A subprocess test proves
byte-empty stdout and stderr for both valid analysis and an invalid native
dictionary load.

These changes are identified by the immutable native field
`misakid-mecab-ko-safety-v1`. CMake independently enumerates every post-patch
staged file before configuring. The accepted tree is 236 files and 7,840,991
bytes. Its sorted `path`, tab, lowercase file SHA-256, newline record digest
is `f12784924ac4a55296520308472d55e433a50e708f338fd52a9106ece5997691`.

## Dictionary identity

The ABI independently validates the loaded system dictionary as UTF-8,
dictionary format version 102, 816,283 words, left size 3,822, right size
2,693, with no chained user dictionary. Dart first validates all 11 files,
112,191,702 bytes, and canonical tree SHA-256
`d851fab8708745442ac3a2d970851dbd0ef598e786a363f406847461d77a6f51`.

## ABI ownership and bounds

ABI version 1 owns opaque contexts and per-call result objects. Each result
copies every surface and POS tag before releasing the process-global MeCab
mutex and remains valid across later calls. Create, analyze, and destroy are
serialized across Dart isolates. The boundary validates strict UTF-8 and
rejects NUL.

Inputs are bounded by the caller's 1..64 MiB configuration. Results are
bounded to 65,536 tokens, 1 MiB per surface or tag, and 64 MiB aggregate.
Fixed-capacity diagnostics never include input text or resource paths. Every
C++ exception is contained. Inherited MeCab code still has unchecked extreme
allocation sites, so process-wide out-of-memory is not promised to be a
recoverable typed failure.
