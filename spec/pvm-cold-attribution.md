<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Inclusive Sieve cold host attribution

This opt-in diagnostic consumes an explicitly passed current canonical `micro` or `all` cohort
and its live native Linux x86-64 production guest image. It profiles the complete unchanged
forced-interpreted Sieve1000 process three times: inclusive `decodeArtifact` (one return),
inclusive `prepareIndependent` (one return), and `runPreparedKernel` (thirteen returns).
All thirteen original state/gas/register/memory/output checks remain required in every process.
It changes no protocol semantics or pinned specification and supplies no timing/parity verdict.

Use `make profile-pvm-cold PVM_COLD_REPORT=<report.json> PVM_COLD_SOURCE_REVISION=<full-sha>`
only in its supported native CI context after separate qualification. An explicitly rebuilt image
requires `PVM_COLD_REBUILT_REPORT=<independently-passed-current-report.json>` for the same product
revision, checked recipe/compiler/toolchain/build environment and logical input bytes. The target
does not provision a toolchain, build a guest, fetch inputs or silently replace an absent image.

Admission retains ordinary `validate_current_report`: incomplete/historical reports and paired
source-comparison cohorts cannot be retagged or supplied instead. The selected source seals must
match the complete immutable Git object. The guest producer's exact checked ARC/Clang ThinLTO
argv and native defines remain fixed. The live binary, three consumed inputs, qualification
documents, profiler and imported helper closure are sealed around every child command. The
Sieve input's native header must actually identify limit1000, even with coherent report hashes.
Qualification CI identity and profiling CI identity remain separate recorded evidence.

The maintained `nm --defined-only` selector requires a unique actual text definition for each
scope in that unchanged Linux image. Missing, inlined, cloned/ambiguous or foreign symbols fail;
local Mach-O symbol observations do not qualify a Linux executable. No hooks, changed driver,
disabled checks or instrumentation build are used to manufacture a scope. All three symbols must
qualify before calibration or collection. The ordinary canonical DOOM adapter and historical
profiling modes are unchanged; there is no synthetic host or comparison-report admission here.

The maintained collector/calibration controls establish selected/absent collection and repeated
work/return-dump reset. Each collection retains its existing1200-second cap without retries.
The expected exact1/1/13 numbered parts and empty final dump are required, and every numbered
part supplies reconciled exclusive costs and complete `Ir,Bc,Bcm,Bi,Bim` host simulation counters.
The first/final execution return is an individual observation, not the canonical reused median.
Raw logs, dumps, annotations and hashes survive partial failure; the current result is failed
instead of borrowing stale success. Instrumented process failure or malformed full-call/native
policy/lifecycle grammar invalidates even complete dumps. Forced interpreted requires absent
compiler runtime and zero native activity.

These are separate inclusive function scopes, not an enclosing cold-call measurement. Caller
copies, capture outside a selected function and driver/oracle work can lie outside them. No
durations are subtracted, no costs are summed into a new cold score, and no per-call readiness
is inferred. Instrumented CPU/wall/constructor/owner clocks are discarded from profile results;
simulated host instructions/branches are not hardware counters or guest-instruction costs.
The bounded workload is three complete13-call processes (39 logical calls), in addition to the
maintained four C calibration controls. No performance claim follows from source-only testing.

Focused inert coverage lives in `tests/test_pvm_cold_profile.py`: complete authority and exact
workload selection, unique scopes,1-versus13 dump boundaries, full13-call/native-zero parsing,
changed source/input/helper seals, absent-image/foreign-host refusal and failed calibration/process
retirement. Maintained collector and canonical DOOM tests continue to own their shared mechanisms.
Native Linux execution, actual ELF symbols, counter/calibration behavior and exact-image current
cohort qualification remain required before claiming this diagnostic has run successfully.
