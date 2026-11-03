# Canonical state and preimage retrieval

Scope: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE129 and CE143,
using full retained canonical `ChainView` snapshots and the pinned GP state trie. The shared
fixed-request stream route also carries CE128 without duplicating its native lifecycle.

CE129 accepts exactly98 payload bytes: sealed header hash32, inclusive start/end keys31 each,
and E4 maximum size. It returns two E4 messages: bare boundary nodes and bare key/value tuples.
Values use canonical JAM natural lengths. Selection walks the sorted complete-map index and
returns a contiguous inclusive prefix. A conservative32KiB reservation for two boundary paths
may underfill the requested byte limit; a single pair may exceed that requested maximum as the
protocol permits. The hard8MiB local reply ceiling always applies. Reversed/unknown ranges or
an empty range whose necessary boundary proof cannot fit reset rather than fabricating success.

Boundary generation copies the bounded map once for start and last-included paths. Root-first
paths are merged by exact encoded-node identity, without duplicates or off-path nodes, preserving
parent-before-child order. For an empty interval there is no last included key: this implementation
returns only the path to the requested start, under the ordinary maximum size constraint. This
records the empty-range interpretation explicitly; it does not invent a last-key sentinel or an
extra end-key proof contrary to the specified path list. Only a complete full-state owner is used;
light roots/partial maps never enter this API.

CE143 resolves a full hash against canonical best-state service preimages. Service metadata
bounds the service search. Every candidate's extent is checked before copying, then its full
Blake2b256 hash is compared with the request; truncated-key collisions or inconsistent raw state
cannot substitute another blob. The CE136 report database and development integration bank are
not used. Unavailable values reset. Serving retained historical preimages beyond the current
canonical map or a future protocol reception cache is outside this layer.

The fixed stream route waits for exact selector/E4/payload/FIN before releasing one host job,
retains no state graph, bounds reads/writes, and revokes pending work on reset/close. Hosts own
fixed route capacity, per-peer/global quotas, deadlines, canonical read leases and bounded proof
worker scheduling. A multiplexer may consume the selector before binding. Frozen replies bind
all request facts and require exactly the method's response-message count and aggregate ceiling.
Ordinary Services integration remains a subsequent layer; codecs/framing alone are not claimed
as a complete runtime node.

Completion checks: `make unit SUITE=jamnp_canonical_read`, authenticating both boundary paths
against the independent retained root; exact inclusive KVs, absent starts/empty intervals,
canonical natural length boundaries, single-pair size exception, wrong ranges/limits, complete
CE129/143 TLS transcripts and delayed request FIN, malformed extents, unknown preimages and full
hash mismatch. `make unit SUITE=jamnp_block_service` preserves the existing shared-route witness.
