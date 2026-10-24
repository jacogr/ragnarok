# Bounded light-journal maintenance

Scope: storage-only opt-in threshold compaction and bounded canonical retired-epoch cleanup,
built on the existing [compaction](storage-light-journal-compaction.md),
[reclamation](storage-light-journal-reclamation.md), [root advancement](storage-light-root-advancement.md)
and [retention](storage-light-retention.md) contracts. Independent root authority, pinned Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, V1 bytes and toolchain/provider policies remain unchanged.
Application startup, scheduler/network integration and hardware power-loss qualification remain separate.

`LightMaintenanceLimits` explicitly supplies frame-count and frame-byte compaction thresholds,
an initial canonical retirement cursor, a maximum number of retirement jobs and a count of earlier
physical epochs to preserve. Zero disables a threshold; bytes exclude the fixed journal anchor.
Thresholds cannot exceed inherited journal capacities. Either reached threshold requests compaction,
but an empty post-checkpoint log never compacts again. Maintenance never evicts proof knowledge or
changes the complete root, snapshot policy or ordinary-update sequence.

`prepareLightMaintenance(owner, expectedEpoch, expectedSequence, limits)` captures the exact
physical selection, chain/root, image checksum, sequence, frame count, journal extent and every
snapshot/journal policy scalar. Preparation performs no IO. It hashes only the existing two
compaction metadata objects when compaction is requested; no-action/cleanup-only preparation is
hash-free. Epoch exhaustion refuses before increment/hash. Default plans grant no authority.

Retirement addresses only canonical positive epochs strictly below the prospective selected epoch,
minus the explicitly preserved count. The explicit first cursor may equal the selected epoch as an
already-finished sweep, but cannot be zero or beyond that head when jobs are enabled. A disabled
sweep ignores its input cursor and exposes zero. Range arithmetic
is subtraction-based, and the exclusive progress cursor never exceeds the selected epoch. No names
are enumerated or selected by a directory scan. Each completed job uses the existing strict selected-
head revalidation and no-follow canonical pair cleanup, including final synchronization when names
are already absent. Unknown sibling names, pending manifests and arbitrary future epochs are not jobs.

`maintain(owner, prepared)` refuses any changed source/policy before publication. It optionally
confirms compaction, then performs only the bounded prepared retirement jobs. A failure before
confirmed compaction exposes no receipt. Confirmed compaction with append-handle retirement failure
returns its passive receipt and skips cleanup. Later cleanup failures return a successful passive
`LightMaintenanceReceipt` carrying the confirmed epoch/sequence, separate retirement/cleanup reasons,
completed synchronized job count and first unfinished cursor. They never erase a confirmed selection
or imply all cleanup succeeded. Existing fresh-owner poisoning rules remain in force.

After a failed cleanup, explicitly reopen if required and prepare a fresh plan at the confirmed head
using the receipt's unfinished cursor. A partial unlink never counts as a completed job; absent-name
retry still synchronizes. Old source plans stale after compaction, even when root/image/sequence are
unchanged. `discardUnselectedMaintenance(owner, plan)` delegates only its opaque compaction to the
existing all-prefix-preflight cleanup. It cannot discard a selected target, unknown candidate bytes
or a plan without a compaction candidate. No automatic salvage, publication retry or root guessing
is added. Reads remain immutable and free of hidden maintenance side effects.

Completion checks cover independent threshold/range models, exact source and policy refusal,
no-action/read-only preparation, maximum epoch/cursor arithmetic, immutable retained readers,
separate publication/retirement/partial-cleanup receipts, bounded continuation and synchronized
absence retry, result/private-plan guards and 1,000 ARC retirements. Real stopped-child deaths
qualify combined compaction/cleanup and cleanup-only paths before strict reopen, explicit matching
candidate cleanup or fresh-plan retry, then a following ordinary update.

## Implemented-scope evidence

Local checked ARC/Clang ThinLTO macOS arm64 verification passes 490 independent threshold/range
model cases, exact policy/source refusal, zero-mutation-budget compaction, maximum epoch/sequence
and maximum preservation/cursor arithmetic, separate publication/retirement/cleanup receipts,
nine consumed native/provider failure cases, partial multi-pair progress and synchronized absent-
name continuation. One thousand prepared/copy/late-metadata-refusal cycles retain 9,920 occupied
ARC bytes before/after. Seven runtime guards, five genuine controls and one exact private-plan
compiler rejection pass. Existing compaction, reclamation and retained-admission suites pass.

The maintained process suite passes nine actual completion controls and 56 exact stopped-child
SIGKILL/reap boundaries, including 18 real 64-byte write boundaries. Combined maintenance observes
three normal writes, eleven syncs, one rename, two unlinks and ten closes. Cleanup-only work
observes three syncs, two unlinks and six closes, including selected-inode and retired-child
validation. Every killed child retains LOCK against a live Busy contender before kill/reap.
Independently authored manifest/anchor/image bytes prove selection and complete or exact partial
transport before strict reopen. Explicit matching unselected discard or fresh-plan cleanup retries
preserve selected bytes, synchronized absence, old readers and unknown siblings; a following
retained admission advances the ordinary sequence exactly once and strictly reopens.

Pinned formatting, semantic and inventory checks pass; logs and receipts remain under ignored
`build/storage-db5-maintenance-*`. Compiler pin remains
`4724f66c2e01b17810c844f26575b2317995fda2`. Local process-death evidence does not establish
hardware power-loss durability or full native Linux qualification. M1 framing remains its
existing completed milestone, distinct from complete JAM state serialization.

This implements opt-in bounded retention and maintenance at the standalone owner boundary.
Owners still retain complete selected evidence images/caches; paged working-set storage remains
separate work. Application scheduling/startup adoption and network proof acquisition retain
their existing integration ownership and independently selected root authority.
