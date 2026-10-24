# Calibrated diagnostic opcode and pair census

## Scope and reproduction

Run `make census-pvm` to count interpreted PVM instructions and adjacent opcode pairs in the
existing eleven frozen checked workloads. This is diagnostic data for choosing future dispatch
experiments, following the interpreter-optimization [discussion supplied by the maintainer](https://langdev.stackexchange.com/questions/1724/what-are-some-common-ways-to-optimise-an-interpreter).
Frequency is not CPU cost; these synthetic programs do not establish real-guest or whole-JAM
representativeness. Continue to use sampled profiles and paired timings on maintained upstream
guests when deciding what to optimize.

The tool copies owned PVM modules, the natural codec and existing workload driver into ignored
`build/tests/pvm-census/snapshot/` paths. Only that copied step module is instrumented. Every named
injection site must occur exactly once before mutation; missing, duplicate or already-instrumented
sites fail. Compiler/runtime sources, production modules, instruction semantics and public APIs
remain unchanged. Original/generated source hashes, binaries, input contracts and commands remain
in the aggregate report. Source, harness or fixture changes during the run invalidate publication.

## Invocation-local counter contract

Counters belong to the same private execution cache as each invocation's decoded/price/target
facts. They retain scalar counts only, never programs, machines, memory, callbacks or contexts.
A valid admitted instruction evaluation contributes exactly once; pricing and decoder probes do
not contribute. The previous opcode survives host continuations within that invocation, while
new/nested executions start separately. No terminal-to-start pair crosses invocation boundaries.
Both guest and terminal host replies can close a completed observation.

All256 byte opcodes have independent uint64 counters. Pair storage has512 bounded exact16-bit
keys with linear collision probing. Counters guard overflow; table saturation fails instead of
silently dropping transitions or publishing a partial result. This is a diagnostic resource
policy, not a guest admission/default or a new prepared representation.

## Calibration and report integrity

The ordinary uninstrumented control must compile and explicitly refuse calibration. The ignored
instrumented control then checks two fresh invocations, nested execution inside both callback
forms, preservation of the outer host-to-jump pair, and terminal replies without invented guest
steps. A separate deliberate capacity overflow must produce the exact refusal before any
completed census is emitted. Source/profile mistakes cannot fall back to uninstrumented counts.

The existing native workload driver retains complete independent CPU/gas/memory/source assertions.
Its strict output parser still checks every sample and pricing metadata. Benchmark execution and
preparation timings are then discarded; build/process durations survive only as command-log
metadata. Instrumentation overhead must never be presented as a performance measurement.

The census parser requires complete invocation framing, bounded canonical integers, unique opcode
and pair rows, opcode/transition totals, valid endpoints and one connected walk. Missing, duplicate,
interleaved, inconsistent or disconnected output cannot yield a result. All thirteen samples per
workload must have identical counts and the independently expected exact step total. Dynamic,
complete-plan and lazy-memo runs must also agree. Earlier aggregate success is retired before
preflight; only a fully validated run publishes another aggregate.

## Observed completion and next work

Three native calibration controls, five Python guard/parser tests, source inventory and pinned
formatting pass. All eleven workloads pass429 fully validated invocations across the three pricing
policies. Counts match across cold/warm samples and policies. Per-invocation totals range from4 to
30001 PVM instructions and3 to10 distinct pairs. The large arithmetic case repeatedly contains
131→131 and131→83; the memory/host cases expose their distinct load/store/callback transitions.
These are frequencies of virtual instructions, not native CPU instruction or latency counters.

Reports and complete raw records remain under `build/tests/pvm-census/`; this increment's evidence
is under `build/pvm11/census/`. The unchanged benchmark fixture is
`3d7ac5bd063d1ef09d29e4c3d701ee983e0a23a94213c4d750561cd9d3a2559b`.

Next, extend this diagnostic to the maintained indirect-call, memory-fill and sieve guests and
combine their counts with fresh profiles. Any later specialization/fusion must preserve every
observable attempt, gas charge, host/fault transition and causing PC. No fusion, JIT, computed-goto
backend or prepared IR is introduced here. Local macOS counts do not establish Linux performance
or whole-JAM/STF parity. M1 framing remains complete in scope; full state serialization remains
open. Fuzzing remains paused pending Daybreak access.
