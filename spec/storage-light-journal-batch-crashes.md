# Grouped light journal append process crashes

## Scope and contract

This qualification extends [prepared journal batches](storage-light-journal-batches.md) to real
process interruption. It preserves the existing V1 image, manifest, anchor and delta formats,
independent expected chain/root, inherited budgets, full/light separation and standalone storage
boundary. Compiler, provider and allocator pins are unchanged. This is process-death evidence;
it does not establish hardware power-loss or physical-device persistence behavior.

```sh
make setup
make unit SUITE=storage_light_journal_batch_crashes
```

Every scenario creates its own directory. One workload begins at the checkpoint's empty journal;
the other begins after two genuinely committed frames. Independent ordinary transition
preparation supplies the expected first/second grouped frames at sequences 1/2 or 3/4, their
successor images, and a following ordinary frame. Batch preparation finishes before fork and
contains no native lease. The child strictly reopens, arms the maintained exact-child observer,
then performs the real prepared grouped append.

## Completed controls and killed boundaries

Each baseline independently completes controls for the ordinary full write and final file sync,
64-byte short writes and their final sync, and first-frame-sized short writes and their final
sync. These are successful end-to-end operations with explicit normal-completion receipts.

A fresh child is stopped after every successful write and each final synchronization in those
patterns. Before killing it, the parent must witness the matching stopped-child receipt and
actually receive Busy when contending for the directory's LOCK. Only the observer's exact
SIGKILL/reap receipt and expected operation count satisfy a killed case. Normal completion,
missing stops, child failure, timeout or a different PID cannot satisfy it.

The first-frame-sized writes deliberately stop exactly between group frames. They establish
that an entirely complete observed prefix strictly reopens even though the original two-frame
append did not finish. The 64-byte pattern also leaves incomplete suffixes before and after a
complete first frame. Each selected boundary gets its own namespace and exact authored byte
prefix; later zero padding or a fabricated completed frame is never accepted.

## Recovery and retry witnesses

Before reopening, the parent checks exact journal extent/content, unchanged CURRENT and
checkpoint, and absence of a staging manifest. Strict reopen must preserve every forensic byte
and perform no write, rename or unlink. A nonempty incomplete suffix refuses strict open and
requires fresh held-inode inspection and synchronized repair. The repair plan must retain the
exact original frames plus each completely authenticated grouped frame, including its image,
global sequence and byte extent; only the incomplete suffix may disappear.

An original batch can retry after repair only when its exact original predecessor remains.
Once any grouped frame is retained, that batch must refuse as stale without writes or syncs.
If exactly one frame is complete, a new one-edit batch prepares only the remaining update.
Every path then checks the exact final two-frame concatenation, appends an independently
prepared ordinary following frame, closes and strictly reopens the resulting exact image.
Retained original readers and unknown sibling content survive throughout.

## Scoped result

On October 24, 2026, the checked ARC/Clang LTO macOS arm64 build with Nimony
`4724f66c2e01b17810c844f26575b2317995fda2` passed 12 completed controls and 42 exact
killed boundaries. The two baselines contribute 28 total 64-byte write boundaries and six
first-frame-aligned write boundaries; full writes and all final-sync patterns contribute the
other eight kills. Numeric receipts are recorded by the supported native runner as
`storage_light_journal_batch_crashes.json` under its ignored evidence directory. The native
assertions and actual child receipts supply the verdict, not the counters alone.

This closes real-process grouped-append qualification. Existing ordinary append/bootstrap and
replacement/cleanup process-crash contracts remain separately scoped. Exact-head Linux CI and
hardware power-loss behavior remain separate evidence.
