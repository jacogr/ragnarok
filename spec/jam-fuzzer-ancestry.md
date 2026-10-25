# Initial fuzzer ancestry and lookup-root evidence

Authority is the unchanged GP 1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d
reporting_assurance.tex lookup-anchor predicate and the pinned davxy/jam-conformance
acd4b2da310ff25226c4d41b918712578483fd2c fuzz-v1 Initialize ancestry schema.
Initial records contain only E4 slots and 32-byte header hashes, at most24 records.
The maintainer explicitly directed preserving GP checks and reporting missing
root evidence locally rather than adding a fuzz-only exception.

This primitive captures immutable initial membership facts and actual known
headers under explicit count, header-profile and byte budgets. Input order has
no authority; records are normalized newest-first without changing message wire.
The supplied seed header is always retained. Duplicate/conflicting hash/slot
facts, future/same-slot non-seed records and incompatible head/profile bindings
are refused. Initial metadata is test-seed context, never a production ancestry
certificate or a fabricated full historical header.

A lookup needs its exact declared hash and slot plus a retained actual newer
header whose parent is that hash and whose prior-state root equals the report's
lookup root. A matching record without that child yields MissingLookupChild;
a known different root yields WrongLookupState. No root is guessed from a report,
from an unrelated complete map or from the membership record alone. Captured
headers are structural evidence here; admission/signature authority belongs to
the actual execution pipeline. Integration must keep fuzzer-supplied membership
separate from production chain adoption authority.

A successfully imported child extends one immutable branch context only after
its full sealed parent hash and increasing slot match that branch's head.
Retention keeps a newest-first prefix within count and byte quotas, including
reference metadata and actual known header bytes. Old contexts remain immutable
for sibling restoration. Missing/evicted facts retain typed local failure.

Completion tests cover exact resource boundaries, unordered initial facts,
immutable copies, conflicting membership, parent/profile binding, actual child
root checks, missing child evidence, wrong slots/roots and bounded extension.
Live campaign validation remains explicitly deferred.

Execution integration uses the ordinary authenticated block prefix, current PVM
execution and complete-state composition. Fuzz-only report certificates retain
their ancestry origin, and both chain producers refuse them in ordinary views.
Exact-view comparisons also include the domain. Each successful fork restores
its original parent's immutable evidence; unsuccessful attempts publish neither
state nor ancestry. Target feature mask3 is negotiated before accepting initial
membership or siblings. Missing lookup evidence closes locally with its precise
anchor reason; a known wrong root remains a consensus refusal.

The registered reporting ancestry corpus compares20 actual fuzzer imports across
independent two-core reporting chains against the frozen mathematical STF maps.
Initial membership includes an older hash with no actual child. Four re-signed
reports targeting that hash fail locally as MissingLookupAnchor; four re-signed
reports naming a known incorrect child-committed root fail as WrongLookupState.
Both leave the exact complete map and selected head unchanged before the genuine
block succeeds. Expected bodies, maps and failure classes are calculated before
native execution and their streams are frozen independently.

The registered retention corpus tests exact333/666/999-byte evidence ceilings
(297 actual header bytes plus36 membership bytes per retained record), alongside
independent count ceilings. Five profiles compare eight successful complete-map
transitions. Four lookups lose necessary membership/child evidence and fail
locally without modifying the whole map or selected head. The three-header
boundary control preserves the proof and reaches the real OccupiedCore consensus
refusal instead. Expected retention outcomes and all maps precede execution.
