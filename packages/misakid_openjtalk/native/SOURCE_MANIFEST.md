# Native source manifest

The native library is built from an explicitly supplied, extracted
`pyopenjtalk-0.4.1.tar.gz`. No source or binary is downloaded by this package.

## Source distribution

- Project: `pyopenjtalk`
- Version: `0.4.1`
- Archive size: 1,397,999 bytes
- Archive SHA-256:
  `d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc`
- URL:
  `https://files.pythonhosted.org/packages/58/74/ccd31c696f047ba381f9b11a504bf1199756c3f30f3de64e3eeb83e10b4a/pyopenjtalk-0.4.1.tar.gz`
- pyopenjtalk MIT license SHA-256:
  `c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b`
- Open JTalk `COPYING` SHA-256:
  `14f380a0db8dce139fdcfb731d21e993a31a00b68907515d1c54a5f356241343`
- embedded MeCab `COPYING` SHA-256:
  `05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650`

The source verifier reads `pyopenjtalk.egg-info/SOURCES.txt`, selects sorted
paths below `lib/open_jtalk/src/`, strips that prefix, and hashes records of:

```text
UTF-8 relative path, NUL, lowercase file SHA-256, newline
```

The expected identity is exactly 139 files, 5,381,473 bytes, and aggregate
SHA-256
`dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857`.
Generated `config.h`, build products, Python extensions, HTS code, voice data,
and audio code are excluded.

## Compiled frontend

`native/CMakeLists.txt` explicitly compiles the MeCab runtime plus:

- `text2mecab`;
- `mecab2njd` and NJD records;
- pronunciation and digit transforms;
- accent-phrase and accent-type transforms;
- unvoiced-vowel transform; and
- the pinned long-vowel stage.

It does not compile or link HTS synthesis, voices, audio, `jpcommon`, or
`njd2jpcommon`. `config.h` is generated in the build tree, never in the
supplied source tree. Compiler file-prefix mapping replaces the caller's
absolute staging path with the stable `open_jtalk` prefix. Two clean local
build directories produced byte-identical dylibs; no caller path remained in
the binary.

## Misakid safety patch set v1

The build tool first proves the unmodified source identity, copies only the
manifest files to a dedicated staging directory, and then applies two exact
context-checked changes:

1. `NJDNode_insert` no longer calls `exit(1)` for an invalid graph. A terminal
   insertion is discarded without changing the live list, the active loop can
   finish safely, and a bounded `digit` diagnostic causes the complete result
   to fail. The accepted valid path is unchanged.
2. The deprecated, compile-disabled long-vowel estimator's invalid-byte path
   no longer calls `exit(1)`. It records a bounded `long-vowel` diagnostic and
   returns safely if that branch is ever re-enabled.

Pinned Open JTalk also writes some diagnostics directly with `printf` or
`fprintf`. A force-included adapter header redirects those C stdio calls to
inert functions. Status-bearing stages are checked by the new ABI and exposed
as bounded structured errors without input text or configured paths. The
provisioned test separately proves that both valid analysis and an invalid
native dictionary load produce byte-empty stdout and stderr.

These changes are identified by the immutable native build field
`misakid-openjtalk-safety-v1`. They intentionally convert process termination
into a typed adapter failure; all 24 accepted valid frontend streams remain
byte-for-byte equal to pyopenjtalk 0.4.1.

CMake independently enumerates and hashes every post-patch staged file before
configuring a target. The accepted safety-v1 tree is exactly 139 files and
5,382,103 bytes, with the CMake record digest
`8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb`.
Relative POSIX paths are sorted as complete strings; each digest record is the
path, one tab, the lowercase file SHA-256, and one newline. The SHA-256 of the
concatenated UTF-8 records is the value above.
This prevents a direct CMake invocation against untouched or modified source
from emitting a library that falsely reports the reviewed patch-set identity.

## Native ABI ownership

ABI version 1 uses opaque contexts and per-call results. Results own contiguous
copies of every one of the 11 string and three integer NJD fields and remain
valid independently of the Open JTalk state until explicitly destroyed. A
process-global native mutex serializes initialization, analysis, and context
destruction across Dart isolates. Every C++ exception is contained at the C
boundary; fixed-capacity diagnostics and result/input limits bound failure
data and adapter-owned allocations. A direct ABI test retains one result,
performs another analysis on the same context, and then rereads every retained
field before destruction.

The inherited Open JTalk/MeCab C routines still contain unchecked allocation
sites; an extreme system out-of-memory condition inside those routines is not
promised to be recoverable as status 8. The frontend rejects more than 65,536
MeCab words before NJD construction and retains the same cap after NJD
transforms. Individual copied fields are limited to 1 MiB and aggregate copied
string data to 64 MiB.
