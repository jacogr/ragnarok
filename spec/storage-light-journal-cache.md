# Durable light proof-cache journals

`LightJournalCache` is a standalone explicit disk backend for immutable light proof evidence.
It uses a separate selected directory and the distinct
[light journal manifest/anchor schema](storage-light-journal-selection.md). Independently
selected chain/root and exact proof/image/journal policies come from `LightJournalConfig`,
never from disk. This work changes no application startup, StateStore, checkpoint worker,
consensus root selection or full-state interface.

## Lifecycle and synchronized selection

Initialization accepts only an authenticated prepared light image with exactly matching
chain/root and every inherited snapshot/cache/write/proof ceiling. It exclusively creates
the private directory and stable regular `LOCK`, writes and synchronizes checkpoint epoch
one, writes and synchronizes its empty anchored journal, and opens the exact append inode.
Only then does synchronized atomic `CURRENT` replacement select that epoch. All failure
paths close append before directory and expose no owner. Forensic children remain for
inspection. A failed post-rename directory barrier reports `PublishedUnsynced`; it grants
no receipt and requires strict reopen to determine the selected bytes.

Opening holds the directory lease and selected append inode while it validates the exact
manifest, bounded checkpoint proofs and checksum, anchor, and entire bounded frame stream.
No old-image/full-state schema fallback or older epoch search exists. No corrupt or partial
suffix is automatically discarded. Refused opens retire both resources and preserve file
bytes. Existing regular file/extent/no-follow checks and bounded reads come from managed I/O.

A live owner has one retirement authority. Copying is unavailable, including hidden ARC
lowering copies. `close` always attempts append and then directory retirement, returns the
first refusal and disarms the owner even after a close error. Default and moved-from owners
are inert. Destruction of a live unclosed owner is a contract violation. Immutable readers
retain proof-image ownership, never the directory lease or native descriptor.

## Sparse atomic updates

`append` accepts an opaque authenticated light frame. It checks exact inherited successor
policy and chain/root, current image checksum and next local sequence, configured frame
bytes/edit count, remaining frame count and managed total journal capacity before writing.
Sequence increments are checked before arithmetic. Opaque authority already authenticates
canonical edits, proofs and successor; no repeated proof or checksum hashing is necessary
for this binding. A stale frame cannot append even at an equal complete state root.

`update(proofs, forgotten)` privately prepares one bounded atomic proof transition, then
uses the same append path. No eviction or admission prefix is published. Policy/provider/
proof refusals before I/O preserve current authority. Frame-count, frame-width and total
capacity refusals do not poison an owner and permit another admissible operation.

The selected checkpoint, anchor namespace and `CURRENT` are already synchronized by bootstrap
or strict open. An append writes only the complete frame and synchronizes that held journal
inode. Only a successful barrier publishes its immutable successor and sequence, returning
`FileAndDirectorySynced` for the anchored namespace. Successful appends do not rewrite the
checkpoint or `CURRENT`, rename files or synchronize an unchanged directory entry.
Receipts describe successful system-call barriers; they make no physical-device or power-loss
claim and convey no consensus/root authority.

Any uncertain write or failed append barrier poisons the owner. Every fresh snapshot,
prepared-image, sequence, epoch, byte-length, update and append operation then returns
`RecoveryRequired`. Retained old readers remain valid, but are never presented as a fresh
successful observation. The caller must explicitly close and reopen. A complete frame may
be confirmed on strict reopen after a failed barrier; a partial frame refuses strict open.
Explicit partial-tail inspection/repair and compaction are subsequent features.

## Scoped verification and remaining work

The checked native suite derives a complete two-key root independently with flat-map hashing,
then prepares only partial present evidence and swaps it for authenticated absence. It checks
exclusive lock contention, exact inherited policies, stale/default transitions, no-I/O
admission failures, independent frame/count/total quotas, retained readers and strict reopen.
Observed ordinary append is one write and one file sync with zero renames and zero provider
calls for an already prepared opaque frame. Exact `CURRENT` and checkpoint bytes stay equal.

Real observer faults cover write refusal, a genuine 64-byte partial prefix followed by refusal,
zero progress and a complete append whose sync fails. They verify poison gates, exact forensic
bytes, old readers and strict old/complete/new or partial-tail refusal. Bootstrap tests distinguish
pre-checkpoint refusal from the final post-rename uncertain barrier. Close refusal still disarms
the owner and releases the lease. Scoped reopen/retirement cycles return ARC occupancy to baseline.

Runtime default/failed result and unclosed-owner guard probes have positive controls. Strict
private-field and actual native copy-rejection checks cover composite authority. Format and
inventory checks accompany this unit. Evidence is local checked release on macOS arm64 with
the pinned compiler/providers, distinct from exact-head Linux CI and process-crash qualification.

Next work is explicit validated partial-tail repair under a held lease, grouped real-process
append/bootstrap crash qualification, checkpoint compaction and guarded reclamation. There is
no automatic repair, pruning, startup selection or full-state integration. Historical M1 framing
completion remains distinct from complete state serialization.
