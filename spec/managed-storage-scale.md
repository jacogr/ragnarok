# Managed storage scale measurements

This storage-only tranche measures the merged managed layout before changing its implementation.
It preserves Gray Paper 0.8.0 commitments, existing file formats, bounded canonical history,
explicit finality and independent checkpoint-import trust. No state/app interface changes are planned.

## Fixed workload and completion checks

`make unit SUITE=managed_scale` uses the pinned checked native ARC profile and real hash observer.
Three samples each cover 1,024 and 8,192 entries with 16-byte and 256-byte values. Sixteen sparse
single-key commits retain the last eight roots plus the separated initial root. Every key/value in
all nine complete maps is independently checked after journal replay, compaction and strict reopen;
a held pre-compaction view is checked again after file retirement and explicit owner close.

The suite records actual hash attempts and descriptive phase timing for publication, strict replay,
nine-map extraction, compaction and compacted-snapshot reopen. Selected node/file extents and one
occupied-memory observation with a retained reader are included. That observation is not peak RSS,
a complete reader-memory accounting, a disk-cache measurement or a performance threshold.

Physical and complete-trie ceilings are fixed in the authored fixture. These workloads neither
change production limits nor simulate device power loss. Full-map equality and unchanged strict
refusals remain prerequisites for any subsequent optimization; protocol/STF completeness and
light-state proof storage are outside this tranche.

Raw JSON belongs under the native runner's ignored evidence directory. Timing spread is descriptive;
deterministic counters identify candidate redundant work before an implementation is selected.

## Merged-code baseline

On macOS ARM64 with pinned Nimony `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, the checked
native profile produced identical counters in all three repetitions. For 1,024 entries, strict
compacted-snapshot reopen made 4,410 hash attempts with 16-byte values and 6,490 with 256-byte
values. At 8,192 entries those counts were 33,076 and 49,492. Nine-map extraction made zero
hash attempts in every case. Selected compacted snapshots were respectively 204,911, 454,511,
1,530,700 and 3,500,620 bytes.

Inspection identifies duplicate physical-record hashing: snapshot body decoding verifies each record,
then repository-image admission verifies the same owned records again. The next bounded experiment
will fuse decoding and graph admission inside the repository module. Serialized input must still
pass record integrity, canonical address/root order, full graph/routing, union reachability and all
original budgets. Public raw-image restoration must retain its independent validation.

## Fused serialized image admission

`decodeRepositoryImage` accepts serialized record-collection bytes plus generation, commitment and
root inventory. It verifies record shape, uniqueness, hashes and aggregate limits once, then calls
a private graph-admission helper with the exact same policy. No public flag/token permits skipping
integrity checks. Graph completeness, canonical record/root order, routing, selected metadata and
orphan rejection are identical to raw restoration. Public `restoreRepositoryImage` continues to
validate mutable raw records independently. Returned repositories own their records and do not
retain borrowed serialized bytes or mutable caller root arrays.

`storage_image_decode` compares real hash attempts (ten for decode plus raw admission versus five
for fused admission on a five-record union), all-prefix truncation and hash corruption, canonical
order, orphan and narrower-policy refusals, empty-current retention, continued publication and
1,000 ARC release cycles. Snapshot adoption is a separate dependent layer.
