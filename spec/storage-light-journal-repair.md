# Explicit held-inode light journal repair

This standalone storage feature recovers only an explicitly inspected incomplete light update
frame. It uses the [strict replay and exact-byte tail plan](storage-light-journal-replay.md)
and [durable journal owner](storage-light-journal-cache.md), with no application, checkpoint
worker, startup, full-state or consensus integration.

`inspectLightJournalTail` acquires the selected directory's stable exclusive lease and opens
its selected journal inode. It verifies the complete current manifest and checkpoint proofs,
anchor and every complete frame. Only a bounded structurally possible nonempty incomplete
next frame can produce a live `LightJournalRecovery`. Complete valid journals need no repair;
complete corruption, invalid proofs, policy refusal and partial anchors grant no recovery
handle. Every refused inspection closes both resources and preserves forensic bytes.

The recovery handle retains one private exact-byte plan and that exact held append inode.
Its read-only `plan` result exposes only an authenticated immutable prefix and original extent,
not a fresh writable owner or durability receipt. Copies of recovery handles are forbidden,
including hidden ARC lowering copies. A native move transfers exactly one authority and leaves
its source inert. The caller must explicitly close or successfully transfer every live handle;
unclosed destruction is a contract violation. Close always disarms after attempting append
before directory retirement, preserving errors.

## Destructive repair boundary

`repair(recovery, owner)` first refuses a live target owner. Before any truncation it:

1. Re-reads and authenticates `CURRENT`, requiring the exact original selected manifest checksum.
2. Re-reads and verifies the selected checkpoint against caller chain/root, original policy and
   manifest snapshot checksum. Another valid evidence image at the same complete root refuses.
3. Checks that the selected journal name still resolves to the exact held regular inode and
   original extent, including device/inode identity. Equal bytes in a substituted inode refuse.
4. Rewinds and boundedly reads the actual held descriptor, checks actual EOF and extent, then
   rechecks the selected name/inode/extent after reading.
5. Revalidates the plan against the exact selected manifest, complete original journal extent
   and checksum of all original bytes, including the incomplete suffix.

Only then does the managed primitive synchronize before truncation, truncate to the plan's
complete authenticated prefix, and synchronize the truncated inode. It never chooses another
prefix or repairs a complete invalid frame. No `CURRENT`, checkpoint, sibling or directory name
is rewritten. The already anchored namespace is unchanged. Successful synchronization transfers
the same lease and append descriptor into the previously closed ordinary journal owner, with
the prefix image, sequence and frame count. The consumed recovery handle becomes inert.
The receipt is `FileAndDirectorySynced` for the anchored namespace and successful truncation
barriers; it makes no physical-device, power-loss or consensus claim.

Observed changed selection/checkpoint/transport/extent/inode, read or close failure, provider
refusal and truncate/barrier uncertainty grant no writable owner and poison fresh inspection
access. Explicit close and a new strict open or inspection are required. Pre-truncate failure
leaves the original tail; failed post-truncate synchronization reports `PublishedUnsynced` and
strict reopen may confirm the complete prefix. No failure is presented as a successful repair.

Directory locks coordinate cooperating storage users. Negative mutation tests deliberately
bypass that lease to prove the observed revalidation refusals. These checks do not make arbitrary
concurrent hostile filesystem mutation race-free, authenticate a different consensus root or
replace operating-system/filesystem guarantees. The managed read checks selected name, inode
and extent before and after its bounded read; checksums remain local corruption detection.

## Scoped verification

A shared test-only fixture derives a two-key complete root independently, then retains partial
proof evidence and authenticated forward/reverse transitions. The native repair suite covers
strict refusal before inspection, exclusive contention, busy transfer targets, native moves,
real short reads, exact prefix truncation, unchanged `CURRENT`/checkpoint and preserved forensic
siblings. Repaired owners append successfully and strictly reopen, while retained plans/readers
remain immutable and independent of the consumed lease.

Negative cases modify same-size bytes, grow/shrink the log, substitute an equal-byte inode,
select another valid manifest, replace the checkpoint with another valid same-root image,
or refuse the provider. Every case refuses before physical truncation. Complete valid and
complete corrupt journals grant no recovery owner and release their inspection leases.
Real read, close, pre-sync, truncate and post-sync refusals are consumed and checked, including
poison gates, exact forensic extents, fresh inspection/retry and strict reopen.

Real process controls complete both observed repair operation families. Three exact child
stop/SIGKILL/reap witnesses cover pre-truncate sync, truncate and post-truncate sync. A stopped
child still holds the exclusive lease. After death, exact old-partial or complete-prefix bytes
are checked; only the former needs another explicit repair. These are process-death witnesses,
not power-loss tests.

One thousand scoped inspection/plan/retirement cycles return ARC occupancy to baseline. The
ordinary journal owner suite also passes against the extended managed I/O module. Runtime
failed/default plan and unclosed-recovery guards have independent success controls, with
strict private-field and actual native recovery-copy compiler rejection. Formatting and
inventory checks accompany local checked release evidence on macOS arm64 with pinned tools;
exact-head Linux CI remains separate.

Next substantial work groups append/bootstrap process-crash qualification, checkpoint
compaction and guarded epoch reclamation. No automatic repair, pruning, fallback or application
integration is introduced. M1 framing evidence remains distinct from complete serialization.
