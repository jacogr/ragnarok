# Nimony October 26 nightly upgrade

## Scope and identity

Start from master `5de8efcb` and upgrade official Nimony 0.6.3 from October 23
`4724f66c2e01b17810c844f26575b2317995fda2` to October 26 `358b9bce4dd855453f57a80a0c499b0b2e27d7ee`.
The release API's ordering differed from publication ordering; select the newest published
nightly, not its first returned release. The [26 included commits](https://github.com/nim-lang/nimony/compare/4724f66c2e01b17810c844f26575b2317995fda2...358b9bce4dd855453f57a80a0c499b0b2e27d7ee)
include the requested slice fix. Official macOS ARM64 and Linux amd64 archives are SHA-256
verified against release asset digests and their embedded commit/date/platform metadata.

| Archive/source | SHA-256 |
| --- | --- |
| macOS ARM64 | `7955438a772c3536694d491d4c608f482d55350e321eb2fa5a559b7bab7b9f7a` |
| Linux amd64 | `ea6fd4d024ab86d2d26e093321013fac4058a4360bd511f20b5557663fa9f0e1` |
| Matching Nimony browser source | `1b83738bc0f6a456b41a2068ad19654217cbff9f1dcba4a6b5b62d84f142c312` |
| Matching nativenif source | `7f28e3f1f8fea5d1a56609b93663ec2f992e382d09a24cf50cca81a82c5e2d9a` |

The matching browser source requires nativenif `40324cc66745fb88816b9d613200361a16bf58c9`, read from its
`src/nativenif.commit`; update that dependency with its exact source checksum. Keep Nimpretty
2.2.12, ARC/Clang, checked bounds/assertions, ThinLTO and the current master's independent
protocol/provider pins. No compiler, stdlib, native dependency or private-runtime patch is used.

## Included fixes and exercised decisions

- [#2789](https://github.com/nim-lang/nimony/pull/2789) fixes the submitted
  [#2782](https://github.com/nim-lang/nimony/issues/2782) sequence-slice defect. An unchanged
  outside-project reproducer fails on the October 23 archive; its successful assertion compiles
  and runs on this archive. Restore owned slices in authored admission headers, shortened sealer
  and repository-image fixtures, and the two-response download fixture. Remove the dedicated
  refinement-prefix assertion helper. Preserve exact ranges, byte assertions and all malformed
  cases. Keep read-only borrowed views/indexed markers where they avoid extra allocation.
- A source-owned native suite retains inclusive, backwards, half-open and empty-range controls,
  plus independent sequence and nested-string mutation checks. Copy-banned-element and explicit
  move regressions remain in place.
- Forwarded-var borrow checking now catches five owner/field argument overlaps: the paged
  context digest, full-paged flush, light proof ticket, light query policy and full-node proof
  ticket. Capture only the fixed digest/policy and small host-only ticket values. Split full-paged
  append accounting from the callback borrow and Boolean completion; preserve callback refusal,
  IO/write budgets, exact padding and partial-write uncertainty without copying a 4 KiB page.
- Tighter loop-bound contracts, NIF/BIF input bounds and build-shell argument quoting are
  included. Keep all checked release settings and exact compiler-rejection predicates.
- std/json tree parsing/null behavior, TLS/HTTP/DNS/compression/crypto hardening and std/websocket
  additions do not replace the current bounded token JSON readers, native transport or providers.
  Custom native-worker lifetimes remain; the std/threadpool backoff fix authorizes no pool rewrite.

## PVM allocation discovered during qualification

The actual disk-download native scenario hit a macOS preparation-worker stack guard in
`decodeInstructionMiss`. Its spill constructor materialized a 1 MiB default array temporary.
The old compiler emits the same large literal in a focused control; this is not attributed to
an established new compiler regression. Direct `new(out)` allocation initializes the same fixed
heap table without that stack temporary. Old/new compiler controls both return size 1,048,576
and verify default entries at both ends; the real disk-download scenario passes after this change.
Retain the spill threshold, capacity, lookup/replacement rules and original cache ownership.

## Remaining report drafts

Generic `SomeInteger` formatting and nullable refinement across successive var-pointee calls
still fail on the actual archive. Each minimal reproducer fails 5/5 times from independent empty
outside-project directories; deleting any nonblank line stops its intended failure. Both exact
workarounds compile and run. Refreshed [integer](nimony-reports-2026-10-27/integer-generic.md)
and [callback](nimony-reports-2026-10-27/nullable-var-call.md) drafts include the final output,
current pin/environment, private-path redactions and checks not performed. Preserve the concrete
integer overloads, explicitly typed nonnull callback bindings and retained-ref index loops.
The maintainer will submit the reports; no new issue or comment was posted from this task.

## Qualification

Local macOS ARM64 qualification:

- Canonical debug smoke and checked-release audits pass all 450 production modules plus the
  real integration/offload main. The same complete Linux amd64 graph/main pass semantic checks;
  this is not Linux runtime evidence. Pinned formatting covers 4,832 Nim inputs plus Rust.
- All 2,682 compiler guards pass with their existing exact predicates: 2,076 privacy, 523 nominal,
  12 contracts, five schemas and 66 ownership/lowering fixtures. No rejection is accepted merely
  because an unrelated import fails.
- All 59 selected native suites pass, including every previously affected slice suite and all
  13 full-paged builder/codec/context/publication/crash/reader/recovery/retention suites. The two
  earlier passing binaries containing the changed decoder are rerun after the heap-allocation fix;
  the slice suite is rerun with an explicit zero-length prefix as well as an interior empty range.
  The complete independently generated block corpus passes all 17,194 requests.
- All 109 strict runtime misuse probes in six selected storage/worker/download families pass
  after successful checked builds. All 24 selected real executable download cases pass, as does
  the signed cancellation/reset/resource workload with all 33 joined idle observations, no
  descriptor growth and retained RSS growth within its declared budget.
- The real browser/production RPC test passes with the matching pristine browser backend.
  The relocated macOS package passes the maintained smoke checks; independently verify every
  packaged file hash and its exact compiler/ThinLTO manifest metadata. All four strict native
  fresh reopens pass independent report validation.
- The bounded sanitized program fuzzer passes 10,000 inputs plus its frozen seed and
  assertion/artifact/replay controls. Its program-decoder inputs do not include the later
  private execution-cache allocation change; this unchanged-input result is reused. Default
  allocator/fine-grained heap and finite-corpus coverage limitations remain unchanged.

The original complete Python discovery reaches its configured 1,800-second deadline after
1,051 completed cases (including two skips), before completing the next provenance test.
That exact test passes independently in 9.406 seconds. Run the remaining 464 cases in discovered
order; they all pass. The combined identity-checked coverage therefore includes every one of
1,516 discovered cases, with two skips. Preserve the original failed timeout receipt separately:
this is complete case coverage across resumed runs, not a successful single invocation of
`make check-python`, and no timeout or test predicate is relaxed. No Python implementation or
reference source is changed by this PR.

Raw compiler range, release, archive, isolated probe, crash/control and selected-run evidence is
under ignored `build/ci/nimony-oct26-*`. Python timeout/resumption files retain the initial
verdicts, exact resumed identities and the distinction above. Verification is scoped local runtime
and Linux semantics; it does not claim full E2E, full native inventory, Linux runtime, exhaustive
fuzzing or a new performance comparison.

The maintainer expects another PR tree before merging this upgrade. Keep this ordinary PR open;
merge the announced incoming master changes normally and recheck affected consumers when requested.
Automatic Compile / Smoke runs on publication; heavy CI labels and merging are not requested.
