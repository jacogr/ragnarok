# Chunk-oriented host byte-range transfers

`readBytes` and `writeBytes` retain natural nonwrapping host addresses, caller copy limits,
complete permission preflight, first physical fault precedence and independent immutable results.
They now copy raw bytes in at-most512-byte batches within individual owned chunks. Reads copy into
fresh result storage. Writes first clone the touched page and every touched chunk, then copy from
borrowed input into those private allocations. Neither direction exports a byte pointer, retains
caller input or crosses an allocation boundary in one copy. Raw byte transfers have no endian
conversion. Empty ranges retain their original owner/pointer behavior, including ignored high pointers.

Contiguous range traversal performs one binary search and then advances through sorted page slots.
Preflight compares every required physical index and permission, so a missing sparse page still
fails before any copying. Payload traversal uses the same immutable validated owner and its proven
consecutive slots. This changes successful range lookup from repeated logarithmic searches to a
single logarithmic search plus a linear page walk. Complete validation still precedes allocation
and every write; no failed result exposes a copied prefix.

The native host-memory matrix covers unaligned/chunk/page boundaries, sizes0/1/2/511/512/513/
1023/1024/1025/4095/4096/4097/8192, caller limits, permissions, empty/high addresses and1,000 ARC
release cycles. Public `pageImage` checks every written page independently of optimized `readBytes`,
including all untouched neighbors. A missing middle page in an otherwise sorted sparse vector
must fault for read/write and permission-only queries without confusing a later stored page with
its physical predecessor. The actual suite passes AddressSanitizer with verified dynamic linkage.
Fetch, inner transfer/invoke, refinement export and host execution suites protect direct consumers.

## Supporting bounded benchmark

`make bench-pvm-memory` measures native host APIs, not guest execution or interpreter backend
performance. Each sample retains128 independent results for512/4096/65536-byte unaligned reads
and writes. Three warmups precede ten measured samples per case; two fresh processes reverse case
order. CPU and monotonic wall clocks surround calls only. Input creation, complete independent
result/source validation and result retirement remain outside timing. Release assertions must
fail the exact sentinel before positive measurements run. Strict parsing rejects missing,
duplicate, reordered, foreign, nonpositive and overflowing durations. All samples and warmups
remain available; dispersion flags discard nothing. Short initial16-call batches encountered CPU
clock quantization and were rejected; the maintained128-call plan preserves positive-duration checks.

`build/tests/pvm-memory/` retains JSON, CSV, Markdown and build/control/run logs with source/binary
identities, exact commands/profile, pinned compiler, CPU/OS/load and explicit build flags. Failed
reruns replace the verdict and remove stale successful samples. Normal CI does not select this
opt-in workload. Supporting Python tests cover parsing, process coverage, warmups/noise and failed
rerun artifacts. Full Python discovery runs once for this tooling epoch; Smoke verifies production.

On Apple M1 Max, a matched checked parent/final128-call comparison measured65536-byte reads at
7.060→0.342 ms/batch and writes at7.314→0.632 ms/batch (about95% and91% lower process CPU).
At4096 bytes the observations were0.453→0.029 and0.471→0.047 ms. These are bounded native API
observations, not a real-sieve or whole-client speedup claim, exact-head Linux CI or PolkaVM ratio.
No specification, toolchain/dependency pin, gas, ARC or checking policy changes. M1 framing remains
complete in its scoped contract; complete state serialization and whole-block/JAM parity remain
open. Fuzzing remains deferred pending Daybreak access.
