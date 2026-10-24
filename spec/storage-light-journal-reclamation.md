# Guarded light journal reclamation

This standalone maintenance feature explicitly removes retired physical epochs or abandoned
prepared compaction files. It preserves the selected light proof image and global sequence.
It builds on [compaction](storage-light-journal-compaction.md) and
[held-inode repair](storage-light-journal-repair.md), with no application/startup/full-state
integration, directory scan, automatic pruning or alternate-head selection.

## Selected-head gate

Every destructive cleanup first re-reads and authenticates the exact current manifest and
selected checkpoint, then boundedly reads the actual held journal after selected-name/inode/
extent checks. Strict replay must reproduce the owner's exact confirmed image checksum,
sequence and frame count. Changed selection/checkpoint, an equal-byte replacement journal
inode, corrupt transport, exceeded policy or provider/read refusal grants no deletion and
poisons fresh owner operations until explicit close and strict reopen. Retained old readers
remain valid.

Only confirmed selected authority can authorize removing unselected namespace entries. File
checksums do not supply consensus root trust. Directory leases coordinate cooperating users;
observed mutation is refused, but arbitrary hostile concurrent filesystem replacement is not
claimed race-free.

## Retired epochs and explicit staging

`cleanupRetiredEpoch(owner, epoch)` accepts only a positive epoch strictly below the selected
physical epoch. Zero, selected and future positions refuse before hashing, reads or deletion.
Epochs advance one at a time, so these exact canonical namespace slots are historical unselected
pairs. Only that epoch's regular no-follow journal and checkpoint names are removed. Unknown
sibling names, arbitrary future slots, `CURRENT` and `LOCK` are never targets. No old file is
adopted as authority or required to reconstruct selected state during removal.

`discardPending(owner)` separately removes only regular no-follow `CURRENT.next` after the same
selected-head gate. Its payload is explicitly discarded as unselected staging, never interpreted
as a selected manifest. This is a caller-requested fixed-name operation; it does not authorize
removing unrelated candidate contents or unknown sibling names.

Each successful cleanup ends with a directory synchronization, including when every requested
name was already absent. This matters when a prior final unlink succeeded but its directory
barrier failed: retry cannot turn observed absence into a false completed durability claim without
a fresh barrier. Deletion/barrier errors are returned and permit explicit idempotent retry. They
do not erase the already confirmed selected head, whose files and publication are untouched.
Selected-head validation failures instead poison fresh authority because that selection is no
longer confirmed. Successful barriers remain local system-call evidence, not power-loss guarantees.

## Abandoned prepared candidates

`discardUnselectedCompaction(owner, prepared)` requires an opaque authenticated compaction plan
for the immediate next physical epoch, with the same original selected manifest/epoch and exact
inherited image policy. The target cannot be selected or an arbitrary future slot. A plan's global
sequence may precede later ordinary appends within the same physical epoch: its immutable image
still describes that unselected candidate, while the selected head is independently revalidated.
After another compaction selects the plan's target, the old plan can never discard it.

Before deleting any file, all possible candidate files are preflighted against their exact
prepared bytes: the checkpoint against the prepared image, the journal against its anchor, and
`CURRENT.next` against its manifest. Only absent files or bounded regular no-follow exact prefixes
are accepted. A zero-length regular file is a possible interrupted candidate write. Extra bytes,
wrong bytes, unknown candidate payloads, symlinks and file/read/close refusals preserve every
candidate and the confirmed selected owner. Prefix equality supplies no publication authority.

After all preflights pass, cleanup removes only matching staging, next journal and next checkpoint,
then synchronizes the directory even when all are already absent. Real interrupted checkpoint or
staged-manifest writes can therefore be explicitly discarded before retrying the same confirmed
position. Unknown staging can first be handled by the separate explicit fixed-name staging API;
unknown candidate contents are never silently overwritten or deleted. An ambiguous candidate whose
prepared plan cannot be reconstructed remains forensic rather than being guessed from filenames.

## Scoped evidence

The checked native suite uses independently rooted genuine compaction and following-frame fixtures.
It verifies exact selected bytes/readers/position, historical-pair removal, zero/current/future
refusal before work, unknown siblings/future slots, repeated absent-name synchronization and
explicit staging removal. Five consumed unlink/sync refusal modes exercise partial and completed
removal, confirmed fresh reads and durable retries, including both names already absent after a
failed last-unlink barrier.

Changed selected manifest, another valid same-root checkpoint, an equal-byte selected journal inode
and provider refusal all prevent every unlink and preserve retired forensic bytes. Candidate
cases use actual interrupted 64-byte checkpoint writes, interrupted staged manifest writes and
failed rename; bounded exact-prefix cleanup permits explicit compaction retry. Unknown prefix
cases preserve all good candidates/staging before refusal. A retained older candidate plan works
after ordinary same-epoch append, but refuses immediately once its target is selected. Narrow
managed-prefix tests check default directories, invalid CURRENT targeting, expected-byte limits
before reads, missing files and no-follow symlink refusal.

One thousand scoped selected-head replay and already-absent cleanup cycles return ARC occupancy
to the same 11,232-byte baseline. The existing repair suite passes after sharing the strict
checkpoint reader, with its 1,000-cycle ARC baseline unchanged. No new result payload or native
owner type is introduced; existing authority guards remain unchanged. Semantic, formatting and
inventory checks accompany local macOS arm64 checked release evidence with pinned tools/providers.
Exact-head Linux CI and grouped cleanup process-crash qualification remain separate.

Next substantial work qualifies real compaction/cleanup process deaths and measures matched
full-image versus journal workloads before further physical I/O changes. Historical M1 framing
completion remains distinct from complete state serialization.
