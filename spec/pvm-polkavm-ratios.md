# PolkaVM native/interpreted calibration

The maintainer requested an explicit Linux x86-64 comparison of the pinned
PolkaVM Compiler and Interpreter backends for every existing PVM workload.
`make bench-pvm-polkavm` provisions the pinned reference crates and runs this
comparison. The manual `polkavm-ratios` CI scope uses one x86 runner; ordinary
CI and the existing deferred compiler benchmark policy keep their scope.

The matrix contains the eleven synthetic cases, Sieve at 1K/10K/100K/10M,
Minimal and Memset at 1K/100K, one Pinky frame, and separate DOOM init/tick.
Both engines consume identical bytecode and interpreted preparations, with
JamV1, Sync gas, Full/L2Hit pricing and 4KiB pages. Every execution checks its
complete existing CPU, gas, mapped-memory and host-output expectations before
publishing measurements. Compiler selection is explicit and compiled code
must be present. No fallback measurement can fill a compiler cell.

PolkaVM's default Linux compiler sandbox runs in another process. The timer
uses the public `RawInstance::pid()` and a Linux process CPU clock for that
worker. Per-call CPU is parent CPU plus worker CPU; both components and wall
time remain in raw records. A real busy-child control requires substantial
worker CPU while its parent waits, detecting the parent-only clock mistake.
Worker clocks are sampled outside the parent's CPU interval. Instance creation,
input restoration, verification and teardown remain outside call execution.
Module creation/compilation parent CPU is retained separately; the synthetic
preparation also includes Engine construction. First-call data is preserved.

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

Linux measurements are pending. The focused parser rejects missing worker
CPU, substituted engines, absent compiled code, changed total CPU, missing or
duplicate samples and incomplete backend pairs. Both reference crates compile
locally with pinned Rust; the Linux worker clock is qualified by the manual
job before native timing.
