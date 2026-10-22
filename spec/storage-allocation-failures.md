# Storage allocation aborts and early extent refusal

## Scope and evidence

Continue from merged memory-ceiling stack tip
`ebd27f7bbca34cf0eca62caf2fe2b0d8b790e59f`, on current trunk
`b81269bfc9169736286846e5ec4cdc2a67415a1b`.
The Linux Perf Storage run39778196839 validated all three limit probes, ten constrained native
reopens and all eight unrestricted controls. Journal and managed131,072-entry opens under128 MiB
terminated with SIGABRT, with no native diagnostic. Selected bytes remained unchanged.
A signal alone does not identify its exact allocating call or establish an OOM-killer event.

The pinned native allocator's `lib/std/system/memory.nim` defines `raiseOutOfMem` as a direct
non-returning `cAbort`; Linux/Darwin OS page mapping refusal calls it. `alloc.nim` also routes
an exceeded public `nimMaxHeap` hard test cap to that same function. These sources are read-only
under toolchain pin `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`.
A checked ARC/Clang release/LTO two-MiB allocation succeeds unrestricted and aborts with SIGABRT
under `-d:nimMaxHeap=1`, even inside a raising procedure called from `try/except`. Its flushed
start marker survives; neither its completion nor catch marker appears. This is a deterministic
allocator-path witness, not an exact reproduction of Linux RLIMIT_AS or its unknown allocating
call site. Logs, commands and compiler output remain in ignored `build/storage-db5-probe/`.

The existing [trie contract](full-state-trie.md) and storage module guide require allocation
exhaustion to remain fail-stop. General OS allocation exhaustion cannot be turned into a storage
result by adding an exception handler. Recoverable artificial allocator refusal is a distinct
configuration and does not make the OS page-mapping path recoverable. No compiler/stdlib patch,
private runtime hook, allocator change or production cap is authorized or introduced here.

## Bounded implementation

For journal and managed file readers, inspect the already-open regular descriptor's current
extent before accumulating detached bytes. A negative extent or failed stat is IoFailure;
an extent beyond the caller's narrowed byte ceiling is LimitExceeded. This avoids allocating
a known oversized buffer merely to discover that the configured limit must reject it.
Metadata never authorizes successful admission, buffer preallocation, truncation or replacement.
The existing bounded read loop still verifies actual progress, exact ceilings and one excess
byte, so post-check growth remains a refusal. Full identity/frame/root validation still decides
successful reopen, and all refused opens retire descriptors and leases.

This does not predict total heap/RSS/virtual headroom, prevent allocation failure for files that
fit their declared byte limit, or fix the original128 MiB in-limit graph reconstruction aborts.
The safe remedy is earlier refusal for a caller-selected smaller file ceiling, not a promise of
recovering from arbitrary memory exhaustion. Backend defaults, bytes, roots, trust policy and
state/PVM/consumer ownership remain unchanged.

## Completion checks

Demonstrate a pre-fix abort and post-fix typed refusal for an exclusive sparse regular fixture
whose configured read ceiling exceeds a deterministic one-MiB test heap. Cover managed snapshot,
manifest and journal reads plus journal owner open, exact/empty positive reads, descriptor reuse,
unchanged extent/prefix and subsequent valid reopen. Run existing boundary, short/interrupted
read, I/O and recovery consumers plus relevant inventory/format checks. Keep full native checks
in the standard Make/Hastur path; the heap cap belongs only to per-suite test profiles.

No new M1 completion claim is introduced; complete protocol serialization remains separate.
Controlled resident-memory/paging experiments require a suitable Linux execution environment;
the local Docker daemon is unavailable. Hardware/filesystem power-loss work remains separate.

## Managed reader witness

The new `storage_managed_read_preflight` native suite runs under the explicit one-MiB hard
heap test profile. Before the managed-reader change it compiled and reached its flushed
`managed preflight: Snapshot` marker, then terminated with exit134 (SIGABRT) while trying to
buffer a sparse16 MiB file under a configured4 MiB read ceiling. The original failed fixture
is preserved in `build/storage-db5-managed-before-fixture/`; the Make log is
`build/storage-db5-managed-before.log`. Compiler-error iterations are not runtime evidence.
The native requirement allowlist admits only the fixed `nimMaxHeap=1` test define; production
and other suite profiles retain their existing settings. Arbitrary heap values, recoverable OOM
and unchecked defines remain refused by harness tests.
