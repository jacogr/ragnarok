# Standalone storage records

Scope: detached changed-node persistence foundations under `src/storage/`. GP 0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401` M/B/L remain authoritative; physical records
are local storage data. No state/checkpoint/PVM/application consumer may adopt this work until
explicitly authorized. This storage stack is limited to twenty new PRs after #371.

## Detached revision exports

`exportFullTrie` exports against the empty base. `exportTrieChanges(base, target, limits)` emits
only physical records absent from the declared complete base. Unchanged subtrees are skipped by
cached complete digest, including leaves moved by singleton collapse. Children precede parents.
The detached record includes full left/right child identities: JAM B intentionally clears the left
child's high bit, so its protocol bytes alone cannot serve as a physical navigation record.

Preflight bounds descriptor count and copied leaf bytes before allocation. No hashes or filesystem
operations occur. Result metadata copies base/target roots and exact target entry/node counts;
raw mutable transport records are untrusted and confer no chain authority. Leaf bytes are copied,
and no canonical ARC graph survives in the export. Empty/equal revisions may export zero records.

`make unit SUITE=storage_node_export` checks full/delta shapes, cached collapse, all output ceilings,
input/output isolation, zero crypto calls under refusal and 1,000 scoped ARC cycles. Future layers
must validate physical records before accepting them into a repository or disk layout.

## Strict physical batch codec

`record_codec.nim` encodes exact `RAGNAROK-TRIE-V1\n`, base/root (32 bytes each), uint64
little-endian target entry/node/record counts, then physical records. A leaf stores tag 0, digest,
31-byte key, uint64 raw length and raw value. A branch stores tag 1, digest and both 32-byte full
children. Unused raw object fields must be zero/empty; empty branches, duplicate addresses and
nonempty records at the reserved zero address reject. Root/count claims are bounded but not trusted.

Decode scans every extent and budget before allocating records. Both encode and decode verify
all local node digests through existing JAM B/L primitives; only complete success exposes payload.
Complete graph availability, key routing and externally trusted root selection are later repository
responsibilities. The codec does not authenticate a caller's root or a chain transition.

`make unit SUITE=storage_record_codec` verifies exact framing, every truncated prefix, trailers,
invalid tags, full-width length/count attacks, duplicate/canonical field refusal, changed value
integrity, exact/short encoded budgets and present/empty transport ownership.

## Atomic in-memory node repository

`node_repository.nim` publishes one complete root only after raw records pass local integrity and
full graph validation: all children exist, keys follow MSB routes, no node repeats/cycles, branches
contain at least two leaves, and exact entry/node/value budgets agree. Unreachable new records
refuse. Existing addresses may be reused only with identical physical records; the full left child
is part of physical identity even though JAM masks its high bit in B.

`publish(expectedView, batch)` requires the exact current view and matching base root. Generations
are local checked uint64 ordinals. Private candidates publish at one point; all refusals preserve
the previous view. New values are copied. Copies of the updateable owner branch independently,
and retained read views survive updates and explicit close. Missing physical records, default
views and present-empty leaves remain distinct. Accumulated node/value ceilings include old nodes;
no reclamation, disk durability or state-consumer integration is introduced here.

`make unit SUITE=storage_repository` checks independent changed-node publication, exact counts,
input/read isolation, stale/base/partial/misrouted/count-invalid refusal, storage budgets, close
lifetimes and 1,000 fresh ARC cycles. Shared storage samples remain test-only.

## Independently trusted standalone restoration

`restoreFullTrie(view, expectedRoot, FullStateTrieLimits)` checks an independently trusted root
before any reconstruction. Narrower target limits are enforced on the complete reachable graph
before copying leaf values; retained unreachable history does not become part of the map. The
standalone trie constructor rebuilds the exact root, and only a matching result is exposed with
the caller's explicit future mutation ceilings. Backend refusal carries a guarded `TrieFailure`
reason, not a partial trie. No `StateStore` or checkpoint adapter is involved.

`storage_restoration_replay` loads all fourteen original mappings via the existing pinned provider,
publishes full/changed/inverse physical batches and verifies every restored value/count/root,
trusted-root refusal, narrower ceilings and views retained beyond close. The observer-linked
`storage_restoration_failure` suite proves trust/policy refusal before hashes, typed backend failure,
subsequent recovery and 1,000 independent ARC release cycles.

## Full-state database identity

`database_identity.nim` encodes `RAGNAROK-FULL-NODES-V1\n`, an explicit nominal 32-byte
`StorageChainId`, then Blake2b-256 of that complete prefix. Decode requires exact bytes, a valid
checksum and the independently selected chain. Unknown schema/mode or incompatible chain never
converts or reuses a database implicitly. This checksum grants no chain authority. Default identity
objects refuse; callers must choose the chain and path before opening physical storage.

Only the full-state schema is implemented. A future light database needs a separate schema and
proof/trust contract; no light-state API, CLI mode or path-selection adapter is added. The native
`storage_identity` suite checks a frozen independent hashlib witness, every truncated prefix and
every one-byte corruption, exact/short limits, trailers, defaults and valid-but-foreign chains.

## Append-only journal framing

`journal_codec.nim` wraps each physical batch with uint64 little-endian body length and nonzero
local generation, followed by the body and Blake2b-256 of all preceding frame bytes. The checksum
covers root/count metadata and publication order as well as records. A frame extent helper can
split a bounded journal but confers no content validation. Decode requires exact consumption,
checks integrity before allocating records, and preserves selected physical codec failures.

`storage_journal_codec` checks an independent complete struct/hashlib witness, every prefix and
every octet corrupted, max-width length attacks, exact/short ceilings, zero generations and
multiple-frame splitting without accepting trailers as one frame. No disk IO occurs in this layer.

## Exclusive append-only disk repository

`file_repository.nim` implements the same physical revision publication/read contract using one
append-only regular file. Explicit creation uses 0600 `O_EXCL`; reopening requires the full-mode
identity and independently expected chain. The journal inode itself holds a nonblocking exclusive
advisory lock for its entire owner lifetime; cooperating callers preserve its directory/inode
namespace. FIFO/device/directory/symlink paths cannot become owners. Owners are independently
noncopyable and require explicit close, including after uncertainty. Calls are synchronous storage
work, not networking callbacks; no wall-clock IO deadline is claimed.

Open bounds bytes by actual chunked reads, verifies every complete frame, consecutive local
generations and complete graph admission, then synchronizes file and directory before adoption.
A corrupt/partial tail refuses the whole open; no prefix fallback or implicit truncation occurs.
Publication privately prepares the memory successor, bounds journal growth, anchors the previous
file/directory boundary, appends one exact frame and fsyncs before replacing the live memory head.
Changed records and their selected root share one checksummed transaction frame.

Partial writes return IO failure and poison the owner; complete writes followed by failed fsync
return `PublishedUnsynced`. Neither exposes a successor. Further reads/publications require
reopening/recovery; previously held views stay valid. Strict reopening can anchor a complete visible
frame from prior uncertainty, but its local root still grants no chain authority. Failed bootstrap
may leave a file requiring explicit operator recovery. No automatic deletion/conversion occurs.

`storage_file_repository` uses real file/directory synchronization and tests delta publication,
strict reopen, chain mismatch, cooperative contention, stale refusal, retained views after close
and 1,000 isolated ARC cycles. These are real OS behavior checks, not power-loss simulation.

Observed disk-layer evidence: checked optimized macOS ARM64 `storage_file_repository` passes
1,000 real synchronized publication/reopen cycles at 192/192 occupied ARC bytes.
`storage_file_admission` verifies exact 0600 creation under a restored umask, bounded reads,
unchanged partial/corrupt files, FIFO/directory/regular-target/dangling symlink refusal and
subsequent valid reacquisition. Five strict runtime guards, four valid controls, four privacy
rejections and actual `'=dup' is not available for type <FileRepository>` lowering pass.
Power-loss behavior and actual file/directory-sync refusal remain separate evidence gaps.

## Explicit interrupted-tail recovery

`recoverFileRepository` requires an independently trusted exact last-complete generation/root
token under the journal lock. Only an incomplete final frame or length prefix may be truncated.
Complete corrupt frames, impossible/oversized lengths and mismatched generation/root tokens
refuse without byte mutation. A complete visible successor is never dropped to satisfy an older
token. Identity validation precedes recovery, and ordinary `openFileRepository` remains strict.

Before truncation the verified prefix is synchronized with its parent; after truncation the same
file/directory barrier precedes owner adoption. O_APPEND resumes at the new EOF despite the old
read offset. Previously selected views remain independently valid. Header/bootstrap repair and
complete-frame corruption repair are deliberately unsupported.

`storage_journal_recovery` forks isolated real RLIMIT_FSIZE writers at zero/partial/final-byte
ceilings and exact/ample controls. It separately verifies child poisoning, parent strict refusal,
unchanged selected prefixes, exact trusted recovery, resumed publication/reopen, refusal to
rollback complete frames and refusal to truncate complete checksum corruption. No live file owner
crosses fork; no cross-process ARC or power-loss claim is made.
