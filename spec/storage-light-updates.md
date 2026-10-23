# Incremental light proof persistence

This storage-only tranche extends [light snapshots](storage-light-snapshots.md) and
[light files](storage-light-files.md). It preserves their independent chain/root trust,
canonical format, resource policies and explicit uncertainty. No application startup,
consensus root selection or partial-to-full-state interface is introduced.

`restoreLightSnapshot` validates an untrusted image exactly as ordinary decode does,
then retains an opaque immutable prepared image. File owners retain that image after
open, enabling later edits without caller resubmission of every old proof.

Prepared snapshot `admit` verifies one unique-key batch at the existing fixed root.
Equal keys replace their prior evidence; other canonical proof bytes survive unchanged.
`forget` removes local evidence, producing `UnknownKey`, never authenticated absence.
Unknown-only forgetting and empty batches reuse the original image without hashing.
Batch mutation limits apply to both operations; restoration remains independent of
future batch limits. Every original policy scalar is preserved.

Before hashing or allocating the new image, edits bound batch/native descriptors,
proof shapes, duplicate keys, final item count, logical value bytes and exact final
encoded bytes. Replacements release old quotas before the final merged set is charged.
The sorted merge scans retained canonical entries without allocating old proof buffers.
Admission hashes only incoming proofs plus the new checksum; forgetting hashes only
that checksum. Retained lookup owners remain immutable. Caller transport must stay
stable during synchronous calls and is copied into canonical bytes before returning.

File-owner `admit` and `forget` prepare privately, then use the existing synchronized
atomic publication. Preparation failures leave the selected image and owner usable.
IO uncertainty follows the established poison/close/reopen contract; retained readers
remain valid. Opening still verifies every persisted proof, including unchanged evidence.
The on-disk format and root never change as part of an edit.

Completion checks cover independently calculated complete roots, present-empty/long and
absent proofs, replacements at exact quotas, duplicate/overflow/oversize refusal before
hashing, unknown/empty no-ops, deterministic canonical bytes, caller/retained-owner
isolation, refusal at each incoming-proof/checksum hash, 1,000 ARC edit lifetimes,
and actual file admission/forgetting/reopen with publication failure and recovery.

Observed local evidence: the new update suite and affected snapshot/file suites pass
through the pinned checked ARC/Clang native runner. The independent48-step model
agrees with full canonical preparation after every edit. Two new two-node proofs
require exactly five hash attempts including checksum, a retained long-value proof
is not rehashed, and forgetting requires exactly one checksum attempt. Each hash
refusal boundary and a consumed post-rename directory-sync refusal recover as specified.
The1,000 successful/partial-failure/recovery edit cycles retain20,736 occupied ARC
bytes before/after. Three runtime guards, two positive controls, three privacy
rejections and actual owner-duplication lowering rejection pass. Formatting and
verification inventory pass. Local checks do not claim exact-head Linux CI.
