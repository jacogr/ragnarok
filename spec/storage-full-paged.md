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

`src/storage/full/paged/codec.nim` implements format-only admission. The full header is one 4096-byte page:
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
below. Recovery, consumer adoption and full resource/crash panels remain open.


## Bounded graph engine

`src/storage/full/paged/stream.nim` supplies complete artifact admission and retained-root lookup through
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

`src/storage/full/paged/build.nim` builds complete artifacts from a synchronous sorted physical-record
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

`src/storage/full/paged/store.nim` adds move-only explicit-close `FullPagedReader` owners. Strict open decodes
only the full 192-byte CURRENT against an independent chain/root and bounded artifact geometry,
acquires an independent shared epoch pin, reads/binds the fixed header, admits the complete graph
with private anonymous scratch, rereads exact CURRENT and checks held identity before adoption.
Directory retirement occurs before exposing the reader. Each epoch owns its own parent descriptor;
readers retain no writer lease and owned lookup values survive reader close. One caller serializes
operations on each owner; independent readers provide independent native seek cursors.

`src/storage/paged/io.nim` shares only directory-relative native ownership/IO. Existing light CURRENT and
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


## Retained root unions and captured physical reclamation

An explicit replacement can retain multiple complete roots in one exact physical union. Shared
records are stored once; each root still receives independent route/topology/count validation.
Removing an old physical epoch does not remove a logical root retained by a newer union. Dropping
that root requires another explicitly authored complete replacement; subsequent readers report
UnknownRoot for the dropped root while independently pinned prior readers remain valid.

`epochReceipt` captures a reader's exact checked header/manifest, inode/version/namespace and all
15 inherited admission-policy scalars. It owns no pin or writer lease. `reclaim` accepts only a
captured strictly older epoch and exact current expected selection in the same namespace, chain
and policy. It completely verifies the held source, refuses unknown staging, opens an independent
exclusive nonblocking old-epoch pin, checks captured identity, fully verifies the old graph and
rechecks CURRENT immediately before unlink/directory sync. Busy readers, substituted inodes,
other namespaces and any policy change refuse. No directory scanning or inferred old root occurs.

Already absent retries recheck source and perform a real directory barrier. Uncertain unlink/
synchronization poisons the writer and requires strict reopen; successful absence reports old-file
retirement errors separately. Selected-epoch deletion and default/stale receipts are refused.
The `storage_full_paged_retention` suite covers complete shared-root history, exact64-root header
capacity/one-short policy, every independent policy field, live reader exclusion, logical history
after physical deletion, identical-byte inode substitution, cross-namespace receipts, all observed
cleanup IO faults and strict reopen/retry.1000 synchronized absence retries retain72,416 ->72,416
occupied bytes; admission authority and captured identity privacy rejections pass.

The existing seven-variable epoch-pin model also maps to the full implementation: graph admission
runs while the shared pin remains held, full publication uses guarded CURRENT rename and full
reclamation uses EX/current-check/unlink. Base16 states pass; removing either exclusive exclusion
or post-pin CURRENT equality produces a5-state violation; the retained-old-reader witness is
reachable with a5-state trace. Serial and four-worker results agree. Native tests exercise real
pin contention and retained readers; the model excludes hostile filesystems, proof/graph semantics
and power loss. No new integrated model or broader formal guarantee is claimed.


## Source-derived full compaction

`prepareFullPagedCompaction` takes no producer, root, count or history replacement. It derives
all target metadata from the held completely checked source, advances only physical epoch and
preserves ordinary generation even at its maximum. All complete retained roots, physical child
identities, canonical index/payload bytes and section padding survive exactly.

`compactFullPaged` checks that only epoch differs in the canonical header, then copies source
pages through captured-root authentication. Its global construction counters reserve every
fresh source-page fetch schedule (two EOF checks, page read, sibling reads and hashes) before
dispatch. It rebuilds the complete target digest tree, performs full graph admission under the
source's inherited policy and requires the final exact physical-record fingerprint to match the
source. Native sealing shares the same fresh-stat/error boundary as ordinary construction.
Compaction consumes no producer allowance; a zero producer quota remains valid.

The `storage_full_paged_compaction` suite verifies both cache modes, every target byte against
an independently rebuilt tree, exact/one-short global IO/hash/read/write quotas, changed epoch/
generation rejection, corrupted source page refusal, retained history/readers/reclamation and
maximum ordinary generation with no producer calls. Every observed native preparation IO failure
preserves the strict selected source.1000 actual compaction/publication cycles retain30,464 ->
30,464 occupied bytes. Ordinary publication and retention regressions pass after shared native
sealing and test-oracle extraction. Explicit prefix cleanup/bootstrap recovery remain next.

## Explicit replay cleanup and interrupted bootstrap

`prepareFullPagedCleanup` requires an exact independently expected current manifest and target
header. Ordinary replacement advances generation once; a same-generation target is reproduced
exclusively from the held authenticated source through compaction. No caller producer can change
same-generation graph knowledge. Complete target construction/admission occurs in anonymous disk
scratch before any partial epoch or `CURRENT.next` is captured. `replayBytes` is a separate explicit
native disk ceiling (zero denies replay); graph scratch remains independently bounded to2N bytes.
Construction/admission budgets remain separate; each prefix comparison has the configured finite
construction IO/read ceiling and holds at most two fixed pages. No resident graph is retained.

A move-only cleanup capability captures exact epoch/staging inode/version/extent or their absence.
Every prefix must match independently reconstructed full bytes. Full staging is at most192 bytes;
light-width and overlong prefixes refuse. Captured absence cannot authorize late-created files.
`discardFullPagedCandidate` checks original writer incarnation, exact source selection, source
complete graph, every captured resource and staging prefix before the first unlink. Complete live
seals can be discarded without replay. Failed staging comparisons remain failures on retry.
Uncertain removal/barrier IO poisons the writer; strict reopen and fresh replay are required.
Confirmed synchronized absence reports subsequent retirement errors separately.

`resumeFullPagedInitialization` requires an existing stable LOCK and absent CURRENT, including
refusal of malformed existing CURRENT. It completely replays independently expected epoch1/
generation0/root inventory, removes only matching captured prefixes, constructs afresh and requires
the entire new manifest to equal the replay witness before publication. There is no directory
scan, inferred head, automatic damaged-file repair or authority over an existing selection.

The selected `storage_full_paged_recovery` suite checks header/page/tree/checksum prefix boundaries,
zero/full prefixes, overlong and mismatched bytes, staging retry refusal, late-created paths,
replay disk denial, stale incarnations, source-derived compaction, write/rename bootstrap failures,
changed producer refusal and every observed preparation/removal read/write/flock/close/fsync/
unlink/ftruncate failure with strict reopen and fresh replay.1000 repeated capture/discard cycles
retain73,024 ->73,024 occupied bytes in the checked ARC profile. Process-death and populated Linux
working-set panels, followed by consumer integration, remain open.

## Explicit immutable epoch reopen

`openFullPagedEpochReader` shares the same complete-graph admission and independent shared-pin
path as strict CURRENT readers, but binds one independently supplied full manifest and expected
chain/root. It never reads a root or history identity from a directory scan. Explicit immutable
epoch reads do not follow CURRENT and need no current-selection race check: the exact file stays
pinned throughout complete admission and native identity checks. Strict `openFullPagedReader`
retains its original CURRENT capture/reread behavior. Neither API repairs any namespace entry.

A caller can persist/reconstruct its independently trusted manifest, retire every original owner,
then reopen that immutable epoch and capture a fresh passive `epochReceipt`. This permits safe
physical reclamation after process restart under the normal strict current writer and exclusive
old-epoch checks. It also permits explicit historical reads while newer CURRENT roots are selected;
missing or substituted epochs, wrong expected roots and default manifests refuse. An explicit
epoch reader never constitutes authority to replace CURRENT or infer a corrupted startup head.

`storage_full_paged_epoch_reopen` covers fresh owner incarnations, retained-root lookup, actual
shared/exclusive reclamation exclusion, owned value lifetime, new-current history after old-file
removal, default/wrong-root refusals and every observed read/write/flock/close/ftruncate admission
fault.1000 independent open/close cycles retain42,512 ->42,512 occupied bytes. Existing current
reader and retention suites remain regression controls for the shared admission path.

## Full process-death qualification

`storage_full_paged_crashes` uses the existing exact-child successful-syscall stop/SIGKILL harness
for bootstrap, same-root replacement, independently trusted new-root replacement, source-derived
compaction, explicit prefix cleanup, bootstrap resume and captured old-epoch reclamation. Real
short writes add stops inside body pages and digest words. Graph-scratch ftruncate boundaries are
included. Every stopped child must still hold the stable writer lease against an actual contender;
completion, timeout, ordinary failure and a genuine stopped/killed child are separate outcomes.

Independent complete-map fixtures define every expected full data/manifest byte before the child
runs. After death, CURRENT must be the exact prior or new manifest; new selections require the
entire target and no staging file. Old images, retained readers and an unrelated KEEP sibling stay
unchanged. Strict correct-root reopen makes no rename/unlink and leaves all fixed namespace bytes
unchanged; full admission legitimately writes private anonymous graph scratch. Wrong-root reopen
refuses without namespace changes. Only fresh explicit replay removes partial targets/staging,
and interrupted bootstrap resumes only while CURRENT is absent. No inferred head or broad cleanup
is permitted. Reclamation retry performs an actual directory barrier even after confirmed absence.

The final checked ARC/Clang macOS aarch64 panel passes39 completion controls and556 exact stopped-
child kill boundaries. The identical source also passes39 controls and556 exact kill boundaries on
Linux amd64 under Docker emulation on this aarch64 host. Source hashes are compared against the
qualification image; both profiles retain the pristine pinned compiler/provider and runtime checks. These tests establish implemented process-
death behavior only; fsync success and process death do not establish hardware/filesystem power-
loss qualification. Populated Linux working-set qualification and consumer adoption remain open.

## Populated Linux no-swap qualification

Make's build-storage-full-paged-resources target builds the checked ARC/Clang probe; the optional
full-paged-resources Docker target provisions the same pinned tools. With its image selected,
FULL_PAGED_STORAGE_IMAGE=<image> make bench-storage-full-paged-resources runs the strict panel.
The Python observer, compiler/provenance inspection and resident complete-map/reference artifact
construction remain outside pressure. Each measured writer uses one bounded on-disk descriptor/
record producer; no resident source map, graph or full index enters the measured native exec.
Each target is freshly authored inside one persistent private64MiB no-swap cgroup, preserving
selected-file cache charges through separate fresh reader processes. Input fixtures are read-only
inside pressure and fixed-buffer hashes verify them again afterward. No filesystem cache is dropped.

Four complete datasets exercise maximum depth248 (250 physical nodes), a shallow eight-entry map,
72 entries with1MiB values, and2048 entries with36KiB values/4148 physical nodes. Each retains one
present-empty final leaf. Every treatment inherits the same1MiB per-value,4096-entry/16384-node,
200MB artifact, one-root,16MiB logical-workspace and32KiB scratch policy; only page cache0/1 differs.
The largest two canonical selected artifacts are76,586,976 and78,180,320 bytes, each larger than
the67,108,864-byte enforced memory allowance. Independent complete-map roots are cross-checked
against the full trie, and an explicit-domain reference tree defines every selected artifact byte.
Writers/readers must match its exact data/CURRENT SHA-256; strict readers leave LOCK and all selected
bytes unchanged. Every reader verifies spread values byte-for-byte, present-empty, complete absence
and exact UnknownRoot refusal after complete graph admission.

All16 fresh writer/reader phases pass on Linux amd64 under Docker emulation on this aarch64 host.
Maximum native process peak RSS is17,608,704 bytes; retained Nim owner heap is exactly25,072 bytes
for writers and8608 for readers across all sizes/depths/cache treatments. Writers include the source
file in their five-descriptor live delta; readers retain two. Every native phase returns heap and
descriptors exactly to baseline. The persistent cgroup's largest observed memory.current snapshot
is66,293,760 bytes, swap max/current stay zero and final OOM/OOM-kill counters remain zero. The
memory-limit event counter reaches20,152, witnessing actual reclaim pressure. This kernel lacks
optional memory.peak; reports record null rather than inventing a cgroup peak. Process getrusage
peaks and actual cgroup max/current/swap/events remain mandatory. Complete source, compiler,
provider, observer and native binary identities are frozen and verified before/after execution.

These observations qualify the concrete storage profile and workloads above, including newly
charged selected-file cache. They do not establish a throughput result, deployment-wide ceiling,
resident StateStore/execution bound, complete JAM serialization or hardware power-loss durability.
The selected Python receipt controls reject false identity/geometry/depth, leaked heap/descriptors,
omitted graph work/queries and over-limit RSS. Full/light consumer integration remains open.

## Complete selected-root entry transport

Full reader rootInfo returns copied completely admitted per-root counts for an independently
selected retained root. It grants no chain/history trust and exports no mutable inventory.
visitEntries lends serialized-key-ordered values synchronously, with zero-based ordinals. Each
borrow ends at callback return; callers must copy retained output and stage it until the entire
operation succeeds. VisitorRefused is an explicit consumer refusal, distinct from file corruption.

The stream walks only the captured complete graph through authenticated record/index reads.
Its fixed-depth traversal rechecks routed keys, node/entry/value totals, subtree cardinality and
final source extent. Complete prior admission and immutable captured-root reads exclude cycles/
repeated subtrees, so this readonly walk needs no second visited table, disk scratch or resident
index. Native file identity and shared pin checks remain active. Per-call IO/hash/visit/read/write
ceilings can only tighten inherited policy; a zero IO ceiling refuses before source or visitor
dispatch. Partial callback delivery never produces a successful whole-stream receipt.

The storage_full_paged_entries suite covers selected/historical root separation and key order,
empty roots, present-empty/cross-page values, depth248/250 nodes, owned callback copies, default/
unknown roots, callback refusal, exact and one-short work limits, every observed source callback
and native read failure, strict reopen after poisoned IO and zero native writes/scratch creation
during streaming.1000 consumer capture/release cycles retain51,120 ->51,120 occupied bytes. The
ordinary graph suite remains a regression control. The strict resource probe additionally walks
every selected map entry byte-for-byte and records its complete count in a version2 native receipt.

The version2 Linux panel passes all16 fresh phases with complete entry walks of every dataset
under both cache settings, including the76,586,976/78,180,320-byte files in the same64MiB no-swap
group. Maximum native RSS is18,141,184 bytes; retained writer/reader heap remains25,072/8608 bytes
across every size/depth/cache case and every heap/descriptor sample retires exactly. Each open
receipt records2,8,72 or2048 streamed entries as appropriate. Swap and OOM/OOM-kill counters remain
zero; actual reclaim-limit events reach23,245. Source/provider/binary and exact selected-file
identities are reverified. The same optional-kernel-peak and concrete-profile limitations apply.

## Full StateStore consumer transport

The state-layer paged_state module prepares complete existing StateStore snapshots for the full
paged backend and restores ordinary resident stores from a checked root. PagedStateLimits bound
input snapshots, aggregate staging records/value bytes before deduplication, and final unique
artifact geometry separately. All retained snapshots must share the selected snapshot's exact
complete-map/mutation policy. Metadata/count preflight precedes exported byte/record allocation.
Complete hashes sort the physical union; duplicates require equal complete physical fields.
Repeated logical roots must agree in every complete-map count.

PreparedPagedState owns private immutable detached transport and retains no original map, native
owner or callback. Copied root claims and mutable producer outputs cannot modify its backing.
Its owned producer can be used for explicit native replay cleanup after source maps retire.
Initialization requires the independently selected native root to match the prepared complete
snapshot. Replacement requires exact expected source manifest bytes. These helpers keep native
writer/candidate retirement caller-owned, including failed acquired owners and forensic candidates.
Confirmed publication receipts retain their separate retirementError/writerUsable diagnostics;
a post-confirmation close error never becomes an ambiguous publication failure.

restorePagedStateStore preflights copied root counts against independently selected StateStore
limits, stages owned entry copies, requires successful complete streaming, constructs an ordinary
StateStore and recomputes its complete-map commitment against the caller's expected root. No
partial map escapes failure. Retained roots and an empty selected root over nonempty history restore
independently. Restored snapshots/forks preserve existing sorted iteration, present-empty values
and immutable lifetime after every native owner closes. The consumer does not implicitly mutate
an application memory head: build a private target, prepare/publish the native candidate, then
adopt memory only after confirmed publication.

This transport intentionally materializes bounded resident records and complete maps under caller
policy. Its memory contract is separate from the native storage-only64MiB qualification. The full
V1 paged selection also contains no application checkpoint/head/history context binding; automatic
disk-chain startup/layout flags remain a separate open integration item. Existing context-required
application storage paths are unchanged. This is complete provided-map transport, not completion
of JAM state serialization or whole-client parity.

The paged_state suite covers independent complete roots, record/root deduplication, policy/staging/
image quota refusal, detached producer outputs, full root replacement, historical/empty restoration,
ordinary retained memory views/forks, unknown roots, every observed native consumer read failure,
strict reopen and every initialization close boundary including confirmed retirement diagnostics.
1000 prepare/restore/release cycles retain52,016 ->52,016 occupied bytes. Existing StateStore tests
pass; compiler controls reject private transport/result fields and partial ProofView-as-full input.

## Light proof-view consumer

The separate state-layer paged_proof_view consumer accepts only PagedReader and an independently
supplied expected root. readPagedProofView extracts the explicitly requested bounded witnesses,
recaptures canonical node/value transport as state-layer proofs, re-verifies every proof under
that expected root, and constructs an ordinary immutable ProofView. Storage verified lookups and
state verified lookups remain distinct nominal types; no cast or complete-map conversion grants
state authority. The result retains no native owner or callback and survives root advancement
and reader/writer closure.

PagedProofViewLimits separately bound query descriptors, per-proof nodes/value bytes, aggregate
batch nodes/value bytes, retained view values and finite native work per requested query. Batch
sums are checked before state proof copying. Duplicate queries and mismatched expected roots
refuse before native lookups. Native readProof authenticates the same disk search and proof as
ordinary lookup, then retains raw evidence alone; its guarded proof getter returns independent
mutable transport arrays. Ordinary lookup retains verified values alone. Admission retires raw
transport before allocating its separate canonical replay buffer, preserving the existing native
working reservation. Consumer staging and retained ProofViews have their own explicit memory
policy, separate from storage-only working-set qualification.

Unknown stored queries produce MissingWitness, including a later missing query after earlier
successful extraction. A proven absent query produces an ordinary absent verified lookup;
a present-empty value remains present. Every failed batch withholds its entire private prefix.
Native IO/proof corruption keeps its selected native cause rather than becoming a missing witness.
The consumer does not change light logical-head selection, checkpoint trust or application startup.
Full and light native readers remain incompatible at compile time; partial ProofViews cannot
satisfy complete StateStore snapshot transport.

The paged_proof_view suite covers exact/one-short independent quotas, unsorted requests,
duplicate and wrong-root preflight, empty batches, missing evidence versus proven absence,
present-empty values, detached proof mutation, retained old/new root views, default/closed readers,
every observed native source read failure with strict reopen after poison, and1000 capture/release
cycles with equal warmed occupied heap. Compiler controls cover private proof/result backing and
full-reader-as-light rejection. Existing paged native/stream/cleanup and ordinary state ProofView
suites are regression controls. The Linux native resource probe now also extracts and compares
complete raw witness bytes for spread/cyclic queries and the present-empty witness under the
same64MiB no-swap boundary; the complete consumer's retained views remain a separate contract.

This fifteenth layer reaches the requested stack cap. Automatic paged application startup still
needs an agreed checkpoint/head/history context binding and layout selection flags. The V1 paged
selection does not supply that context, so these SDK consumers do not close that integration gap.
Hardware/filesystem power-loss qualification and complete JAM serialization remain the later
ordered work; none is claimed by this stack.

The extended Linux amd64 resource panel passes all8 fresh writer/reader phases for16,384 and
327,680 stored witnesses, with cache0/1, in one fixed64MiB no-swap group. The larger selected file
is78,458,848 bytes. Maximum native RSS is13,737,984 bytes; retained writer/reader heap remains
10,480/1168 bytes across every size/cache case, and every heap/descriptor sample retires exactly.
Swap and OOM/OOM-kill counters remain zero; reclaim-limit events reach6,615. The frozen source,
provider, binary and selected-file identities are rechecked. This qualifies this concrete native
storage profile including raw-proof extraction, separately from resident state consumer retention
and hardware/filesystem power-loss behavior.

## Restart-safe expected-manifest retirement

`reclaimExpectedEpoch(writer, previous, expected)` takes independently authenticated previous
manifest content and the exact expected CURRENT manifest. It never discovers an old epoch by
scanning names. The previous selection must match the configured chain, finite dataset policy
and explicitly selected V1/V2 schema, have an older physical epoch and no newer ordinary
generation. Current/new/default selections and malformed bindings refuse deletion.

The held writer lease, complete current graph, exact CURRENT and absence of pending publication
are checked before retirement. A present old epoch requires an exclusive nonblocking pin,
header/manifest binding, complete old graph admission, and fresh current/name/inode checks
before unlink and directory synchronization. Foreign readers produce Busy without deletion.
Exact absence is idempotent only after fresh current checks and a real directory barrier.
Confirmed removal remains successful with a separately exposed final close diagnostic; an
unconfirmed namespace/barrier failure poisons the writer until explicit reopen.

This content authority permits a byte-identical replacement inode after restart. Existing
`reclaim` with a captured reader receipt retains its stronger original-inode, namespace and
policy requirements. Neither API grants deletion authority from plausible directory contents.
The new native suite covers both formats, foreign pins, wrong content, equal-byte replacement
inodes, payload corruption, each observed read/scratch/lock/close/unlink/synchronization failure,
and exact restart/retry. Checked macOS ARC evidence is 1,000 idempotent retries at
51,440 -> 51,440 occupied bytes. This is not hardware power-loss evidence.

The new expected-retirement and existing captured-receipt retention suites also pass checked
Linux amd64 under Docker emulation. The new suite records the same 1,000-cycle
51,440 -> 51,440 ARC evidence. Qualified image:
sha256:2eb52334835215e77b0f888f9fd476ef9529efb755c5d1ce2b0f9d8115fa1a6d.
Frozen source hashes and native evidence: build/storage-db5-retirement-linux.json.
