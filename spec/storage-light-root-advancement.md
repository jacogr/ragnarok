# Storage-only light-root advancement

Status: contract-first design for standalone storage. The APIs below are planned; the existing
journal owner still binds one root until the implementation and its completion checks land.
This contract does not authorize StateStore, PVM, startup, networking or consensus integration.

## Authority and meaning

The existing proof/trust contract and pinned Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` state Merklization rules remain authoritative.
See [light proofs](storage-light-state-proofs.md), [immutable caches](storage-light-cache.md),
[canonical snapshots](storage-light-snapshots.md) and
[journal selection](storage-light-journal-selection.md). Compiler/provider/allocator pins stay
unchanged. No JAM encoding, hash domain or local V1 format changes are needed.

A caller independently accepts a destination complete-state root. Storage verifies evidence
against that root but cannot establish the root's provenance, finality, block height or ordering.
The destination root is an explicit argument, separate from the candidate image and disk bytes.
It must differ from the currently selected root; an equal-root request returns InvalidBatch.
Returning to an earlier root is permitted only through a fresh caller-selected request and a new
physical epoch. This mechanism does not itself authorize or interpret a chain reorganization.
Chain identity stays unchanged; changing chains requires a separate database.

## Destination evidence

Use existing `prepareLightSnapshot(chain, destinationRoot, proofs, limits)` to authenticate a
replacement knowledge set. All supplied proofs are checked at the destination root. No Present,
Absent or present-empty entry is inherited implicitly from the source cache, even when its key
or value appears unchanged. Omitted keys become UnknownKey. Empty destination evidence is valid
and leaves every key unknown, including when the destination is the empty complete-state root.

The replacement inherits every source snapshot/cache/proof limit exactly. Its complete evidence
count is governed by snapshot item/value/byte limits, independently of future per-update write
limits. Read-only snapshots with zero mutation allowance may therefore receive a separately
verified full replacement. This is maintenance publication, not a bypass for ordinary updates.
Caller proof buffers remain stable during preparation; opaque prepared images own immutable
bytes/lookups independently of subsequent caller mutation.

Retained source snapshots and lookup/proof/page readers remain bound to their original root and
remain valid after advancement, failure, native close or later advancements. Storage never
retags an old reader. Retained handles supply no claim that their root is still selected.

## Planned durable API and ownership

The owner remains `LightJournalCache`. Planned public operations are:

```nim
prepareLightRootAdvance(owner, expectedEpoch, expectedSequence,
                       destinationRoot, image): LightJournalResult[PreparedLightRootAdvance]
advanceRoot(owner, prepared): LightJournalResult[LightRootAdvanceReceipt]
discardUnselectedRootAdvance(owner, prepared): FileError
```

`expectedEpoch: ManagedEpoch` and `expectedSequence: LightDeltaSequence` name the caller's
confirmed source position. `destinationRoot: StateRoot` is the independent trust input;
`image: PreparedLightSnapshot` must match it and the owner's chain/exact snapshot policy.
Preparation requires a live confirmed source, checks stale position and epoch exhaustion before
metadata hashing, then prepares the destination manifest and empty anchor without file IO.

`PreparedLightRootAdvance` is an opaque immutable handle. It owns only the verified destination
image, manifest/anchor bytes and exact source/destination metadata. It binds source root,
manifest checksum, image checksum, epoch, update sequence, frame count, append extent and all
snapshot/journal policies. It carries no directory/append lease and can outlive the owner.
Default plans grant no authority. Read-only initialized/epoch/sequence/root/snapshot accessors
must guard payload access; mutable backing and tagged-result fields remain private.

Publication requires the exact source position and policies captured by the plan. Any ordinary
append, compaction or intervening root selection makes it stale, including a later return to an
equal root/image. A close/reopen at the same exact source may reuse the plan only with identical
policies. Previously prepared frames, batches, compactions and root plans cannot publish against
a different selected root/epoch; refusal must precede writes. Passive receipt objects are never
accepted as publication or root-trust authority.

## Physical epoch and update sequence

Advancement checks and increments the positive physical epoch exactly once. It preserves the
global proof-update sequence, writes a checkpoint at that sequence, and selects an empty anchored
journal with zero post-checkpoint frames. The update counter numbers ordinary proof updates,
not root selections. The next ordinary update, when sequence capacity permits, is sequence+1
at the destination root and exact new checkpoint image. Advancement may preserve a maximum
update sequence; future appends must then refuse. Maximum epoch refuses without wrapping.

The unchanged V1 manifest already binds root, epoch, baseline sequence and checkpoint checksum.
Destination checkpoint and anchor are synchronized before atomic CURRENT replacement. The old
checkpoint/journal remain until explicit guarded reclamation. Only confirmed manifest-directory
synchronization permits publication of destination root/configuration/image and append owner.
Prepared publication performs no repeated target proof/image/frame hashing.

## Refusal and uncertainty

Recoverable failures use the existing typed storage result/error domain. Uninitialized and
poisoned owners refuse. Wrong destination chain/root returns WrongIdentity; mismatched limits or
an equal destination root returns InvalidBatch; changed source position returns StaleView.
EpochExhausted and LimitExceeded preserve arithmetic/resource refusal. Provider failure remains
BackendFailure. Pure refusals preserve the confirmed source and every caller-held reader.

Existing candidate names return AlreadyExists without replacing them. Staging/write/read/barrier
uncertainty preserves the original IO cause and poisons fresh owner observations until explicit
close/reopen. A post-rename failed directory barrier remains PublishedUnsynced and returns no
confirmed advancement receipt. No error becomes implicit rollback, root selection or salvage.

A successful `LightRootAdvanceReceipt` contains previous/destination roots, previous/new epochs,
unchanged sequence and a separate native-retirement reason. If selection is confirmed but old
append-handle retirement fails, the successful receipt still reports the selected destination;
the owner is poisoned until explicit close/reopen. Retrying that committed plan is invalid.
This preserves the existing compaction distinction between selected publication and retirement.

Strict reopen always requires one independently supplied expected root and exact policy. It
verifies CURRENT, checkpoint, anchor, all frames and final held-inode/EOF checks. It never scans
old epochs or chooses between source/destination trust from surviving files. After uncertain
publication, the caller must use an independently accepted root when explicitly reopening;
a WrongIdentity refusal preserves forensic bytes and does not establish another root's trust.
Existing partial-tail inspection/repair remains bound to the selected expected root and exact
original bytes. Repair cannot roll back an advancement or resurrect an older selection.

## Explicit unselected-candidate cleanup

`discardUnselectedRootAdvance` first validates the actual confirmed selected head. The plan must
still originate from the same source physical selection, and its target must be exactly the
immediate unselected successor epoch. Later ordinary appends in that same source epoch may be
allowed for cleanup only; they never make the old plan publishable. An advanced/compacted epoch
or a target that has become selected must refuse.

Before any unlink, all existing candidate checkpoint/journal/staging files must be regular,
bounded exact prefixes of this opaque plan's expected bytes. Missing names are permitted;
unknown or conflicting content preserves every candidate. Then remove only those fixed owned
names and synchronize the directory, including an already-absent retry after a prior barrier
failure. No directory scan, automatic pruning, root guessing or arbitrary-epoch cleanup occurs.
Old selected epochs remain eligible for existing explicit retired-epoch cleanup, even when their
roots differ from the current one; validation still uses the current independently expected root.

## Completion checks and implementation units

1. Contract and ownership/publication decision recorded here, linked from the storage guide.
2. Coherent durable advancement implementation with its supporting tests/docs: independently
   authored two-root fixtures, changed/unchanged values, stale positive and negative proofs,
   present-empty/Absent/Unknown distinctions, empty/read-only destination evidence, exact inherited
   limits, wrong chain/root, stale position/policy, root/image return cycles, maximum epoch/sequence,
   caller mutation, retained readers, strict reopen and following ordinary updates.
3. Group preparation/publication/cleanup qualification: provider refusal before IO; real native
   short writes and barrier/close/rename failures; confirmed selection versus retirement failure;
   exact forensic files; all-candidate preflight; same-epoch cleanup after append; selected-target
   refusal; idempotent synchronized retry; default/private result and plan misuse guards; 1,000
   scoped ARC cycles after all extraction temporaries retire.
4. Grouped real-process transition/cleanup interruption: successful controls, exact stopped-child
   LOCK contention and kill/reap at observed boundaries; independently accepted source/destination
   reopen expectations; no stale-proof inheritance or trust fallback; explicit cleanup/retry and
   a following destination-root append. Process death is distinct from hardware power loss.

The contract, feature with supporting qualification, and grouped process-crash evidence are
planned as three substantive additions to native stack #1395. The existing four layers count
toward the maintainer's maximum of 15 PRs. Each ready unit is published before the next begins.
M1 framing and complete JAM state serialization remain separate milestones.
