# Nimony October 28 nightly upgrade

## Scope and identities

Upgrade master `41a74790` from official Nimony 0.6.3 October 26
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee` to October 28
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`. The release was published at
14:58:07 UTC on October 28. Sort by publication time rather than relying on API ordering.
The official macOS ARM64 and Linux amd64 archives match their release-asset SHA-256 digests
and embedded commit/date/platform metadata. Linux ARM64 is pinned to its official asset digest;
its archive was not downloaded locally. Do not claim Linux runtime qualification from macOS.

| Archive | SHA-256 |
| --- | --- |
| linux_amd64 | `2425e2dca6e4b13fb2b4149b75e0f445feb61702caab02960df91cf085723a3c` |
| linux_arm64 | `960fb1093e2acee648ccc4f3b8991f171289945aee23c37b1a21be6a040779f8` |
| macos_arm64 | `514b85d257206176cd8851d383558f19faa914e8c2d3c27978f132b5ce718f36` |

The matching browser compiler source has SHA-256 `5e23ea2821115ac334215a93a1f524032e076767afcf45805fb8f98697f80396`.
Its `src/nativenif.commit` selects `60f400e7104e534da63e38d79ac17eab0b1b19ee`, source
SHA-256 `97785fbbad4e944a9e87545a151fbb0e7d7066a9ce52c2c84d3c43ed8e52bb34`.
Build the backend from those pristine sources through the maintained Make setup. Keep Nimpretty
2.2.12, independent protocol/provider pins, ARC/Clang, checked bounds/assertions and ThinLTO.

## Compatibility changes and retained choices

The [20 included commits](https://github.com/nim-lang/nimony/compare/358b9bce4dd855453f57a80a0c499b0b2e27d7ee...63fed6cb4b2f59d34c9fbb18f1796e671e2024e4)
include the requested nil-proof repair and additional ownership enforcement.

- [#2811](https://github.com/nim-lang/nimony/pull/2811), followed by
  [#2813](https://github.com/nim-lang/nimony/pull/2813), preserves the pointer's presence when
  a mutable call changes its pointee. The original inferred-local reproducer and explicitly typed
  control compile and execute, including nil input. Remove redundant guarded-pointer annotations in the block/session and ancestor transport
  fixtures, and retain repeated var-call coverage in a new
  `nimony_pointer_refinement` native suite. Explicit types elsewhere can still document an API
  boundary; no blanket annotation rewrite is required.
- Every written destructor now requires a written moved-from hook. Add 45 missing hooks while
  preserving ten existing hooks and their lifecycle restrictions. Aggregate hooks delegate to
  each field's own hook, preserving nested move contracts rather than zeroing whole owners.
  PreparationWorker requires joined shutdown before relocation, like the existing worker owners.
  Raw native handles become nil; secret scratch is wiped without releasing transferred ownership.
  Keep every destructor, copy/dup ban, explicit-close obligation and stable callback/thread lifetime.
- The compiler now rejects explicitly inconsistent copy/dup error annotations. Retain the existing
  move-only exclusions and require their original rejection predicates to pass.
- Selected-symbol re-exports no longer introduce the underlying module name. Preserve explicit
  imports/aliases; do not depend on accidental namespace exposure.
- Hastur adds `--parallelBuild` to cap concurrent executable builds. Keep the project's existing
  source-owned scheduling, private caches and serial linked profiles in this upgrade. The macOS
  ARM64 and Linux amd64 archives still lack `bin/jorogumo`, so the matching-source browser
  backend setup remains necessary.
- Literal-index alias refinement, optimizer improvements, supportsCopyMem tuple handling, stdlib
  buffer lifetime fixes and strutils contracts are included. JSON raw-number and SmartCLI variadic
  APIs do not replace the current bounded protocol readers or explicit command grammar in this PR.
- NIM-002 remains closed as expected behavior: `SomeInteger` does not guarantee a dollar operator.
  Concrete JSON integer overloads stay as the supported implementation choice.

## Remaining issue and qualification scope

NIM-004 still hits the same assertion on the new official archive in five clean outside-project
directories. Its empty-source and unqualified controls compile and execute successfully.
The [standalone draft](nimony-reports-2026-10-28/qualified-declared.md) retains exact redacted
current output. No upstream issue was filed. See the [issue register](compiler-issues.md).

Linux-target semantic checking from the macOS archive asserts in `app/cli_catalog.nim`.
The same focused check asserts under the old October 26 archive with identical source and flags;
this does not establish a new upgrade regression or a native Linux failure. Native Linux CI
must qualify the published PR; record that result separately from local macOS tests.

## Local validation

On macOS ARM64 with the new pristine archive:

- Canonical `make check-smoke` passes after the ownership adaptations.
- Complete debug and checked-release audits pass all 473 production modules plus the actual
  integration/offload peer main. The optional PolkaVM-enabled PVM module also passes semantic
  checking; these checks are distinct from native execution.
- All 2,688 existing compiler rejection guards pass their original predicates: 2,081 privacy,
  523 nominal, 12 contracts, five schemas and 67 ownership fixtures.
- 102 selected native suites pass: the 101-suite run plus the ancestor-dispatch consumer after
  its fixture cleanup. Coverage includes the new nullable-pointer regression, sequence ownership,
  crypto owners, paged/full-paged/file/light-journal storage, checkpoint and proof workers,
  RPC/UI/management/MCP/telemetry, downloads, and real JIT/fallback/PolkaVM runtime policies.
- All 188 strict runtime misuse cases in 18 affected families pass after successful positive
  builds, retaining their original expected assertion/contract messages.
- All 106 selected Python CI, Make and native-runner safeguard tests pass. This is not full
  Python discovery or full native inventory qualification.
- The maintained production build succeeds; its QUIC selftest passes 10,000 malformed DER/frame
  cases and its integration selftest passes 10,000 arbitrary digest captures. The browser RPC
  regression passes against the real production `ragnarok_clientInfo` endpoint using the matching
  backend. This is not full E2E, full fuzzing, a security audit or a performance comparison.

The full pinned formatting check passes 4,895 Nim sources and Rust; the subsequently edited
transport helper files also pass the pinned formatter individually. Documentation relative links
and whitespace checks pass. Initial failure receipts are retained separately from successful
post-adaptation checks; no test predicate, compiler check or runtime assertion was relaxed.

Local raw release metadata, checksums, commit review, probes, module audits and native/guard
receipts live under ignored `build/ci/nimony-oct28/`. Native Linux PR smoke remains a separate
qualification step; no Linux runtime result is claimed here.
