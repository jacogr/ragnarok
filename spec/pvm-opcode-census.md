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

The real-guest extension below now supplies maintained indirect-call, memory-fill, sieve and Pinky
counts. Combine these counts with fresh profiles. Any later specialization/fusion must preserve every
observable attempt, gas charge, host/fault transition and causing PC. No fusion, JIT, computed-goto
backend or prepared IR is introduced here. Local macOS counts do not establish Linux performance
or whole-JAM/STF parity. M1 framing remains complete in scope; full state serialization remains
open. Fuzzing remains paused pending Daybreak access.

## Maintained real-guest census

Run `make census-pvm-guests` for seven bounded inputs: sieve, minimal/indirect calls and memory
fill at1,000 and100,000, plus one initialized Pinky frame. The ten-million-element sieve timing
case remains outside this diagnostic pack. Make provisions existing pinned tools and reference
dependencies. The reference uses its existing interpreted preparation entry point; no guest
compiler, compiled execution backend or prepared representation is added.

The ignored snapshot includes the unchanged maintained guest driver and its clock header. Its
existing independent result and full reference CPU/gas/page/permission/source comparisons remain
mandatory. Each input executes twice in fresh processes under each of the three pricing modes:
42 completed invocations. All six counts per input must agree. These are fresh memo processes,
not measurements of warm memo performance. The shared strict driver parser accepts an explicitly
requested single diagnostic sample; normal benchmark callers still require thirteen samples and
their complete policy preparation/occupancy framing. Instrumented sample and preparation timings
are validated for framing, then discarded from the aggregate census.

The synthetic default remains512 exact pair entries; real-guest snapshots select4,096. Both
capacities use the same calibration witnesses: compiled ordinary-control refusal, nested/fresh
and host-terminal positive controls, and exact capacity-exhaustion refusal with no completed
record. The real guest binary also must prove its native assertions are active before running.
The parser enforces the selected capacity and complete connected-walk conservation. Native
overflow remains a failure rather than a truncated result.

Observed checked M1 Max/macOS results after the previous fifteen optimizations/qualification
layers merged at`32d1e9c4`:

| Input | PVM instructions per invocation | Distinct adjacent pairs |
| --- | ---: | ---: |
| Sieve1,000 | 13,091 | 383 |
| Sieve100,000 | 1,166,742 | 446 |
| Minimal1,000 | 20,034 | 48 |
| Minimal100,000 | 2,000,035 | 48 |
| Memory fill1,000 | 12,335 | 222 |
| Memory fill100,000 | 1,200,349 | 231 |
| Pinky frame | 32,055,270 | 761 |

Pinky therefore exceeds the old synthetic capacity. Its most frequent opcode is149
(3,152,504 evaluations), followed by151 (2,424,254); its most frequent pair81→2 occurs809,552
times. Memory fill repeatedly traverses120→149→171, while sieve frequently traverses132→81.
These virtual frequencies identify profiling candidates; they do not attribute native CPU cost
or establish that pair fusion would improve performance.

Reports, raw logs, source/snapshot/fixture/binary identities and all build/process commands remain
under`build/tests/pvm-guest-census/`. Generated reference inputs are bound to their actual bytes;
all original inputs, generated snapshot sources and binaries are rehashed before aggregate
publication. A new invocation removes earlier aggregate success before preflight. A failed
build, wrong guest/policy/size, missing invocation, inconsistent counts or concurrent identity
change prevents publication. This diagnostic adds no automatic CI workload. Remaining work is
fresh uninstrumented profiling and paired optimization experiments on these maintained guests.
