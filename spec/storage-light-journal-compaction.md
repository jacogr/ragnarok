# Atomic light journal checkpoint compaction

This standalone physical maintenance operation replaces a light journal epoch without changing
its independently selected complete chain/root, proof knowledge or global update sequence.
It builds on the [durable owner](storage-light-journal-cache.md) and distinct light-journal
selection schema. No application, StateStore, checkpoint worker, startup or consensus wiring
changes here.

## Prepared exact-position authority

`prepareLightCompaction(owner, expectedEpoch, expectedSequence)` checks a confirmed live owner,
the exact expected physical epoch and global sequence, and epoch exhaustion before incrementing
or hashing. It prepares the next manifest and empty journal anchor around the current immutable
proof image. Zero and maximum global sequences are valid checkpoint baselines; compaction never
increments that domain. The physical epoch must remain positive and cannot wrap.

The opaque `PreparedLightCompaction` retains the current authenticated image and tiny fixed
metadata, including the original manifest identity and exact position. It retains no native
lease, mutable caller buffer or predecessor-image chain. Copies retain immutable authority.
Default handles report uninitialized; epoch/sequence getters require initialized private backing.
Preparation hashes only the new fixed manifest and anchor and performs no file I/O. Provider
refusal preserves the current owner's confirmed authority.

`compact(owner, prepared)` requires the exact original epoch, sequence, manifest checksum,
current image checksum and inherited snapshot policy. Stale or default plans cannot publish.
An equal complete root alone is insufficient. Prepared publication performs no repeated proof
or metadata hashing. Another owner with equivalent trusted selection still must satisfy all
binding checks and its own fixed resource policies; no native lease is carried by a plan.

## Atomic physical replacement

Publication exclusively creates the next epoch's checkpoint from the current immutable image,
synchronizes its bytes and namespace, creates and synchronizes the exact empty anchored journal,
and opens the actual candidate append inode. Its bounded returned bytes must equal the prepared
anchor. Only then does synchronized atomic `CURRENT` replacement select the new epoch.

Before confirmed selection, no candidate owner or completed receipt escapes. Existing candidate
names are never overwritten. A pure candidate-name refusal preserves confirmed old authority;
other observed I/O uncertainty, including blocked/failed manifest publication, requires close and
strict reopen. Failed candidate files and staging remain forensic. A post-rename directory-sync
failure reports `PublishedUnsynced`; no guessed selected epoch is exposed through fresh getters.

After `CURRENT` and its directory barrier complete, the new physical selection is confirmed.
The old append handle is retired and the new held append handle transfers into the owner. The
owner keeps exactly the same immutable image and global sequence, resets replay frame count to
zero, and uses only the new journal anchor bytes. This makes configured journal capacity/frame
budget available again. The next update still requires the next global sequence and exact current
image checksum. Strict reopen starts from the new checkpoint baseline and verifies following
frames normally.

Old snapshot/journal files remain untouched. This unit performs no deletion, scan, automatic
reclamation or skipping past occupied candidate epochs. Explicit guarded cleanup is separate.
Retained readers and prepared plans keep immutable images without retaining directory ownership.

## Confirmed selection versus retirement

The successful result contains passive `LightCompactionReceipt` metadata: previous epoch, selected
new epoch, unchanged global sequence and a separate `retirement` error. These copied diagnostic
fields are never accepted as publication or cleanup authority.

A failed old-handle close after confirmed selection cannot erase the completed manifest barrier.
The operation therefore still returns a successful confirmed-selection receipt carrying that
retirement refusal. The owner poisons fresh operations and requires explicit close/reopen; the
caller can see what committed without implicitly retrying it. After strict reopen, the same old
prepared plan is stale and cannot advance another epoch. An unexpected handle-transfer refusal
is treated the same way. Failed/default tagged results never expose a receipt or prepared payload.
Successful barriers describe local system calls, not device power-loss guarantees or root trust.

## Scoped verification and remaining work

The independently rooted native fixture fills a one-frame journal budget, checkpoints it and
appends the next global frame after compaction. It checks exact new checkpoint/anchor/manifest
bytes, unchanged old files/readers, strict reopen, stale plans and distinct epoch/sequence domains.
Preparation observes exactly two fixed hashes; an opaque publication observes zero provider
calls and exactly three writes, eight syncs and one rename on the checked local workload.

Both preparation provider boundaries refuse before I/O. Real faults cover checkpoint and anchor
writes, staged-manifest sync, rename, post-rename directory sync, candidate read, staged-file close
and old-handle retirement. Existing candidate/staging sentinels are preserved. Cases distinguish
old selected epoch, uncertain new selection and confirmed selection with retirement failure;
all require the documented fresh-observation and strict-reopen behavior. Maximum physical epoch
refuses before work, while maximum global sequence checkpoints unchanged and still refuses
further update increments.

One thousand scoped prepared/copy/retirement cycles return ARC occupancy to baseline. Runtime
default/failed prepared and receipt results and default candidate getters have independent
successful native controls, with strict private-backing compiler rejection. Formatting and
verification inventory checks accompany local macOS arm64 checked release evidence using pinned
tools/providers. Exact-head Linux CI and grouped process-crash qualification remain separate.

Next substantial work is guarded retired/abandoned epoch and staging cleanup, followed by grouped
compaction/cleanup process-crash qualification and matched storage measurements. Historical M1
framing completion remains distinct from complete state serialization.
