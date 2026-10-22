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

## Journal reader witness

The new `storage_journal_read_preflight` suite constructs a valid tiny journal and holds its
immutable view, then adds an exclusive sparse tail to16 MiB without a large memory buffer.
Under its configured4 MiB file ceiling and one-MiB test heap, the unmodified journal reader
compiled and aborted after the `journal preflight` marker (exit134). The preserved log and
fixture are `build/storage-db5-journal-before.log` and
`build/storage-db5-journal-before-fixture`. After early extent refusal, the same fixture must
return LimitExceeded, retain its full extent and valid prefix, release the failed open's lock,
and strictly reopen after the test alone removes its deliberately authored tail. Exact original
root/generation and the independently retained view remain required.
The existing short-read suite now requires zero payload read calls for a known oversized
journal; managed CURRENT still precedes snapshot refusal. Post-stat growth needs a separate
real-IO witness so metadata cannot bypass the existing excess-byte guard.

## Post-stat growth witness

The test-only SDK observer can borrow one caller-owned writable regular descriptor and grow its
exact inode once, immediately before the next real read, after the storage reader's stat.
Configuration rejects invalid/read-only descriptors, shrinking or greater-than64 KiB extents,
and replacement of an active cue. Execution rechecks device/inode and current extent before
real ftruncate; failure supplies no positive read result. Reset forgets the borrowed descriptor
without closing it. No production call path, native runtime or allocator uses this cue.
`storage_read_growth` exercises actual growth and real eight-byte short reads for managed
snapshot/CURRENT/journal reads, managed append open and ordinary journal owner open. Each starts
below its read ceiling and then exceeds it by one byte; pending-cue consumption and actual read
calls must prove the path executed. Refusal preserves the test-authored grown extent/prefix.
The tests alone remove their deliberate tails before positive strict reopens.

## Final local qualification

Frozen implementation `2fb095c06c7a645334fc5721a153e1699d5b7f5e` passed all 12 selected native
suites through Make: both one-MiB preflight regressions, real post-stat growth, original chunk
bounds, short reads, interrupted reads, file admission, journal owner semantics, managed owner
semantics, managed publication IO, managed disk recovery and repair interruptions.
The native/profile Python guards passed 88 and 6 tests respectively. Inventory and pinned format
checks passed. The SDK observer compiled with its normal strict C warnings; no compiler/stdlib
source or pin changed. Native unit profiles retain their established checked ARC/Clang release
configuration; the separate tiny allocator probe also used the checked LTO profile.

A fresh Make memory-ceiling panel passed all eight ordinary large-state native reopens with
exact complete maps, producer roots/generation, retained lifetimes, allocator release and selected
byte preservation. Its three probes and twelve constrained rows remain unavailable on this
Darwin host; the earlier successful Linux run is evidence for its original merged source, not
exact-head Linux evidence for this change. No new remote CI label was requested.

The final qualification edit changes only feature/operator prose. Full logs and exact input
identities remain in `build/storage-db5-final-qualification.json`,
`build/storage-db5-final-logs/`, `build/storage-db5-final-memory-ceilings/` and the pre-fix fixture
paths above. Initial fixture/compiler corrections are not counted as runtime controls.
The bounded storage fix is complete; the exact original Linux allocating call site, general
OS-OOM recovery, controlled resident-memory/paging and hardware/filesystem power-loss work
remain outside this qualification. No complete-serialization or M1 completion claim is added.

## Linux call-site qualification follow-up

The maintainer requested Linux diagnosis before merging the current stack. The added
`make diagnose-storage-aborts` target first runs the unchanged checked ARC/Clang LTO
memory-ceiling panel. Every Linux cap probe must establish enforcement. It then builds the
same fresh-reopen source with C debug information (`-g`) as a separate comparison binary.
LLDB remains uncapped and follows the existing disposable limit launcher's exec into each
131,072-entry native consumer under128 MiB. The launcher must read back the applied soft
limit with the original hard bound. An actual SIGABRT stop, bounded native backtrace containing `abort`
and fatal signal continuation are all required; debugger exit zero is insufficient.

Separate strict unrestricted symbolized consumers bracket each backend's abort attempt,
checking complete maps, exact producer root/generation, retained views and final ARC release.
Selected bytes must remain identical after every attempt. The ordinary panel retains its own
binary identity, limit receipts and observed exits. Debug information can affect layout;
these symbolized comparisons do not retroactively identify an old binary's exact instruction.
A backtrace still requires source inspection before calling a particular abort allocator OOM.
No compiler/stdlib patch, allocator hook or production build change is introduced.

The explicit `storage-diagnostics` workflow-dispatch scope runs the three current reader
regression suites on Linux, then this diagnostic. Make's existing bounded `host-tools` path
installs LLDB only for the diagnostic target. Raw logs, binary identities, comparison binaries
and failed/partial JSON remain in `build/tests/storage-abort-diagnostics/` and CI artifacts.
Darwin and missing debugger support fail explicitly, rather than becoming skipped successes.
Actual exact-source Linux results and allocating callers will be recorded after that run.
