# Working in Misakid

Misakid is an idiomatic Dart port of Misaki. The root package is pure Dart;
optional native/model adapters live in `packages/`.

## Start here

Read [README](README.md) and the relevant mode in
[PORTING_STATUS.md](PORTING_STATUS.md). For a behavior change, read its entry in
[PORTING_NOTES.md](PORTING_NOTES.md), the relevant
[porting contract](doc/porting_contract.md) sections and pinned upstream source.
For an adapter, also read that package's README. Use
[reference tooling](tool/reference/README.md) for oracle/fixture work.

Inspect the working tree and preserve unrelated edits and unpublished commits.
State the affected mode/boundary, expected behavior and checks. Keep one complete
slice per task; do not scaffold unrelated languages or redesign public APIs.

## Essential contracts

- Pinned Python behavior defines parity. Do not silently follow upstream main,
  linguistically correct quirks, or change normalization to make tests pass.
  Upstream sync is a separate change with reviewed fixtures and provenance.
- Compare exact Unicode output, whitespace, order, token metadata and null
  versus empty values. Never generate expected results from the Dart port.
  Capture a regression before changing behavior; intentional divergence needs
  an explicit compatibility decision and independent expected results.
- Keep conversion offline and the core free of Flutter, `dart:io`, Python and
  implicit native dependencies. Inject typed backend interfaces; resources and
  fallback selection are explicit. Missing backends fail with typed errors.
- Preserve Unicode/code-point semantics, bounds and native/process ownership.
  Pass subprocess arguments directly, bound captured output, and support
  timeout/cancellation where possible. Do not log full user text by default.
- Keep APIs immutable, typed and small. Separate sync and async engines;
  preserve phoneme/chunking contracts at the Kokoro boundary. Do not export
  internals for tests or hand-edit generated data/bindings.
- Committed runtime tables own normal development inputs. Temporary upstream
  extraction belongs to an explicit sync task. Preserve independent fixture
  provenance, checksums, attribution and [notices](THIRD_PARTY_NOTICES.md).
- Keep model candidates, binaries and caches outside Git. The only approved
  model-publication exception is the exact
  [en-US G2P pair](models/en-us-g2p/v1-5ce8863c502d/README.md); preserve its bytes
  and notices and exclude `/models/` from Pub packages. It authorizes no runtime
  download. Public push requires owner review of the unpublished commit range.
- A supported mode needs the exact dependency/platform configuration and parity
  evidence in the status document. Do not generalize a fixture pass to another
  language, model, backend or target.

## Verification

For code changes, resolve dependencies as needed, run focused tests, then run
these checks from each affected Dart package:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Behavior changes need the applicable committed parity cases; ordinary tests
remain offline and must not overwrite goldens. Oracle/fixture changes also
need the documented read-only reference verification with the exact provisioned
interpreters. Regeneration is a separate explicit acceptance step with a
reviewable diff, never a way to accommodate an unexplained mismatch.

Run `dart doc --dry-run` for public API/documentation changes. Run
`dart pub publish --dry-run` when package contents, metadata or distribution
boundaries change; report an omission when it cannot apply. Do not publish with
Git or path dependencies. Keep published-library `pubspec.lock` files untracked;
a separately documented workspace/tool policy may differ.
Real-adapter/mobile qualification requires its documented provisioned checks.
[CI](.github/workflows/ci.yml) owns the full SDK/platform matrix.

For prose-only guides/instructions, check links, command paths and
`git diff --check`; no oracle provisioning or full Dart suite is required.
Update status, notes and notices only when their underlying facts change.

## Delivery

Branch names must not begin with `codex` (case-insensitive), including
`codex/` and `codex-`. Rename tool-generated defaults before committing or
pushing; use a descriptive name such as `docs-agent-guides`.

Use a task branch, review the diff and commit only task files. Push, publish or
release only when requested; merge only with owner approval. Routine work within
the authorized scope can proceed. Obtain approval before expanding scope or
changing recorded compatibility decisions. Report checks, supported modes and
any missing evidence without weakening tests or hiding features.
