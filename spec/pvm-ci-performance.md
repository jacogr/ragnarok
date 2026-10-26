# PVM CI performance monitoring

## Scope and scheduling

Regular CI retains **Perf / PVM** and adds **Perf / PVM DOOM** as independent members of the existing
Perf matrix. Both run on every master push, manual `perf`/`full` requests and open-PR label
additions `ci:perf`/`ci:full`. Ordinary PR updates request Smoke only. Standalone `bench-pvm`
and `bench-doom` scopes select one workload, without claiming the whole Perf group. The existing
Perf aggregate requires every selected family; storage performance families are unchanged.

Retired CI jobs: PVM Instructions, PVM Prepared, PVM Revisions, DOOM Attribution and DOOM Revisions.
The instruction job reported current counts without a revision baseline; prepared measurements
still selected an old experiment parent. The revision/attribution jobs were explicit investigation
lanes rather than ongoing monitoring. Their dispatch options, diagnostic input fields and
`ci:pvm-compare` event handling are removed. Existing Make tools and their tests remain available
under their current platform/timing restrictions; historical numerical evidence is preserved.

## DOOM workload and correctness

`make bench-pvm-doom` uses the existing pinned headless DOOM ELF, WAD, interpreter-only Rust
reference and checked Nimony host adapter. Pins, guest behavior, gas policy and callback behavior
are unchanged. The warmup is fixed at 1,320 ticks, admitting the matching upstream normalized
rendered-frame golden. Initialization and one gameplay tick are distinct input states.

Before clocks, both engines pass complete CPU/memory/output checks and assertion, wrong-gas and
wrong-event controls. Every timed invocation checks all registers, gas/PC/paid state, mapped page
bytes/permissions, original source bytes and ordered host output. Thirteen ordered validated
samples are mandatory; the first three warm up and the last ten supply reused CPU medians.
Both process orders run sequentially after builds. Source, fixture and image hashes must still
match after collection. Failed/partial runs cannot retain an old successful summary.

`--timings-only` skips optional Callgrind collection/calibration and source annotation, without
skipping preparation, the golden, refusal controls or reference-state checking. Other existing
check/profile modes remain available; contradictory mode flags are refused. Timings still require
the isolated Linux x86-64 CI runner. Regular DOOM setup needs zstd, not Valgrind.

## Reports and limits

Actions summaries show initialization/gameplay CPU milliseconds for both interpreters and
Ragnarök/reference ratios in each process order. JSON retains all samples, cold first calls,
source/input/compiler build evidence and exact reference identities. Raw logs, JSON and the
summary are retained for 30 days; generated fixture memory and compiler caches are excluded.

Call CPU includes in-memory host callbacks. Preparation, input reset, file I/O and final reference
validation are outside the clock; this is not full application startup time. No native/JIT backend
is selected. Timing ratios are informational, with no universal or cross-runner regression threshold;
semantic, identity or sample failures fail CI. There is no claim of a revision instruction baseline.

## Completion evidence

Workflow safeguards cover master, full/Perf, standalone, PR-update and closed-PR scheduling,
retired experiment absence and aggregate coverage. A complete inert-tool orchestration test
exercises CPU-only preparation, all six refusal controls, eight timing processes and source identity
checks while refusing profiler calls. Summary tests reject partial phases/orders, invalid durations
and forged ratios. Existing reference event/golden/parser tests remain authoritative.

Local tooling tests and workflow lint are recorded in the PR. Actual Linux performance evidence
will come from the new job; local macOS tests do not claim an executed Linux benchmark.
