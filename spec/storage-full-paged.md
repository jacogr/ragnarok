# Full-node paged storage and subsequent light adoption

## Authorization and order

The maintainer authorized db #5 on 2026-10-24 to implement paged storage for full nodes,
followed by light adoption, in one native stack of at most 15 PRs. This explicitly authorizes
storage internals and the minimal state/application consumer changes needed by that integration.
It supersedes the storage isolation gate for this tranche only. Existing StateStore consumers,
checkpoint trust and independent workstream interfaces must remain compatible. Hardware/filesystem
power-loss qualification follows this tranche; complete JAM state serialization follows that.
Neither later item is part of this stack.

The merged light-evidence paged backend is the baseline, not a full-state graph implementation.
See [its contract](storage-paged-working-set.md). The complete-state physical record semantics
remain those of [the physical repository](storage-trie-node-layout.md) and the pinned JAM state
layout. M1 framing completion is distinct from complete JAM serialization and whole-client parity.

## Required behavior

Full storage admits a complete, independently root-bound physical graph and an explicit retained
root union. Missing reachable records are corruption. Protocol absence is established only by a
complete checked route. Light storage continues to distinguish unknown evidence from authenticated
absence; neither a local miss nor a partial light root can satisfy the full-state interface.

Full and light databases have distinct versioned identities and directories. Reopening the wrong
mode, chain or schema refuses before adoption. Startup selects mode independently from memory/disk
backend. Existing journals and checkpoint files are not silently converted. Explicit conversion
must verify the complete source, exact chain/root/generation, destination and selected-byte result;
it confers no external checkpoint trust.

## Physical format and admission

A new full-state format preserves all 32 bytes of each physical child identity, including the
left child bit masked by JAM B. Physical hashes are sorted strictly, with one canonical index row
per record, contiguous bounded spans, exact EOF and canonical zero padding. Leaf records retain
all 31 key bytes and the exact value, including empty values. Branches retain both full edges;
zero names an empty subtree. Unknown tags, duplicate hashes, noncanonical unused fields, overflow,
trailing bytes and hash mismatches refuse. Full format/domain bytes are distinct from light V1.

Selected metadata binds chain, physical epoch, ordinary repository generation, selected complete
root, exact retained-root inventory, logical counts, physical extent and artifact integrity.
The caller supplies expected chain/root independently. Local checksums never supply chain trust.
A checked header or individually valid record is not complete-graph authority.

Strict admission scans the complete physical artifact and validates every retained root. Each
nonzero edge resolves by the full physical hash; each record's JAM hash is independently recomputed.
Every leaf follows the exact MSB key prefix; maximum depth is 248. No cycles or repeated physical
subtrees within a root are accepted. Singleton subtrees collapse; a branch represents at least
two leaves. Per-root entries/nodes/value totals are checked, not trusted from disk metadata.
Shared records between retained roots are permitted. Every stored record must belong to the exact
retained-root union; unreachable historical garbage is refused in a selected compact artifact.

Traversal uses a fixed depth-bounded stack. Per-root visitation and retained-union membership
reside in explicit bounded disk scratch, never an O(N) resident bitmap, node table or hash set.
Scratch is disposable private workspace, cannot select a root, cannot outlive its operation and
has a separately admitted extent. Every scratch read/write and reset participates in finite work
budgets. Scratch failure preserves the selected source and exposes no partially checked artifact.

No map-sized allocation, mmap of the whole dataset, full-file read, implicit index preload or
resident graph is allowed on the bounded open/read path. A bounded record/value transfer may
scale only with an explicitly admitted per-value ceiling. Dataset size, working bytes, page-cache
slots, retained roots, scratch extent, IO calls/bytes and hashing/traversal work have independent
finite policies. Unsupported cache policies refuse rather than silently allocating a larger cache.

## Construction, reads and publication

Construction borrows a replayable sorted producer, or streams a held checked source, under explicit
quotas. Replayed bytes and full child identities must agree; equal protocol roots alone cannot
establish equal physical data. No producer/callback is retained. Candidate handles bind the exact
writer incarnation, source position, target metadata, file identity and admitted policy.

Read views own independent immutable epoch pins and survive publication or writer close. Lookups
return owned values. Sorted iteration and proof/export adapters must stream under quotas and retain
the original owner through completion/cancellation; detached roots do not grant extraction rights.
Full state adapters preserve their existing atomic mutation, fork, history and empty-value semantics.
Any operation that explicitly materializes a complete execution map states that memory boundary;
that path cannot be reported as bounded-memory full-node execution.

Publication holds the stable writer lease, completely validates the target, synchronizes its file,
stages and synchronizes the exact selection, rechecks the source, atomically renames CURRENT and
synchronizes the directory. Before confirmed selection no target receipt is returned. Uncertain IO
poisons the writer until explicit close/reopen; confirmed selection is reported separately from
later descriptor-retirement or reclamation failures. Readers pin before validating selection and
reread CURRENT to exclude selection races.

Replacement, retained-root changes and physical compaction have explicit source/target positions.
Compaction preserves ordinary generation and exact logical knowledge. Reclamation uses captured
identity, an exclusive old-epoch pin, full validation and a fresh CURRENT check. No broad directory
scan, inferred corrupt-head recovery or automatic deletion of unknown staging files is permitted.
Explicit interrupted-build cleanup requires exact replay/prefix evidence; uncertain cleanup needs
fresh capture after reopen. Initial bootstrap recovery has no authority over an existing CURRENT.

## Review units and completion evidence

The stack begins with this contract, then coherent implementation units covering full physical
codecs, bounded streamed construction/admission, native publication and retained readers, updates/
compaction/recovery, and full consumer adoption. Full process-death and populated working-set
qualification accompany those behaviors. Light consumer adoption follows using the already merged
light backend. Layer count is a cap, not a requested count: supporting tests/docs stay with their
implementation, and each ready substantive layer is published before beginning the next.

Required evidence includes independent complete-map roots and physical-child witnesses; malformed
headers/indexes/records; absent children; left-bit aliasing; wrong routes; repeated/cyclic/unreachable
graphs; multi-root sharing; empty roots/values; exact and one-short quotas; changed replay; retained
readers/forks; stale/incarnation substitution; actual IO fault and process-death boundaries; fresh
strict reopen; and complete retirement of owned heap, descriptors and scratch. Hostile tests must
rehash/reseal local bytes where necessary so integrity checks cannot hide graph-validation defects.

Native checked ARC/Clang builds retain assertions/bounds and pristine pinned dependencies. Actual
lowering verifies move-only/resource privacy contracts. Make owns setup and selected suites. A
fresh-process Linux panel must construct and reopen populated data larger than an enforced no-swap
memory limit, measure native process/cgroup use and preserve exact source/provider identities.
Logical workspace accounting alone is insufficient. Consumer tests cover mode/schema separation,
unknown versus absent, startup refusal/close and existing complete-state behavior. Process death
and successful fsync receipts do not establish device/filesystem power-loss durability.

## Current status

`full_paged_codec.nim` implements format-only admission. The full header is one 4096-byte page:
32-byte zero-padded magic, chain at 32, epoch/generation at 64/72, selected root at 80,
record count/payload extent/root count at 112/120/128, eight reserved zero bytes, then at most
64 strictly root-sorted 56-byte claims (root, entries, nodes, value bytes) from offset 144.
All remaining bytes are zero. Root inventory is fixed-capacity; unsupported larger histories
require an explicit future format rather than implicit allocation.

Each 64-byte index row stores complete hash at 0, payload-relative offset/length at 32/40 and
sixteen zero bytes. Payload records preserve the physical repository wire fields: tag/hash/key/
length/value for leaves (72 fixed bytes), tag/hash/full-left/full-right for branches (97 bytes).
Every record is locally JAM-hashed; physical left-bit aliases remain distinct transport bytes.
Shared light geometry is arithmetic-only, with a stronger 72-byte minimum full-record extent.
Page leaf/padding/internal hashes use separate FULL-PAGED V1 domains. Full CURRENT is 192 bytes:
32-byte magic, chain/root, epoch/generation, data pages/exact EOF, page root and BLAKE2b-256 of
its preceding 160 bytes. No light schema or digest gains full artifact authority.

The selected `storage_full_paged_codec` native suite verifies independent fixed-offset bytes,
all header truncations and trailing reserved bytes, exact/one-short geometry/value quotas,
strict/sticky index coverage and ordering, every manifest-byte corruption, primitive failure,
empty/long values and complete physical left-bit retention. This is format evidence only.
Complete-graph admission, native readers/construction/publication are implemented by the units
below. Retention/recovery, consumer adoption and full resource/crash panels remain open.


## Bounded graph engine

`full_paged_stream.nim` supplies complete artifact admission and retained-root lookup through
synchronous borrowed byte callbacks. Checked metadata retains only the fixed header, captured
page root and inherited policies. Every stored postorder digest is checked; subsequent index/
payload reads authenticate complete pages against that captured root. Strict ordering/coverage,
canonical section padding and every record hash precede complete graph traversal.

The first engine supports zero/one cached page and a conservative 4 MiB fixed logical workspace
reservation plus four per-value transports. This is an admission bound, not an RSS measurement.
Per-root seen and retained-union membership use two byte-addressed N-byte disk scratch tables.
Both are explicitly initialized; only seen is reset between roots. An exact2N-byte disk
ceiling succeeds; one byte less refuses before scratch access. Final union membership must
cover every physical record. IO/hash/visit/byte quotas charge before work; source/scratch EOF
are rechecked at successful completion. Scratch is private disposable trusted IO, never authority
for a selected head, and its exact extent must be independently admitted before traversal.

The selected `storage_full_paged_graph` suite uses an independent domain/tree byte oracle and
reseals locally valid hostile graphs. It covers wrong routes, repeated subtrees, missing full
children including masked-bit aliases, unreachable records, lying counts, multi-root sharing,
empty graphs/values, cross-page values, unknown roots, owned lookup bytes, exact/one-short work
ceilings and every observed source/scratch callback refusal. Checked ARC retains exactly
21,712 bytes before/after 1000 admission/lookup cycles in the small fixture. Native readers, construction and publication are implemented below; populated Linux resource
qualification remains subsequent work.


## Replay-bound construction

`full_paged_build.nim` builds complete artifacts from a synchronous sorted physical-record
producer. Pass zero writes the bounded index, pass one writes canonical record transport;
a private chained fingerprint binds every complete physical byte across both passes, including
JAM-masked left bits. Explicit end markers, exact count/coverage and output EOF are mandatory.
Fixed-page buffering adds canonical padding, then a fixed-depth postorder pass rereads completed
body pages and appends all full-format digests. Final complete graph admission is mandatory;
failed replay or graph admission exposes no checked candidate and leaves only forensic bytes.
Admission also fingerprints the exact authenticated on-disk record stream; construction compares
that fingerprint with both producer passes before granting a checked artifact. Equal JAM roots
never substitute for exact physical replay. Construction producer/IO/hash/read/write budgets
are separate from admission work budgets.
Dataset, scratch, resident policy and complete output extent are checked before authoring.

`storage_full_paged_build` compares every output byte with the independent complete-tree oracle,
rejects failed/early/late producers and valid same-root physical alias substitution, checks every
one-short construction quota and every observed output callback refusal (including partial failed
appends), and retires all closures/bytes/scratch after 1000 cycles (54,480 -> 54,480 occupied bytes).
The shared test-only byte/tree oracle lives in `tests/support/full_paged_reference.nim`; it is
resident reference material, not the production bounded path. Native ownership and publication are implemented below; consumer adoption remains open.


## Native full-state readers

`full_paged_store.nim` adds move-only explicit-close `FullPagedReader` owners. Strict open decodes
only the full 192-byte CURRENT against an independent chain/root and bounded artifact geometry,
acquires an independent shared epoch pin, reads/binds the fixed header, admits the complete graph
with private anonymous scratch, rereads exact CURRENT and checks held identity before adoption.
Directory retirement occurs before exposing the reader. Each epoch owns its own parent descriptor;
readers retain no writer lease and owned lookup values survive reader close. One caller serializes
operations on each owner; independent readers provide independent native seek cursors.

`paged_io.nim` shares only directory-relative native ownership/IO. Existing light CURRENT and
append-only writer scratch entry points retain their exact width and policy. Full graph scratch
uses a separate private random-write anonymous descriptor, a bounded signed `ftruncate` extent
and explicit graph-engine initialization. No database scratch name, selected-file truncation,
resident index or callback escape is introduced. A failed scratch retirement prevents reader
adoption. Native source identity/EOF checks remain active on every authenticated read.

The selected `storage_full_paged_readers` suite verifies independent native bytes, full-graph
refusal despite valid record/page hashes, full/light width separation, expected-root refusal,
independent shared pins versus an actual exclusive open, move transfer and lookup lifetime.
Every observed native read/write/flock/ftruncate/close failure refuses adoption; EINTR controls
retry only idempotent still-owned operations.1000 complete open/read/close cycles return occupied
heap from54,544 to54,544 bytes. The pristine compiler's top-level-defer limitation is avoided by
procedure-scoped test cleanup. Writer publication, mutation/retention and crash/resource panels
remain subsequent work; reader admission alone claims no durability receipt.


## Native full-state publication

`FullPagedWriter` owns one stable writer lease and a shared selected epoch pin. Initialization
starts at physical epoch1, ordinary generation0 and a caller-selected complete root/inventory.
Explicit complete replacement advances epoch and ordinary generation once. New-root trust is
an independent caller argument; no destination root or retained history is inferred from bytes.
The same inherited graph policy always governs source, authoring admission and target validation;
construction work ceilings are separate scalar limits in the native configuration.

A move-only `FullPagedCandidate` binds its exact source manifest, native file/version and original
writer incarnation. Preparation completely admits the held source, constructs and fully validates
the target, then synchronizes its file and directory before sealing. Failed authoring retains its
forensic prefix and explicit close obligation. No failure automatically removes a database file.

Publication checks live incarnation/source bindings, completely revalidates source and target,
captures target identity, stages/fsyncs/closes CURRENT.next, rechecks source/target, renames CURRENT
and fsyncs the directory. Uncertain publication returns no new selection receipt and poisons the
writer until close/reopen. Once selection is confirmed, candidate/old-head retirement and shared
new-head adoption report separately in `FullPagedPublication`; its new selected root remains
confirmed when `writerUsable` is false. Shared adoption must match the exact captured target
inode/version. Independent old reader pins and owned values remain valid after publication.

`storage_full_paged_publication` qualifies normal bootstrap/root replacement and strict reopen,
writer/candidate moves, stale writer incarnation, full-width epoch/generation exhaustion before
any hashing, every observed bootstrap and publication read/write/fsync/rename/flock/ftruncate/
close fault, old-or-new strict recovery and post-confirmation retirement diagnostics.1000 strict
writer/reader lifetimes retain42,208 ->42,208 occupied bytes; an additional1000 actual publications
retain their warmed occupied memory exactly while an old reader stays pinned. Physical epochs
are deliberately left forensic/retained in this layer; captured reclamation and explicit replay
cleanup follow. These OS barrier receipts do not establish hardware/filesystem power-loss durability.
