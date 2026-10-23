# Atomic light proof evidence batches

This standalone feature extends [incremental light evidence](storage-light-updates.md)
with `update(proofs, forgottenKeys)` on prepared snapshots and light file owners.
It preserves the independently selected root, exact policies and canonical format.
It does not choose consensus roots or change application startup.

A capacity replacement previously required forgetting then admitting, causing two
separately visible file publications. The combined operation preflights the complete
final evidence set, verifies incoming proofs privately, and publishes one image once.
Old readers retain their original knowledge. Fresh readers see the whole new set only
after successful file/data/directory publication; uncertainty follows close/reopen recovery.

The mutation allowance counts the sum of both input lengths. Validate addition and
native descriptor bounds before allocation. Both lists and their union must be unique:
a key occurring in both lists is a `DuplicateKey` proof failure, since admission already
replaces existing evidence without an explicit forget. Per-proof shapes and the final
item/value/file quotas are checked before hashing or allocating a new encoded image.
Forgotten and overwritten charges are released before charging the final selected set.
Unknown keys may be forgotten; they never become authenticated absence.

Private cache forgetting and proof admission may construct temporary immutable state,
but no intermediate cache escapes. A bad proof, checksum-generation failure or provider refusal
leaves the original prepared image and file owner usable with unchanged selected bytes.
Incoming proofs alone are reverified; retained proof bytes are copied canonically.
Combined empty batches reuse the prepared image. File operations still perform real
publication barriers before returning a fresh durability receipt. Existing `admit` and
`forget` delegate to the same planner with one empty list and keep their contracts.

Completion checks cover full item/value/file capacity replacement, disjointness and
combined batch limits before hashing, unknown forgetting, all incoming-proof/checksum
refusal boundaries, retained/default/read-only state, canonical output versus independent
full preparation, a deterministic set model, 1,000 success/partial-failure/retry ARC cycles,
and actual file IO counts, failed publication, poison/close/reopen and old/new selection.

## Local verification

The new atomic-batch suite and four affected incremental-update, borrowed-view, snapshot
and file-cache suites pass through the checked native runner. A replacement at exact
three-item/33-byte/732-byte-image capacity matches independent full preparation and uses
one real write, two syncs and one rename. The combined allowance and cross-list conflict
cases refuse before hashing/IO. All five incoming-proof/checksum refusal points, a 32-step
flat known-key model, write refusal and post-rename directory-sync uncertainty pass.
The 1,000 success/partial-failure/retry lifetimes retain 19,616 occupied ARC bytes before/after.
Three file-result/retirement runtime guards, two controls, three privacy rejections and
actual owner-duplication lowering rejection pass. Formatting and inventory pass.
These local results do not claim exact-head Linux CI or production power-loss qualification.
