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

## Staged cancellation and retained observation

Only matching Staged requests may cancel before dispatch; cancellation retires sole
bytes on their host and retains Done capacity until acknowledgement/join. Running,
Executing and Done publication outcomes never become Cancelled. Peek observes only
a matching Done receipt without collecting or retrying it. Foreign, stale and
restart tickets expose no outcome. Tests cross actual publication, cancellation
shutdown, repeated observation and 1,000 staged buffer/ticket retirement cycles.

## Real worker write refusal receipts

Child-only kernel file-size ceilings cross header/profile/map context changes through actual detached-envelope I/O threads. Each zero/partial/short refusal must remain Completed(IoFailure), and exact/ample controls Completed(None), through both explicit collection and joined shutdown. Eighteen refusals and twelve controls verify exact old/new whole bytes, independently bound child/parent recovery, lock retirement and absence of temporary siblings. Producer byte policy remains sufficient; no live native owner crosses fork. Process/kernel behavior is covered, not power loss or post-rename directory-sync refusal.

## Known worker process-exit boundaries

Child processes exit without collection, joined close or copied-parent ARC destruction at observed Staged, Cancelled and durable Done boundaries. Across header/profile/map changes, nine boundary witnesses verify exact old/new whole envelope bytes, fresh parent cooperative lock admission and independently bound recovery, rejecting the other context. No live native owner crosses fork. Final private-directory removal detects orphan temporaries. These are known process boundaries, not mid-write interruption, power-loss or filesystem crash-consistency claims.

## Managed shutdown acknowledgement

ApplicationCheckpointSession privately owns one fixed-address worker and a scalar
joined-outcome journal. Actual uncollected work or native retirement uncertainty
survives repeated close and blocks restart until explicit takeShutdown. Collected
work and clean idle shutdown create no duplicate receipt. Inactive ownership may
move the fixed journal, clearing source acknowledgement authority; live parent
relocation and implicit copies are rejected. No shutdown path silently retries a
possible publication or adopts restored state. Native tests cross real completed
publication, staged cancellation, retained observation, restart and repeated full
native lifetime retirement, with strict accessor/lifecycle and copy/private checks.

## Services canonical capture boundary

Services exposes fixed identity capture and explicit bounded prepared-envelope
creation only when its existing canonical preparation lease is inactive. Both
operations traverse the selected application pair synchronously outside transport
callbacks; missing/default/closed state remains a typed refusal. After preparation,
only independent bytes and fixed identity remain. Strict runtime witnesses start a
real managed execution lease and reject both APIs before graph access, with genuine
successful controls before the lease. Native tests cover configured capture,
explicit short budgets, close/restart and 1,000 detached preparation lifetimes.

## Service-owned export lifecycle

Services explicitly starts one managed export session at its stable address.
Prepared bytes may stage/dispatch/observe/collect during execution leases because
these APIs touch no canonical graph. Serialization remains a separate lease-guarded
host operation outside callbacks. Aggregate close joins I/O and preparation before
retiring canonical/listener aliases; repeated close preserves a fixed actual joined
receipt, and export restart requires explicit acknowledgement. Neither actual
publication nor retirement uncertainty triggers an implicit retry or adoption.
Services itself rejects live relocation and implicit copies. Native tests cross
real publication, aggregate close/restart, stale tickets, staged cancellation and
acknowledged idle shutdown, with actual runtime/move/copy/private checks.

## Independent export and canonical execution lifetimes

Real Services integration holds an actual preparation/RPC canonical lease while
staging, dispatching and observing previously prepared checkpoint bytes. I/O Done
never releases the execution gate. Both explicit export acknowledgement and
unacknowledged joined aggregate close preserve the exact publication outcome;
joined close retires both threads before canonical/input owners disappear. Fresh
independent recovery agrees with the pre-lease context. Repeated close and restart
cannot overwrite the retained receipt or revive its ticket. These witnesses use
existing execution APIs and change no PVM implementation or storage backend.

## Scalar verification receipts

Verification-only path and cooperative-writer APIs perform the same bounded,
independently context-bound complete load, then retire all decoded byte/map owners
on the allocating caller thread before returning fixed matching identity. No map
owner escapes this API, and no verification repairs, writes, adopts or asserts disk
durability. Native/context/format/resource failures remain precise payload-free
results. Tests cover exact/short budgets, wrong/default trust, tight map policy,
corruption, closed writers and 1,000 paired path/locked full verification cycles,
plus strict refused-success access with a genuine verification control.

## Native verification without map transfer

Verification admission accepts only independently supplied fixed application
context and explicit map/byte policy. It shares publication's one outstanding slot,
nonwrapping namespace, staged cancellation and acknowledgement gates. Complete
file bytes and restored maps allocate/retire entirely on the I/O thread; only fixed
identity/result metadata returns to the host. Actual Completed receipts explicitly
identify Publish or Verify, so successful validation cannot masquerade as durable
publication. Joined session journals preserve that operation identity. Tests cross
both operations, exact context/resource refusals, cancellation, joined receipts,
backpressure and 1,000 host ticket/receipt cycles; verifier tests separately witness
complete decoded graph release. No recovered chain is adopted automatically.

## Service verification during execution leases

Services stages verification using explicit independent fixed context and resource
policy through the existing export session. No canonical getter or graph traversal
is involved, so managed preparation/RPC exclusion remains held independently.
Native integration publishes once, starts a real execution lease, then verifies
without releasing that lease. Done capacity and default-context refusal remain
effective. Repeated aggregate close retains a distinctly Verify joined receipt,
not a publication receipt; no restored canonical chain is installed. Verification
requires no startup trust-policy decision and changes no PVM/backend implementation.
