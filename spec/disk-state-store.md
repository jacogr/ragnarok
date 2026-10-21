# Disk state storage

The maintainer authorized disk storage, including application backend selection, on 2026-10-21.
db #1 owns storage and StateStore persistence APIs; state #5 independently owns checkpoint recovery
and startup. GP 0.8.0 and existing compiler/crypto pins remain unchanged. Full/light mode and
memory/disk backend selection are independent. This feature does not implement partial light state.

## Snapshot transport

StateStore exports bounded full/delta physical records directly from its immutable cached trie.
Exports copy raw bytes, grant no authority over the source, and require no cryptographic work.
Default snapshots refuse export; limits preflight descriptor and payload allocation. A disk owner
must authorize exact snapshot identity before using a delta: equal roots alone grant no authority.
Repository restoration can extract detached complete leaves under an independently trusted root
without building an intermediate trie. This avoids reconstructing and hashing a second temporary
trie before constructing a StateStore. Returned leaves remain mutable transport values only.

## External design references

- [Firewood](https://github.com/ava-labs/firewood): physical addresses separate from Merkle hashes,
  explicit retained revisions, and data durability before root publication.
- [NOMT](https://github.com/thrumdev/nomt/blob/master/docs/nomt_specification.md): path-derived page
  identities and subtree packing reduce dependent reads.
- [ParityDB](https://github.com/paritytech/parity-db): atomic batches and distinct visible/durable
  stages, with OS page cache and separate metadata columns.

These sources inform design tradeoffs; no foreign node encoding, dependency or license-bearing
implementation is copied. Our journal remains the correctness baseline. Layout/cache/reclamation
changes require reproducible measurements and recovery tests; no throughput claim follows from
fewer encoded bytes alone. Canonical block authority cannot be inferred from a locally valid root.

## Durable StateStore owner

`state/disk_store.nim` owns one explicit-close, noncopyable `FileRepository` and an ordinary
in-memory `StateStore`. Creation requires an explicit complete snapshot and exclusively creates
the journal. Strict reopen requires independently supplied chain, root and exact local generation,
then constructs one StateStore from checked reachable leaves under explicit caller-selected policy.
No self-authentication, implicit repair, truncation, default database or policy widening occurs.

Updates fork the current immutable snapshot privately, validate/apply the borrowed batch, export
only changed physical nodes, and append/synchronize the journal before replacing the live memory
snapshot. Empty batches retain identity without a frame. Successful nonempty no-ops publish a new
snapshot and a journal generation. Native IO uncertainty poisons the journal: new reads/writes
refuse until close and explicit trusted recovery; already retained snapshots remain readable.
Failed initialization/open releases its lock, preserving any created bytes for explicit diagnosis.
Normal forks remain independent in-memory execution branches, never duplicate descriptor owners.

This first owner exposes durable state revisions only. It is not yet wired into normal application
adoption, canonical block metadata or a startup flag. Those require atomic publication of the
matching application context and coordination with state #5's startup/recovery layer. A successful
storage receipt cannot silently advance the application head or choose consensus authority.

## Publication failures and explicit recovery

`recoverDiskStateStore` wraps the existing independently trusted prefix repair; ordinary open
never repairs. Tests constrain actual child-process writes with `RLIMIT_FSIZE`: zero bytes, one
byte, half a frame and one byte short must fail; exact and ample ceilings are genuine controls.
Poisoned owners refuse new reads, updates and synchronization while held values remain readable.
Strict open preserves incomplete bytes. Wrong trusted generations preserve every byte. Authorized
repair restores the exact complete prefix, permits resumed append, and refuses complete visible
successors or complete checksum corruption. Repair may already be durable if subsequent policy or
cryptographic StateStore restoration fails; no writable owner escapes that later failure.

A separate maintained-crypto-observer suite refuses each required hash stage before update
publication. Every refusal preserves journal bytes, generation and exact old snapshot identity;
the same workload also completes with real successful controls.

## Reproducible real-file workload

`make measure-disk-store` runs the identical 128/1024-key, 33-byte-value workload ten times,
performing 64 deterministic sparse updates, retaining one/eight snapshots and strictly reopening
the result against its independently calculated complete root. Every restored key/value is checked.
Counter samples must agree exactly; source/compiler/crypto/profile/host identities are recorded.
`DISK_STORE_BASELINE=path/to/results.json make measure-disk-store` compares compatible prior
reports. Python tests reject malformed, partial, duplicate, incompatible and unstable observations.

The measured update region includes actual commitment, export, physical admission, frame encoding,
append and synchronization. Full-frame reference encoding and independent root checks are outside
that region. Monotonic publication/reopen durations are stored separately from exact counters;
process duration additionally includes fixtures and reference work, so is not update latency.
Occupied ARC bytes are live observations after completed updates, not internal transient allocation
peaks, allocation counts or RSS. This benchmark does not claim power-loss behavior or production
throughput from synthetic authored mappings.

Initial checked macOS ARM64 baseline, all ten counter samples identical:

| Complete keys | Held snapshots | Update hash calls | Journal bytes | Equivalent full-frame bytes | Maximum observed occupied bytes |
| --- | --- | --- | --- | --- | --- |
| 128 | 1 | 1984 | 92272 | 1690672 | 293568 |
| 128 | 8 | 1984 | 92272 | 1690672 | 402800 |
| 1024 | 1 | 3520 | 471823 | 23133327 | 2311536 |
| 1024 | 8 | 3520 | 471823 | 23133327 | 3037216 |

The equivalent full-frame total is a byte-size reference, not a second database benchmark or a
claim that it fits the configured total-journal budget. Delta persistence uses 98.0% fewer bytes
in the 1024-key workload. The current accumulated sorted record table still copies all descriptors,
sorts them on every append and walks the entire target graph. No disk-addressed paging, bounded
read cache, automatic history reclamation or production-scale efficiency is claimed yet.

## Sorted-index admission

Publication now sorts only newly admitted addresses and linearly merges them with the already
sorted immutable table. Existing full-address conflict checks, complete graph validation, budgets,
failed-publication atomicity and raw byte ownership remain intact. Mixed full/delta transports,
reversed record orders, reused addresses, zero-record revisions and held historical readers are
checked independently. Descriptor copying remains O(history); new-record sorting uses O(delta)
scratch instead of the pinned mergesort's O(history) temporary buffer.

The fixed candidate's ten deterministic samples exactly match the baseline bytes, hash calls and
post-update occupied memory. Ten alternating baseline/candidate runs also agree on every exact
counter. For 1024 entries, publication median totals across 64 updates changed from 51.5/49.5ms
to 42.7/42.6ms for retention one/eight; reopen medians changed from 43.0/42.8ms to 37.5/38.3ms.
Outliers overlap substantially on this shared host. This supports retaining the simpler asymptotic
sorting improvement, not a production latency promise or a claim of reduced post-update live memory.

## Normal restart authority

The maintainer selected local durable-head resume for normal disk-mode restarts: verify configured
chain identity and physical integrity, then resume the app's own previously validated durable head.
External checkpoint imports still require independently supplied trusted application identity and
sealed header. Persisted state root/generation alone is insufficient application context; disk mode
must atomically select matching block identity, sealed header, full parameters and state revision.

## Atomic contextual frames

The separate `RAGNAROK-FULL-STATE-V1` database schema uses frames containing E8 body length,
E8 nonzero local generation, E8 context length, bounded raw context, the existing strict record
batch and a Blake2b-256 checksum covering every preceding frame byte. Both identity domains have
fixed equal extents; callers explicitly select a schema. Existing `FULL-NODES-V1` bytes remain
unchanged. There is no format guessing, conversion or cross-schema fallback.

Context ceilings and exact borrowed extents are checked before checksum work or transport
allocation. Truncation, every single-byte mutation, huge lengths, exact/short budgets and schema
cross-decoding are exercised; a frozen independent Python struct/hashlib checksum covers the
combined generation/context/record representation. Application decoding remains responsible for
validating context semantics and its match to the selected complete root.

## Contextual file publication

The existing explicit-close file owner accepts an explicitly selected physical schema and an
independent context-byte ceiling. Contextual frames restore the selected context only after node
graph admission succeeds. Publication copies context before append and replaces context and node
head only after successful synchronization; new context reads refuse on poisoned owners. Returned
contexts are detached and remain owned after close. Node-only owners refuse nonempty context.

The real kernel write-limit matrix also runs through contextual frames, proving old context
survives refused/partial publication, exact/ample writes select the new context, trusted repair
retains the matching complete prefix, and node-only open refuses the contextual database identity.
Dedicated budget and input/output mutation cases check metadata ownership independently.

## Local application-head context

`app/disk_head.nim` encodes exact chain identity, nonzero journal generation, existing full
ApplicationCheckpointIdentity and one exact sealed-header extent. The enclosing contextual frame
checksums all fields. Restore compares configured chain/profile, frame generation and complete
posterior map before structural capture, then verifies exact block identity/time/root/profile.
It retains the same StateStore snapshot and reconstructs one unfinalized anchor. Header prior-state
root is never substituted for posterior state root. This codec is a local restart path, not an
external checkpoint import certificate or seal/consensus verifier.

Tests preserve exact snapshot ownership and encoding roundtrips, and refuse wrong chains, complete
profiles, posterior maps, generations, sealed headers, truncated contexts and oversized extents.
Historical/finality persistence beyond the selected anchor remains a separate explicit contract.

## Prepared snapshot commit and local reopen

DiskStateStore can durably commit an already prepared snapshot without repeating state execution
or changed-path hashing. It requires the exact current parent owner and equality of all six
complete-map/batch ceilings. Root-equal foreign parents and any policy change refuse before IO.
Contextual owners require explicit nonempty context for creation/commit and refuse bare mutation
batches that would erase the application head. A new context may select unchanged state while
still consuming a durable generation. Ordinary node-only apply uses the same prepared commit path.

Local reopen explicitly selects only the contextual schema and the maintainer-authorized local
restart trust policy. It strictly checks identity, complete journal/graphs and a rebuilt state root;
application adoption must additionally validate the selected context against configured chain/profile.
External trusted-root/generation open and explicit repair retain their existing independent trust
contracts. Tests change each inherited ceiling independently, reject foreign parents/context budgets,
preserve exact prepared identity and verify context/generation across local restart. Existing hash
failure and real partial-write recovery suites pass through the refactored node-only path.

## Opaque canonical preparation

`state/accumulation_publication.nim` runs the unchanged accumulation coordinator on private state
and history handles. A successful opaque update retains the exact original parent snapshot and
entire original ordered view, plus its private successful successor. Installation checks exact
owners, complete profiles, retained history and finality before durability; a guarded final install
only assigns existing handles and performs no composition, hashing or callbacks. Stable owners and
single-threaded exclusion must span preflight, durable commit and installation.

Genuine signed execution fixtures prove failed preparation leaves live owners unchanged, alternate
finality/default preparations refuse installation, old aliases remain intact, and valid installation
still succeeds with all hashing disabled and zero observed hash calls. Explicit parent finality is
preserved. Compiler checks reject candidate-field and result-payload access.

The maintainer selected preservation of the bounded retained history and explicit finalized block
for normal local restart. The single-head context codec above is a building block; final disk-chain
context must retain those additional bindings. External checkpoint imports keep their separate
single-head/unfinalized behavior.

## Canonical/RPC prepared installation

Application and RPC adapters share the opaque prepared update without circular imports. RPC
preflight requires an open listener, exact full history/finality agreement and either no active
lease or the exact caller-held exclusion token. Installation replaces canonical state, application
history and RPC history before bounded subscriber work; it does not repeat state execution or
header capture. An explicit lease remains held until its owner resumes RPC. Subscriber validation
or queue overflow keeps existing client-retirement semantics and cannot roll back the durable head.

The real WebSocket application suite now prepares a genuine source once, refuses missing lease
and mismatched-finality publication, installs under the correct lease with zero observed hash calls
for the best-block subscription, and then observes the matching notification and query reply.
Existing application-chain failure, owner-identity and 1,000-cycle ARC checks still pass.

## Historical complete mappings

Explicit historical-root extraction validates the full reachable graph under caller ceilings and
copies complete leaves without changing current selection. Merely finding records grants no
block or finality authority; durable application context supplies that binding. Selected-root
restoration keeps its stricter current-root equality contract. Disk snapshot restoration rebuilds
and independently checks the requested historical root under an explicit policy, leaving current
snapshot identity/generation untouched. Empty complete roots and missing physical roots remain
distinct cases. Real restart tests compare every historical value and independently recomputed root,
check narrow ceilings and unknown roots, and preserve current selection and held readers.

## Local history/finality reconstruction

The provider exposes bounded oldest-to-newest retained-block access and an explicit local-history
restoration boundary. It reuses direct-child header/prior-root/time/profile checks, refuses empty
or oversized windows and failed slots, and restores finality separately. In-window finality must
reuse the identical map owner; header/root equality cannot replace it. An evicted finalized anchor
must have the same full profile and predate the retained suffix. Its earlier ancestry is supplied
by the previously validated local durable context, not re-proved from an unavailable archive.
This is not a consensus verifier or the externally trusted checkpoint-import constructor.

Structurally authored local histories exceed the retention window and exercise evicted finality,
in-window owner sharing, duplicate/reversed/oversized histories and root-equal foreign map owners.
Modified fixture seals never stand in for execution certificates; live publication tests use the
separate genuine signed execution fixtures.

## Bounded durable history context

`app/disk_history.nim` encodes one exact `RAGNAROK-DISK-CHAIN-V1\n` representation:
a retained count (1..8), finality tag (0 absent, 1..count referencing the retained owner,
255 for one detached older anchor), then oldest-to-newest retained single-head contexts and
an optional detached finalized context. Each entry has a full 32-byte posterior-root hint,
an E8 exact byte length and the existing single-head encoding. The root hint only routes
physical restoration; the checked enclosed identity/header must agree with the restored root.
Every enclosed head is bound to the same configured chain, full parameters and journal generation.
No alternate schemas or trailing bytes are accepted.

Encoding preflights all header extents and the total ceiling before allocation/hashing. Decoding
preflights every extent before restoring any graph. Historical snapshots rebuild under the explicit
restart policy, while the newest block reuses the disk store's exact current snapshot owner. The
provider checks the linked retained suffix and separate explicit finality; in-window finality reuses
its already restored owner. This boundary consumes verified local journal context, not external
checkpoint trust or new consensus/finality certificates.

`make unit SUITE=disk_history` checks a real journal exceeding the retention window, every retained
value, evicted/in-window/absent finality, exact current ownership and byte-identical round trips.
All truncations, malformed tags/lengths/root hints, trailing data, insufficient context budgets,
wrong generations/policies and absent historical records refuse without changing durable selection.
The local-history fixtures contain structurally authored headers, not execution certificates.

## Disk-chain coordination

`app/disk_chain.nim` creates a contextual database exclusively and provisions detached older
finality followed by the retained suffix through ordinary valid single-root publications.
At most nine bootstrap revisions are followed by a final canonical context-only publication.
Bootstrap markers deliberately cannot decode as canonical history; interrupted initialization
leaves forensic bytes and releases the lock, with no fallback to a partially initialized head.
Normal strict reopen restores every retained binding under the configured profile/policy and
closes the disk owner on any application-context failure. It performs no implicit tail repair.

Opaque `PreparedDiskPublication` stages the already prepared chain update, exact original map,
next generation and encoded context. Preparation also compares freshly encoded prior canonical
context with the durable selected bytes, binding chain/history/finality as well as state ownership.
This costs bounded header/context work, not full-map restoration. Commit checks the exact parent, selected context
and generation, publishes through the existing disk store, and never accesses application/RPC.
The synchronous convenience coordinators preflight enabled RPC/lease authority, commit first,
then install the opaque update without repeating execution or capture. Call synchronous IO only
at startup or under a native worker's exclusive lease, never in dispatcher callbacks. Shutdown
must join any worker before retiring its disk/canonical graphs; cancellation cannot undo IO.

`make unit SUITE=disk_chain` covers real bounded bootstrap/restart, incomplete-bootstrap refusal
without byte changes, genuine signed successors with and without RPC, missing leases, wrong chain,
changed durable finality, budget failures, exact owner retention and strict successor restart.
Application options/services are not wired by this coordinator layer. External checkpoint import
continues to require independent trust and does not inherit local history/finality.

## Native disk-publication worker

`app/disk_worker.nim` owns one fixed-address native thread and one bounded publication slot.
Submission borrows stable disk/publication addresses and all their ARC aliases exclusively until
Done collection or joined close. The host preflights and pauses RPC beforehand, touches only scalar
worker state while native IO runs, then checks the actual receipt and installs the prepared update
on the host before resuming RPC. The worker never invokes RPC or canonical installation.

Default/foreign/stale tickets cannot collect another slot; Done retains capacity until collection.
There is no cancellation-as-rollback API. Joined close reports either the actual operation result,
including any IO uncertainty, or an explicit NotExecuted result when queued work never entered IO.
A completed durable commit is never discarded by shutdown. Composite copy/dup hooks reject actual
ARC lowering; relocation and destruction require an inactive worker.

`make unit SUITE=disk_worker` exercises real native commits, normal collection, completed and
racing shutdown, stale publication refusal, ticket reuse and 24 repeated full lifetimes. Compiler
fixtures verify composite duplication rejection and opaque publication context privacy. These
checks run under checked ARC/Clang. The pinned native allocator's public occupied counter is scoped
to the calling thread and includes pending remote frees; it is not a process-wide cross-thread
leak measurement. This suite makes no numeric zero-leak claim from that counter.
