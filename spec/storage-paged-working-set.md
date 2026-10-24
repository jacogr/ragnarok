# Paged storage and bounded working sets

Status: storage-only contract; no paged runtime, memory result or application adoption is
implemented by this document. The first backend is an immutable, disk-indexed **light-evidence**
store. Its selected dataset may exceed RAM while its private working set remains explicitly
bounded. Existing complete-image/cache and full-node repository APIs keep their current contracts.

Authority remains the pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`
Merklization M/B/L and the [proof/trust contract](storage-light-state-proofs.md). Local page hashes,
file indexes and checksums establish storage integrity, never root provenance, finality or a
complete-state map derived from partial knowledge. Compiler, provider, allocator and upstream
pins remain unchanged. This is a local schema, not a network proof format.

## First boundary and full-node gate

The [storage direction](../docs/design/state-storage.md) separates protocol commitments from
physical layout and requires distinct full/light semantics. The current
[streaming light reopen](storage-light-streaming-reopen.md) still materializes a selected image
and cache. The [retained-layout evidence](storage-retained-layout.md) likewise leaves a complete
full-node graph resident. Neither establishes a bounded working set.

| Boundary | Paged light backend | Full-node paging |
| --- | --- | --- |
| Root authority | Independently supplied chain and well-formed complete-state root | Independently supplied complete root plus complete graph authority |
| Local key missing | UnknownKey after a checked disk-index search | Missing physical data is corruption; protocol absence requires a complete checked route |
| Admitted content | Canonical root-bound query proofs, including explicit absence | Every reachable physical record, route, child identity and retained-root inventory |
| Initial working set | Fixed page pool, bounded metadata, one proof/value at a time | Requires a separate bounded graph/visited-inventory design |
| Consumer surface | New explicit-close paged resources and owned verified lookups | No adoption by StateStore, PVM or checkpoint consumers in this tranche |

A future full-node backend must preserve full physical child identities, including the left
child bit that JAM B masks in its protocol commitment. It must verify routing, counts,
availability, duplicate/cycle rules and the complete retained-root union with bounded memory and
explicit disk scratch. A page checksum, valid root field or lazy visited subset cannot replace
those checks. This contract does not authorize a partial implementation of that full-state API.

## Chosen local V1 layout

The first layout uses **4,096-byte logical data pages**, independently of OS page size. This is
a bounded buffered-IO baseline, not a page-size performance claim. The codec implementation must
freeze independent golden bytes and reject every other schema; it may not silently reinterpret
existing light snapshots, light journals or full-node files.

All integers below are unsigned fixed little endian. E8 means eight bytes; E2 means two.
The schema strings use one LF byte for `\n`. Page digests, page ordinals, file offsets and
protocol StateRoot values retain distinct nominal roles; a page digest cannot become a StateRoot.
Let P = 4096, N be retained query count, and S be total encoded proof-record bytes.

- Page zero contains `RAGNAROK-LIGHT-PAGED-V1\n`, 32 chain bytes, 32 complete-root bytes,
  E8 positive physical epoch, E8 ordinary-update sequence, E8 N and E8 S, then zero padding.
  The fixed prefix is 120 bytes. An empty cache has N = S = 0 at any independently expected root.
- The index follows page zero: N fixed **64-byte descriptors**, strictly increasing by the full
  31-byte query key. Each descriptor is key, E8 payload-relative offset, E8 record length and
  17 zero reserved bytes. Its final page has zero padding.
- The payload follows the padded index. Each record is the existing canonical query transport:
  31-byte key, E2 node count, E8 raw-value length, canonical 64-byte path nodes and raw value.
  Descriptor and payload keys agree. Records occupy exact consecutive, nonoverlapping extents
  in index order, with no holes or aliases; only the last payload page may have zero padding.
- A complete binary digest tree follows all data pages. With G = 1 + ceil(64N/P) + ceil(S/P),
  let T be the smallest power of two at least G. Store (2T - 1) 32-byte digests in canonical
  postorder: complete left subtree, complete right subtree, then parent. Root is the final slot.
  Subtree extents and child/sibling positions are computed from T and bounded depth, without an
  in-memory tree/index. This order permits sequential tree construction with bounded carry scratch.

For Blake2b-256 H, data-page leaf i is
`H("RAGNAROK-LIGHT-PAGED-LEAF-V1\n" || E8(i) || page[P])`. Padding leaf i, for G <= i < T,
is `H("RAGNAROK-LIGHT-PAGED-PAD-V1\n" || E8(i))` and has no physical data page. An internal
node is `H("RAGNAROK-LIGHT-PAGED-NODE-V1\n" || left[32] || right[32])`. These local domains
are distinct from JAM's B/L domains. The logical file length is G*P + 32*(2T - 1), exactly.

`CURRENT` has its own exact schema: `RAGNAROK-LIGHT-PAGED-MANIFEST-V1\n`, chain[32], root[32],
E8 epoch, E8 sequence, E8 G, E8 file length, page-tree root[32], then H(all preceding manifest
bytes). It selects only `paged-<16 lowercase hexadecimal epoch digits>.bin` in the held directory.
All manifest/header/actual-length claims agree. The manifest checksum is not a trusted JAM root.
`LOCK` remains a stable regular writer-lease file; `CURRENT.next` is exclusive manifest staging.
The builder exclusively creates the immediate next canonical epoch file. Until sealing and
selection it is unselected; an existing name is never overwritten or opened as a fallback.

Count products, ceiling division, next-power-of-two growth, tree slots, relative offsets,
file offsets and native conversions must be checked **before** arithmetic, allocation or IO.
Zero entries require zero payload; each nonempty record has at least 41 bytes and at most 249
proof nodes. Reserved/padding bytes are canonical zeros. Unsupported schema, overflow, short
files, wrong extents and extra EOF bytes refuse; sparse-file holes grant no admission authority.

The independent empty witness uses zero chain/root, epoch one, sequence zero and N = S = 0.
It has one data page, T = 1, a 4,128-byte container and 193-byte manifest. All queries
are UnknownKey until evidence is explicitly retained, including at the empty complete root.
Python hashlib/struct produce:

- Page-tree root: `4fc34f4e3d1af70566cfc84c0f513c2f538adeb511f93f890df921bd85d1f093`.
- Manifest checksum: `d0a672190bbc37ce48e0944a04cabd5dfaca4a8ae87ca4477221f2b4ca573146`.
- Container SHA-256: `96196bf96f8ebc1a662a0e7bf7212c8bd751f0c5fad856a2d9bed22d87b0bfaf`.

These are independent format witnesses, not native-code execution or paging qualification.

A nonempty witness retains zero-node authenticated absence for keys beginning 0 and 128, all
remaining key bytes zero, at the independently expected empty root. N = 2, S = 82, G = 3 and
T = 4. Index descriptors occupy 128 bytes before padding. Its seven tree slots are leaf 0,
leaf 1, their parent, leaf 2, padding leaf 3, their parent, then root. The container is 12,512
bytes and the manifest is 193 bytes. Unknown key 64 remains UnknownKey. Independent values:

- Page-tree root: `65c398a5724e8de74a7e253676a8fe75e490df05318f2b0e898525e0a87fb1a1`.
- Manifest checksum: `0b685aad6b4cb1cba9a4fc4c5dead2d70bdd31423fde37f53a4281d89d296aa6`.
- Container SHA-256: `b8980831d10ff6a361b8caeb9cfca44838f9aee3c3e5ed377d32867480b31dda`.

## Logical limits and private memory

Dataset limits independently bound total file bytes, entries and logical retained values.
They may exceed the working-set allowance. Per-proof node/value ceilings remain independent
of dataset size and future mutation-batch allowances, including zero future writes.

The reader owns a finite page pool and fixed-capacity slot metadata. All cached, pinned and
in-flight buffers are charged, including index and digest-tree IO. The implementation must
preflight the pool's byte/descriptor extents, hash-input buffers, tree-depth scratch and native
handle allowance. No full descriptor table, query inventory, decoded cache, whole-file buffer
or whole-file mapping may hide outside that accounting.

A lookup reconstructs at most one bounded proof into node/value transport, verifies it, and
returns one independent owned lookup. Charge concurrent transport and verified-value copies:
up to 64*proofNodes + 2*valueBytes, plus explicit page/hash/traversal/ownership scratch. A page
hash's domain-prefix buffer is additional scratch, not an uncounted page copy. Actual native
object headers/allocation rounding must be measured separately from these logical payload bounds.
Backend allocation exhaustion retains the existing fail-stop policy; this adds no recoverable allocator.

Cache capacity zero means uncached reads through a finite IO workspace. It never means unlimited
retention. The first replacement policy is deterministic round-robin over eligible private slots;
failed/unverified pages are never installed. Limit checks precede allocation and disk work. One
owner's bounds do not cap process RSS: caller-retained owned results, simultaneous reader owners,
provider/runtime allocation and kernel page cache require separate accounting and qualification.

## Strict open and authenticated disk lookup

The public paged reader is distinct from PreparedLightSnapshot and LightStateCache. Opening it
must not construct either complete representation internally. The caller supplies the expected
chain/root and all policies; file metadata never supplies those expectations.

Strict open performs a complete **bounded-memory** pass before returning a usable reader. It
checks format/shape, all index ordering and coverage, every proof at the expected root, every
page/tree digest, counts, padding and actual EOF. Tree verification uses bounded traversal/carry
scratch, not an O(G) visited/hash array. One proof and bounded windows retire before the next.
Open work scales with the dataset; it is neither constant-time nor a lazy trust shortcut. A late refusal exposes no
reader or partially authenticated cache and retires acquired resources without changing bytes.

After open, fixed-width disk binary search finds a query without loading the index. Every
fetched data page is authenticated through the on-disk digest path to the reader's cached root;
that root binds the already checked header, index and payload. File offsets and page roles are
checked before each read. A cache hit remains tied to that exact epoch/root/file incarnation.
Held inode/name/extent and final EOF checks detect replacement, shrinkage and growth. Recomputed
checksums in modified files cannot replace the cached digest root or the caller's state root.

A cache miss performs bounded IO. It is not UnknownKey. Only a checked index search that finds
no retained query returns UnknownKey. A located entry must still verify against the exact query
and independently expected complete root before returning Present, present-empty or authenticated
Absent. The first cache retains authenticated page bytes, not an unbounded table of verified
lookup owners. Proof/provider/IO failure never becomes local missing data or protocol absence.

Default/closed resources return Uninitialized. Typed reasons distinguish UnknownKey, policy/work
limits, unsupported schema, identity mismatch, corruption/proof refusal, provider refusal, native
IO, Busy and stale position. Pure quota/provider refusal installs no partial output. Integrity,
inode/extent or native-read uncertainty poisons further fresh reads until explicit close and strict
reopen; previously returned owned lookups remain valid. Failed/default result payloads and
selected proof-reason accessors remain private and success-guarded.

## Reader pins and reclamation

Paged readers are explicit-close, move-only native owners. They own their immutable epoch handle,
read pin and bounded cache independently of the writer. They remain bound to the captured root,
sequence and epoch across publication and writer close. They do not silently follow a new CURRENT.
Lookup/proof byte extraction is owned; no borrowed cache page can escape a call or pin a slot.
Returned owned lookups survive reader close and file removal.

Use a shared advisory pin on the immutable epoch file and an exclusive, nonblocking pin for
reclamation. Before deleting an old file, the writer holds the stable directory writer lease,
revalidates CURRENT/selected data, refuses the selected/future epoch, and acquires the old epoch's
exclusive pin. Any live reader makes cleanup Busy without unlinking that epoch. Independent
readers hold independent descriptors; no resource-owner copy duplicates close authority. Native
lock/retirement behavior must be qualified on supported Linux/macOS; unsupported platforms refuse.

To open a current reader, read/validate CURRENT, open and pin that exact regular no-follow epoch,
and reread CURRENT. If the selection changed during acquisition, return StaleView and release
resources, without fallback/retry. Successful acquisition fixes that immutable selection; later
publication may advance CURRENT while the bounded verification pass completes. Final validation
still checks the pinned epoch and its complete extent. Writer cleanup honors the pin throughout.
No selected file is modified in place, and no in-place shared-to-exclusive lock upgrade is assumed.

Closing retires handles even after poison and reports native failures without retrying a reused
fd number. Resources/leases remain acyclic; cached pages own no writer, callback or reader cycle.
The implementation must prove actual ARC copy/move/lowering behavior, not only semantic checking.

## Streamed construction and atomic selection

The initial writer builds full immutable replacements, not an incremental paged journal. A bounded
replayable producer supplies a declared count/payload extent and strictly sorted query proofs,
one stable borrowed input at a time. Every pass binds the same canonical stream with bounded
streaming-digest scratch; changed input refuses sealing. Actual counts, every proof and the
exact final extent must agree; an early end, extra entry, duplicate/out-of-order key or late provider failure refuses the whole build.
The builder cannot stage a complete detached proof batch, cache or in-memory sort. Large fixture
production must likewise be streamed or kept outside the measured reader process.

Build IO is explicit. With N/S known and bounded, write the complete header and index in one
producer pass, then matching payload in another, and finally the postorder tree through bounded
body reads/carry scratch. Emitted file bytes are always a canonical prefix: no reserved sparse
holes, header rewrites or random tree writes. Validate each emitted proof before its payload and
fully check the completed file/tree before sealing. Only synchronized file/directory completion
produces an opaque sealed-artifact owner. This owner retains its exclusive native artifact pin;
sealing is not CURRENT publication. Raw bytes, a ready flag or a checksum cannot manufacture it.
A failed result never carries a partial artifact: an acquired authoring owner must be closed
explicitly, preserving its unselected forensic files.

Publication binds the exact source selection, root/chain, epoch/sequence, file incarnation/extent,
all inherited policies and one live sealed-artifact incarnation. Passive prepared metadata never
duplicates native ownership. Closing/reopening an artifact requires fresh validation/preparation;
it cannot revive an old capability through equal counters or a reused descriptor. Before selection,
revalidate held source and candidate bytes against their cached complete page roots with bounded
reads and actual EOF. A live checked seal may avoid repeating target proof verification when its
exact bytes still match; freshly opening an artifact requires full proof verification.

All selected data and the complete digest tree become durable before the bounded manifest is
staged, synchronized, atomically renamed to CURRENT and the directory synchronized. Only confirmed
selection changes the writer's visible head. IO uncertainty yields no fresh head/receipt and poisons
fresh writer observations until explicit close/reopen. Post-confirmation artifact/old-handle
retirement is reported separately and cannot erase a confirmed selection. Retained reader pins
remain bound to old epochs; cleanup is explicit and bounded, with synchronized absent-name retries.

Initialization starts at epoch one/sequence zero. Full same-root evidence replacement advances
sequence once, including a requested no-op. Explicit compaction preserves root, exact knowledge
and sequence, and must derive its stream from a held checked source reader; equal state roots
alone do not prove equal retained knowledge. A root change requires a separate explicit destination
root and wholly reverified destination evidence, preserving the ordinary-update sequence as in
[light-root advancement](storage-light-root-advancement.md). Every selection advances physical
epoch once. Exhaustion refuses before build IO/hash; no counter wraps or implicit root/proof carry.

Ordinary open consults only CURRENT and never adopts a staged candidate. Unknown/unsealed build
files block conflicting creation and remain forensic evidence. Partial-build cleanup requires
an explicit expected source position, independently expected destination root/counts/policy and
a replayable fully verified target producer. Reconstruct its canonical bytes/digests with bounded
passes, and compare the actual held candidate against exactly that complete-file prefix, including
possible partial page/digest bytes. Root and target shape are never inferred from the candidate.
Hold its exclusive pin, revalidate name/inode/extent/EOF and source selection, and preflight the
bounded CURRENT.next prefix against the reconstructed final manifest before any unlink. The
opaque cleanup owner retains that validated inode/position, not the producer or whole dataset.
Already-absent names still receive final synchronization. Without matching producer authority,
or on any unknown prefix/policy/provider/IO mismatch, preserve all candidates and return a typed
refusal. Invalid or nonreproducible builds may therefore need separately authorized administration.
Complete sealed-candidate cleanup uses its checked capability with the same source/pin/preflight
rules. Directory scans, arbitrary epoch deletion, in-place page reuse and conversion of existing
databases are outside this first layout.

## Completion and evidence gates

The contract is the next substantive layer on native stack #1395, after its ten published layers.
The total cap remains **15 PRs**, including this contract. Subsequent coherent units cover the
paged codec/digest/index boundary, streamed construction and bounded reads, native publication/
reader-pin lifetime, and grouped process/resource qualification. Supporting guards/tests/docs stay
with their implementation concern. Each ready unit is published before starting the next; the cap
never licenses dropping validation or fragmenting cases into individual PRs.

Required implementation evidence:

1. Independent byte witnesses for empty and nonempty artifacts/manifests; every truncation,
   trailing byte, reserved field, ordering/descriptor/page/tree error, count/offset/power-of-two
   overflow and recomputed-checksum false proof. Wrong-mode/root/chain and preallocation limits
   refuse without hidden conversion. Include 249-node paths and values crossing page boundaries.
2. Independent complete-map proofs and cache/image comparisons on small fixtures. All resident
   page capacities, including zero cache, agree on Present/empty/Absent/Unknown, root, sequence
   and canonical proof bytes. Exact/short work budgets, provider refusal at each observed stage,
   caller/output mutation and cold-lookup IO faults expose no partial successful prefix.
3. Actual resource-owner copy/lowering rejection, private/default result guards and positive
   controls. Run at least 1,000 open/read/evict/refuse/close cycles after all extraction temporaries
   retire. Check native handles, locks and ARC occupancy; no retained page or whole-index growth.
4. Real concurrent reader pins versus replacement, writer close and old-epoch reclamation,
   including another process. Qualify every observed build/selection/close/cleanup syscall boundary
   and positive short-write chunk with exact stopped-child/kill/reap controls, unchanged forensic
   bytes, strict independently expected-root reopen and explicit permitted recovery. Process death
   remains distinct from hardware/filesystem power loss; cleanup needs explicit matching producer
   or sealed-artifact authority.
5. Serial fresh-process resource panels with fixture production excluded, exact source/compiler/
   provider/binary identities, independent query results and native bytes/pages/hash/cache counters.
   Bound private buffers and metadata as N grows under a fixed working budget. Qualify any actual
   larger-than-RAM claim on controlled native Linux with a populated selected dataset larger than
   the enforced no-swap allowance, spread/cyclic reads, deadlines and exact kernel receipts.
   Distinguish completion, typed resource refusal, OOM kill and timeout; fresh processes alone do
   not prove cold filesystem/device caches. Keep optional pressure work out of routine CI defaults.

No performance or deployment-ceiling conclusion follows from this contract or a small functional
fixture. Existing M1 framing/implemented-scope completion remains distinct from complete JAM state
serialization and whole-client parity. Startup, StateStore/PVM/checkpoint adoption, network proof
fetching, trust selection and full-node paged graph validation retain their separate scope gates.
