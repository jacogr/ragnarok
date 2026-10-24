# Strict frame-by-frame light journal reopen

This standalone storage change consumes selected light journals through
[held-inode windows](storage-held-journal-ranges.md). It preserves checkpoint, anchor and frame
formats, independent root expectations, exact inherited limits, explicit partial-tail repair
and the application integration gate. No toolchain/provider/allocator pin changes.

## Shared authenticated replay steps

`lightDeltaDeclaredExtent` reads bounded fixed header metadata to size a future frame buffer.
Its successful integer is only an allocation bound; it does not authenticate a frame or imply
that its payload/footer is present. `lightDeltaExtent` retains its complete-frame contract.

`beginLightJournalReplay` authenticates exactly one selected anchor and its independently
validated checkpoint. Its immutable result represents only that authenticated prefix.
`advanceLightJournalReplay` verifies exactly one next complete frame, enforcing predecessor,
chain/root, sequence, count, byte limits, canonical shape, checksum, proof and after-image
checks. A failed/default result exposes no candidate, and prior immutable progress is unchanged.
Available bytes of incomplete frames retain the established identity and partial-shape refusal
rules. Trailing bytes cannot be silently included in one step. A prefix is not evidence that
an external journal has ended; the consumer must establish the complete selected extent.

Whole-buffer strict replay and explicit tail planning now use these same anchor/frame steps.
Planning still binds the complete original input checksum and extent; repair continues to use
its existing bounded whole-input revalidation. No incomplete proof receives a successor image.

## Durable owner consumption

Strict `openLightJournalCache` attaches the exact bounded journal inode, reads its anchor, and
walks frame-sized windows. It checks work/sequence capacity before reading each header, checks
available identity and partial shape before a declared-length allocation, and bounds that
allocation by both the per-frame cap and the remaining held extent. Genuine short reads must
fill the requested window; incomplete frame bytes receive the established typed refusal.

At most frame-sized encoded buffers are live for reading and verification, independent of the
complete encoded-log length. The verifier may make its existing private frame copy. This does
not remove checkpoint or successor-image allocations. Checkpoint loading and anchor admission now
share one private initialization scope. Only replay progress retains the admitted checkpoint
when that scope ends; a completely authenticated first successor may retire it before later
frames. Anchor-only reopen still retains the checkpoint as its selected image. This changes
private lifetimes, not verification order, frame/EOF checks, failure publication or caller-held
immutable-reader lifetimes. Every window rechecks selected name,
inode and extent; final actual EOF/identity revalidation occurs after all proof processing.
Only then does the durable owner publish the final image, sequence and frame count. Refusal
releases both native resources and preserves exact forensic files, with no fallback or cleanup.

## Scoped evidence

`make unit SUITE=storage_light_streaming_reopen` compares filesystem streaming with whole-buffer
admission for empty/short anchors, every second-frame prefix and a separate single-byte mutation
at every second-frame position. Successful cases compare exact images and sequences; every
case checks unchanged forensic bytes and no write/rename/unlink. The suite independently
checks anchor-only progress, retained readers, fixed-header sizing versus complete extent,
all observed native read refusals, both attachment barriers, genuine seven-byte native reads,
lease release after refusal and 1,000 scoped reopen retirements. Local ARC occupancy is 9,968
before/after. Existing delta, replay, bounded partial enumeration, durable owner, repair, journal
crashes, compaction, reclamation and replacement-crash consumers accompany this change.

The maintained matched churn panel remains the resource/work regression entry point. Streaming
bounds encoded-input buffering; the earlier short-log measurement's larger successor-image
footprint is a separate cost. Evidence is local checked release on macOS arm64 with pinned
inputs. Exact-head Linux CI and hardware power-loss behavior remain separate.

The final matched three-round panel passes all twelve fresh consumers with unchanged exact
work and ARC retirement. Journal peak RSS remains 27.062/53.797 MiB for 64/1,024-byte values
on the short-log fixture; observed reopen medians are 147.933/261.798 ms. This confirms no
large-image memory improvement claim follows from bounded input buffering alone. Fifteen
existing replay runtime guards, ten positive controls and ten strict privacy rejections pass
against the final verifier tree.
