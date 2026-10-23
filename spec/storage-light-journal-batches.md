# Bounded prepared light journal update batches

This standalone local-storage feature groups ordinary authenticated light update frames into
one append/barrier operation. It preserves existing checkpoint/anchor/frame encodings,
independent chain/root trust, exact inherited limits, full/light separation and the application
integration gate. No compiler, provider or allocator changes.

## Preparation and publication

`LightJournalEdit` supplies one ordinary disjoint proof-admission/removal update. Caller-owned
proof and key buffers remain stable during synchronous preparation; later caller mutations
cannot change prepared transport, immutable candidate lookups or retained source readers.
`prepareLightJournalBatch(owner, edits)` requires a nonempty group, bounds remaining frame count,
sequence growth and minimum aggregate byte extent before provider work, and authenticates every
update at its exact predecessor. Remaining log capacity also caps each frame before its own
shape allocation and proof verification. Intermediate candidates stay private. The result
retains only final immutable evidence, bounded concatenated frame bytes and exact starting
selection/image/epoch/sequence/frame-count/byte-extent metadata, without a native lease or an
intermediate-image chain.

The opaque `PreparedLightJournalBatch` exposes guarded frame count, byte length, final sequence
and prepared snapshot. Default/failed values grant no payload. Its immutable snapshot is a
candidate, not a durable-head receipt. Copies may outlive the source owner without retaining LOCK.

`owner.append(batch)` checks inherited policy and the exact starting position before IO. A
logical update or checkpoint replacement makes the candidate stale, including compaction that
preserves sequence but changes physical selection. Normal full-progress append performs one
write of the complete concatenation and one file synchronization, with no rename or provider
work. Actual short writes/EINTR retain the existing bounded native write-loop semantics. Only
confirmed completion publishes the final image, global sequence and frame count in memory.
The returned synchronization receipt has the same meaning as ordinary journal append.

## Explicit uncertainty and recovery

A failed write returns `IoFailure`; failed synchronization after complete bytes preserves
`PublishedUnsynced`. Either poisons fresh owner observations until explicit close and strict
reopen/inspection. The disk can contain complete earlier frames and an incomplete next frame.
This operation does not promise an all-or-nothing disk transaction or automatically roll back.

Strict reopen may confirm a complete observed prefix. An incomplete suffix requires the existing
held-inode inspection, exact original-byte plan and synchronized prefix repair. Recovery retains
every fully authenticated earlier frame. The original prepared group is reusable only if the
exact original predecessor remains. Otherwise it refuses as stale; callers prepare only the
remaining updates at the recovered predecessor. No completed frame is duplicated or discarded.

## Scoped evidence

`make unit SUITE=storage_light_journal_batches` compares exact concatenated bytes and final image
against two independently prepared genuine proof transitions. It checks zero-IO preparation,
one normal write/barrier with zero hashes, immutable lookup/input ownership, copied candidate
lifetime, logical and physical stale positions, nonempty/frame/aggregate/per-frame/maximum-near
sequence bounds and every observed preparation-provider refusal. One thousand prepare/late
provider-refusal/retry cycles retire intermediate images and transport to the same occupied
ARC baseline (8,976 bytes locally).

Every actual 64-byte short-write failure position and a failed final synchronization receive
fresh namespaces. Tests check exact written extents, poisoned observations, strict open versus
explicit repair, retained complete-frame counts, original-candidate stale rules, remaining-update
retry and exact final journal bytes. Unknown siblings and old readers survive. The existing
durable owner, held-inode repair and streaming-reopen suites pass. Eight runtime authority guards,
six independent positive controls and three strict private-field compiler rejections cover the
new opaque candidate and result payloads. Seven paired benchmark admission tests plus six
full-image admission tests pass.

## Matched resource/work panel

```sh
make setup
python3 tools/storage_light_journal_benchmark.py --output build/light-batch-panel --samples 5 --include-batch
```

The optional third mode preserves historical two-backend report admission. It uses the same
4,096-query fixtures, 17-node proofs, eight one-key forget/admit pairs, retained pre-edit reader,
exact final image/reopen and whole-child resource receipts. Preparation and append are timed
together. The batch candidate retires before reopen, matching ordinary per-update preparation
lifetime; caller-authored edit inputs are prepared outside the timed phase. All sixteen frames
remain in the journal and are reauthenticated on reopen.

Two final three-round panels passed on October 23, macOS arm64, pinned Nimony
`4724f66c2e01b17810c844f26575b2317995fda2`: 36 fresh consumers and four separate producers.
The second final panel observed:

| Value bytes | Mode | Application write bytes | Writes / syncs / renames | Update ms median (min–max) | Peak RSS MiB median |
| ---: | --- | ---: | --- | ---: | ---: |
| 64 | Full image | 78,176,952 | 16 / 32 / 16 | 155.380 (154.145–156.469) | 17.734 |
| 64 | Journal | 13,216 | 16 / 16 / 0 | 130.239 (129.617–132.598) | 27.078 |
| 64 | Journal batch | 13,216 | 1 / 1 / 0 | 128.057 (128.056–129.045) | 27.078 |
| 1,024 | Full image | 141,083,832 | 16 / 32 / 16 | 270.405 (269.730–273.294) | 36.766 |
| 1,024 | Journal | 20,896 | 16 / 16 / 0 | 233.674 (232.539–236.193) | 53.812 |
| 1,024 | Journal batch | 20,896 | 1 / 1 / 0 | 229.514 (229.194–232.359) | 53.812 |

Both journal modes perform 176 update hashes and 73,907 reopen hashes. Grouping reduces measured
ordinary write/barrier work, without changing proof/image reconstruction or encoded byte volume.
The small timing difference is not a demonstrated general speedup. Application write extents
are not physical device traffic; peak RSS includes load, initialization, update preparation,
append, reopen and validation. No cold-cache, Linux pressure or hardware power-loss claim.
Exact-head Linux CI remains separate.
