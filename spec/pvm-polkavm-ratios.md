# PolkaVM native/interpreted calibration

The maintainer requested an explicit Linux x86-64 comparison of the pinned
PolkaVM Compiler and Interpreter backends for every existing PVM workload.
`make bench-pvm-polkavm` provisions the pinned reference crates and runs this
comparison. The dispatch-only `.github/workflows/polkavm-ratios.yml` workflow
uses one x86 runner; ordinary CI has no calibration job. The existing deferred
compiler benchmark policy keeps its scope.
The disposable Ubuntu runner enables unprivileged user namespaces required by
the pinned Linux sandbox (`kernel.apparmor_restrict_unprivileged_userns=0`)
and its dynamic paging profiles (`vm.unprivileged_userfaultfd=1`). A complete
native synthetic control exercises every required compiler profile before
the application timing cohort.
A successful one-call execution in each backend checks full guest state,
compiled-code identity and CPU accounting before the corrupted-state controls.

The matrix contains the eleven synthetic cases, Sieve at 1K/10K/100K/10M,
Minimal and Memset at 1K/100K, one Pinky frame, and separate DOOM init/tick.
Both engines consume identical bytecode and interpreted preparations, with
JamV1, Sync gas, Full/L2Hit pricing and 4KiB pages. Every execution checks its
complete existing CPU, gas, mapped-memory and host-output expectations before
publishing measurements. Compiler selection is explicit and compiled code
must be present. No fallback measurement can fill a compiler cell.

PolkaVM's default Linux compiler sandbox runs in another process. The timer
uses the public `RawInstance::pid()` and Linux perf task-clock counters for
both parent and worker. Each process must have exactly one thread; a real
two-thread control must be refused. The pinned worker's seccomp policy denies
thread creation. Counter availability or thread-count failure stops the run.
The disposable runner permits these software events with
`kernel.perf_event_paranoid=-1`; no samples are replaced or retried.

Per-call CPU is parent task CPU plus worker task CPU; both components and wall
time remain in raw records. A real busy-child control compares remote task CPU
against the child's own CPU report, catching parent-only, duplicated or
uncalibrated accounting. Worker counters are read outside the parent's CPU
interval. Instance creation, counter setup, input restoration, verification
and teardown remain outside call execution. Complete guest validation runs
before the positive-worker-CPU verdict, so a zero cannot hide a guest failure.
Module creation/compilation parent process CPU is retained separately; the
synthetic preparation also includes Engine construction. First-call data is
preserved.

Remote POSIX process-group clocks can omit still-running task time until a
scheduler update; they cannot safely time short sandbox calls. The
[Linux accounting source](https://github.com/torvalds/linux/blob/master/kernel/sched/cputime.c)
documents that limitation. An independent local Linux control observed 967 of
1,000 intervals with stale group time while perf task CPU grew; its perf total
32,519,542 ns agreed with self-reported thread CPU 32,510,917 ns. This is an
OS-clock control, not a guest performance result.

Six process pairs alternate backend order. Each process retains all thirteen
validated calls, with the first three designated warmup. The primary ratio is
the median of per-pair warm CPU-median ratios, Compiler / Interpreter. JSON
also retains the ratio of process medians, every paired ratio, source/input/
binary hashes, hardware identity and cold preparation. Raw CSV separates parent
and worker CPU. A changed expected-state control must fail in both engines
before emitting execution samples.

The proposed portable estimate is:

`estimated ARM ours / PolkaVM native = (ARM ours / PolkaVM interpreted) /
(x86 PolkaVM native / PolkaVM interpreted)`.

This assumes the per-workload reference ratio transfers across architectures;
it is an estimate, not an ARM native measurement. Native/interpreted factors
are kept per workload. Latency, total CPU and throughput remain separate when
considering process workers or parallel independent invocations.

The Linux job qualifies compiler execution and both counters before accepting
ratios. The focused parser rejects missing worker CPU, substituted engines,
absent compiled code, changed total CPU, missing or duplicate samples,
duplicate backend observations and incomplete pairs. Both crates compile on
macOS and Linux with pinned Rust. Local Linux checks exercise real calibrated
child CPU, multi-thread refusal and the explicit/default interpreted protocols.
Invalid platform or pair-count arguments replace any previous successful JSON
verdict with a failed verdict before exiting.
