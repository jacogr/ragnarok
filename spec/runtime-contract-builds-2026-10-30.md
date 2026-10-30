# Runtime Contract build pilot — October 30, 2026

## Scope and preserved inventory

Starting master: `9619c3971042a370f682ab9d7500090575f975b8`. The current inventory matches the
reviewed snapshot: 386 ordinary families, 3,930 planned checks including specialized controls.
Every original family, case identity, argument, expected diagnostic and build requirement is
preserved. Compiler Guards, ordinary units, production source, contracts and dependency pins
are outside this change.

The pilot combines only `pvm_execution`, `pvm_fallthrough`, `pvm_gas` and `pvm_step`: four small
PVM drivers with the same checked build profile and no native libraries. Their 20 negative probes
still execute in independent child processes. Generated main imports preserve module scopes;
original fixtures remain executable on their own. Bundle assignment keeps the four together on
one shard, with deterministic seed replay. Existing intermediate reuse, native ABI identity and
build locking are retained.

Ordinary executable builds fall from 386 to 383. Eight existing specialized builds remain;
two additional checked/ThinLTO qualification builds make 393 total scheduled builds versus 394
before. The additional 16 planned qualification checks bring the full inventory to 3,946. This is
a bounded pilot, not an assertion that four-family consolidation is the optimal group size.

## Setup and failure premises

Contract uses partition-derived Make prerequisites instead of full application setup. Compiler,
pinned sources and generated build metadata remain mandatory. Native providers are the union of
ordinary and specialized declarations. Cargo fetching remains the existing locked/offline setup
path. Model-tool preparation is unnecessary. UI generation remains for transitive UI-server
imports (24 ordinary fixture families at this revision); it is omitted only from partitions
without such consumers. Unused integration corpus preparation is removed from Contract; specialized
availability, composition and offload controls retain their independent inputs.

`pvm_step_results.nim` checks decoding, memory capture and machine capture success before reading
setup payloads. Before the deliberately forbidden result extraction it requires the exact
Uninitialized, InvalidMachine, UnsupportedInstruction or GasCycleLimitExceeded state, as appropriate.
A wrong premise exits 2, while the expected accessor rejection requires exit 1 and the original
`r.status == None` plus `[AssertionDefect]`. The premise helper intentionally has no static
postcondition: the runtime negative must compile successfully. The approved former-negative
program still checks its successful exit, PC and register value.

## Production-profile qualification

The same small source runs with checked ARC/Clang/release/speed and with those checks plus the
shipped ThinLTO flags; caches are profile-isolated. Each typed mode is a separate child process.

| Mechanism | Rationale and required observation |
| --- | --- |
| Sequence slicing, NIM-001 | [Original defect](nimony-reports-2026-10-23/sequence-slice.md), upstream #2782/#2789. The original slice must compile and retain independent mutable storage under optimization. |
| Pointer refinement, NIM-003 | [Original reproduction](nimony-reports-2026-10-27/nullable-var-call.md), fixes #2811/#2813. Both mutating pointee calls must retain the inferred pointer proof and update the actual value. |
| Noncopyable sequence move, #2737 | [October 21 evidence](nimony-nightly-2026-10-21.md). A legal explicit transfer must preserve its exclusive-owner token without copying. Compiler-negative copy prohibitions remain the separate Guards suite's responsibility. |
| PVM step result refusal | Result-tag and payload-access lowering must still enforce all five premise-checked refusals under ThinLTO. A wrong state, compile rejection or unrelated assertion cannot pass. |

## Validation and timing

Python harness tests exercise shared builds, failed-build refusal, original probe identities and
arguments, deterministic shard co-location, preparation selection, cache-profile separation,
compiled enumeration and refusal of wrong-state/status/positive-output observations. Native builds
and timings run on CI only, respecting the maintainer's local timing work.

The opt-in CI measurement runs two counterbalanced standalone/bundled pairs, each in fresh private
intermediate caches with identical inputs and checked flags. All 20 original negative probes and
three original positive fixture modes must pass before timings are valid. Setup, native-provider
preparation, fixture preparation, compilation and child execution have separate receipts. The
measurement is additional work, never a replacement for normal Contract checks.

Native results and comparable timing measurements are pending CI qualification. No measured runtime
saving is claimed yet. Full CI aggregate time also includes runner provisioning, scheduling and
additional qualification; it cannot be estimated reliably from executable counts alone.

Remaining opportunities: expand sharing only after this pilot is measured; audit other failure
premises individually; consider more precise pinned-source preparation if evidence warrants it.
No probe reduction or execution-frequency change is part of this work.
