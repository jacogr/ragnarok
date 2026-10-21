# Application checkpoint context and lifecycle

## Scope and authority

Use the existing complete-map StateStore and local checkpoint primitives. This
work does not modify/import/adopt the independent storage trie, add adapters or
prepare storage integration. PVM execution/certificates remain separate. No GP
0.8.0 protocol equation, pinned vector or network representation changes.

## Captured scalar identity

Capture only from an initialized ApplicationChain selected head and its exact
immutable canonical map owner, using sameStateSnapshot rather than root equality.
Retain sealed block hash, complete posterior map root, nominal block time and the
entire immutable 122-byte parameter tuple. No source map, history or header graph
is retained. Defaults never compare equal or expose initialized accessors.

These facts identify a persistence context; they do not prove consensus validity,
finality or authority to adopt recovered state. Header prior-state roots cannot
replace the selected posterior map root. Recovery must eventually compare against
independent trusted context, not metadata supplied by the same file.

## Completion checks and next layer

Native tests compare exact selected fields, independently changed headers, maps
and profiles, detached producer lifetimes and 1,000 scalar-capture release cycles.
Strict extraction and privacy probes preserve initialization gates. The fixture
is the existing checked-in complete RPC chainspec with an explicit hash contract;
structural fixture variants do not claim valid executed successors.

Next: canonical bounded local encoding of the scalar identity, then an application
envelope binding that context to existing complete checkpoint bytes. Application
startup/shutdown and dispatcher work must remain explicit and nonblocking; no
serialization occurs inside transport callbacks. M1 framing remains complete;
full T(state), whole-block parity and light-state persistence remain open.

## Canonical local identity encoding

The fixed 238-byte local metadata encoding is RAGNAROK-APP-V1 plus LF, sealed
block hash (32), posterior state root (32), E4 little-endian time, all 122 encoded
parameter bytes, then Blake2b-256 of the preceding 206 bytes. The checksum detects
corruption and does not authenticate a head. Decode accepts one exact version and
extent, validates the full parameter tuple and exposes no metadata on failure.
Decoded initialized metadata must still be compared with independent caller
context; a checksum-valid attacker-chosen identity is not a recovery trust anchor.

The native suite uses independently encoded hashlib bytes and existing RPC root/
header goldens, every truncation/octet tamper, exact/short ceilings, valid-checksum
context mismatch, invalid profiles and repeated owned-buffer release. No JAM wire
encoding, chain identity, canonical adoption or storage backend changes.

## Complete application envelope

The application envelope is the fixed 238-byte identity immediately followed by
one existing canonical RAGNAROK-FULL-V1 complete-map checkpoint. The single output
ceiling covers both parts and is bounded by native sequence extent before allocation.
Capture requires exact application head/map owner agreement. Missing context,
metadata/backend failure and complete-map refusal return only selected typed reasons.
Independent golden bytes come from original fixture keys/values and published RPC
root/header expectations. The native suite checks exact whole bytes, every short
output budget, context/map changes and repeated release. No file I/O, canonical
adoption, new database schema or storage integration occurs in this layer.

## Context-bound complete-map restoration

Decode requires a separate initialized expected identity and explicit store/byte
limits. Validate the fixed metadata first, compare every context field, then
restore the exact remaining complete-map checkpoint against the independently
expected posterior root. A checksum-valid mismatched context refuses before map
allocation. Truncation, trailing bytes, invalid identity, changed map/root and
resource refusals expose no recovered payload. Successful maps own their values
and inherit only the caller's explicit policy; no header/history or canonical
application owner is adopted. The native suite checks every cut/tamper, every
context mismatch, complete original entries/counts/roots, input detachment and
1,000 complete-graph release cycles.

## Exclusive prepared application envelopes

PreparedApplicationCheckpoint retains sole encoded bytes plus fixed context and
no canonical graph. Preparation is synchronous computation outside transport
callbacks. Copy/duplication is rejected during actual ARC lowering; a public move
hook resets source status without freeing destination bytes. Only successful
preparation exposes extent/context. Failed/default/moved owners cannot touch a
publication path. Ready publication delegates the existing atomic raw primitive,
including exact/narrower limits and visible-but-unsynced outcomes. Native witnesses
cover detached source lifetime, exact bytes, moved-source refusal, old-file
preservation and 1,000 preparation/transfer release cycles.

## Bounded single-file publication and recovery

Synchronous file adapters publish captured identity and complete map in one atomic
replacement through the existing raw primitive. No separate manifest can lag its
selected map. Prepared or source-owner publication returns fixed identity only on
durable success; visible-but-unsynced remains a distinct payload-free outcome.
Recovery requires independent context before opening a file, bounded regular-file
EOF and checked close before decode, and explicit complete-map resource policy.
Exact native/identity/checkpoint/context failures remain typed. These are startup/
offline APIs, not dispatcher callbacks or canonical chain adoption. Tests cover
exact old-file preservation on refusal, mismatched trust, native paths, corruption
and repeated complete recovery ownership release.

## Exclusive cooperative application writer

ApplicationCheckpointWriter privately owns the existing raw AtomicFileWriter;
regular non-symlink lock admission, copied path ownership, immediate Busy and
explicit close are inherited unchanged. The composite independently forbids copy/
duplication and requires explicit retirement. Source and prepared publication,
bounded recovery and independently supplied context share the same file adapter.
No state graph is retained between operations. Tests cover copied paths, repeated
open, contenders, exact recovery after close/reopen and 1,000 complete owner/read
lifetimes, plus actual ARC copy rejection and private native-child access.

## Real whole-envelope write rollback

Child-only kernel file-size ceilings exercise header-only, profile-only and map-
only context changes. For each, zero/partial/one-byte-short writing must report
actual IoFailure and preserve every old file byte. Exact/ample controls publish
all new metadata and map bytes together. Independent child and joined-parent
recovery agree with the expected context and reject the other context; producer
limits cannot masquerade as native failure. No live writer/lock crosses fork.
Private-directory removal witnesses temporary cleanup. These nine refusals and
six controls cover process/kernel write behavior, not power loss or post-rename
parent-directory synchronization failures.

## Detached envelope I/O worker

One fixed-address native worker owns an exclusive writer and one prepared envelope.
Stage checks lifecycle, capacity, readiness, explicit byte limit and nonwrapping
request generation before moving the caller's sole bytes. Explicit begin grants
I/O; Done retains capacity until matching collection. Host-only namespace identity
keeps foreign/stale/restarted tickets distinct. No canonical graph is shared with
the native thread. Collection/join retires all native aliases before host buffer
release. Joined shutdown preserves actual returned publication outcome separately
from native retirement error; unstarted work is Cancelled, missing outcomes after
native entry are Interrupted. Copy/duplication and live-address relocation are
checked independently. Startup allocates host identity before starting the thread.
Tests cover real publication/recovery, detached producer lifetime, ticket isolation,
backpressure, restart and 1,000 host buffer/ticket retirement cycles.
