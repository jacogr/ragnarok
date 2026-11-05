# Source-bound assurance acquisition, retention and distribution

Target JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, shard assignment and CE137/141,
and Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`, `assurance.tex` and
`reporting_assurance.tex` equations `assurancesig` and the pending-assignment bit rule.
This is one coherent feature layer; its source qualification, durable storage, signing,
network lifecycle, startup policies, tests and documentation belong in the same PR.

An assurance's anchor is the actual selected parent block. Its fixed bitfield is signed as
`ASCII(jam_available) || Blake2b256(anchor || fixed_bitfield)`. No validator ordinal is carried
by CE141. All original roster positions sharing the actual TLS public key must therefore have
verified assigned shards before that identity claims a core. Do not discard repeated keys or
compress null positions. Assignment is `(core * recoveryThreshold + validatorIndex) mod V`,
using the actual greatest-divisor erasure geometry, including valid non-optimal populations.

Acquire only descriptors from complete selected-parent C10 and the actual C8 parent roster.
Registration/evaluation slots, report core, full six-field availability specifier and profile
must agree. Bound whole chapter reads and all planned requests before exposing a plan. Recheck
anchor and complete posterior root before signing or publishing; network replies cannot select
their own expected roots or replace canonical assignments. A cleared/replaced assignment cannot
reuse a previous bit. Cryptographic shard inclusion alone is not a signing capability.

The existing `AvailabilityStore` is a bounded evicting read cache and cannot back assurances.
Durable storage must commit verified bundle and all exported/proof shards, with the exact
specifier/shard identity and retention obligation, before any possession bit is signed. Defaults,
partial/invalid responses, capacity exhaustion, failed writes and visible-but-unsynced writes
must not grant a possession receipt. Preserve existing promises on refusal. Restart must retain
and reverify committed data before it can serve requests or support another signature.

The GP requires exported shards for **28 days**, independent of profile epoch length. The
usual production conversion to 672 one-hour epochs must not shorten Tiny-profile retention.
Bundle shards remain until authenticated audit completion; timeout or disappearance from C10
alone is not audit completion. Retention metadata cannot shorten an existing promise. Safe
pruning must keep both independent obligations and authenticated audit evidence.

The ordinary node uses bounded managed jobs for state, cryptography and storage I/O. Native
callbacks only detach raw frames. Acquisition retries genuine guarantors with exact request
ownership and validates every CE137 component. CE141 has the exact anchor/bitfield/signature
wire form, authenticated validator handling, two-way FIN, bounded duplicate/cancellation and
source refresh. Schedule near two seconds before slots and implement the distinct assurer and
possible-author epoch cutovers from the pinned source; uncertain authority does not justify
inventing a future roster. No file/policy enables this implicitly.

Completion evidence must include genuine canonical assignments and source changes, every local
repeated-key position, non-optimal geometry, corrupted/partial/wrong-root responses, complete
preflight and capacity refusal, real durable restart and I/O failure, 28-day boundaries across
profiles, proof serving after session retirement, exact independent signing/bitfield vectors,
real TLS acquisition and CE141 delivery, epoch timing, cancellation/Done/join ownership and
explicit optional foreground activation. Full JAMNP-S still needs audit/judgment lifecycles and
CE147-to-138 auditor fallback. This feature is in progress and is not yet publishable.

## Assignment qualification evidence

`assurance_duty.nim` now captures complete parent C8/C9/C10/C11 under independent per-chapter
and aggregate read limits. It checks exact chapter consumption, C11/header time agreement,
actual local C8 indices, pending report/core/population/registration consistency and the whole
acquisition-request ceiling before publishing an immutable plan. C9 supplies the independent
prior credential bound for decoding canonical assignments. Null positions remain in the geometry;
every repeated local identity position is retained. A changed anchor or complete posterior root
revokes a previously captured plan, even when the sealed header is unchanged.

The checked native suite passes six-, twelve- and 1023-validator source/coordinate witnesses,
including three repeated local positions and a null predecessor. The twelve-validator threshold
is four, since 2052 is divisible by four; a naive threshold of five gives different coordinates.
It also covers exact/minus-one whole input and request limits, malformed C10 tails, future
registration, population mismatch, absent/invalid coordinates, default policy and non-validator
refusal. Its 1,000 success/late-refusal cycles retain 122128 occupied bytes before and after.
Pinned formatting, verification inventory and all 556 production modules plus the application
entry point pass. These are local source/API results, not native Linux CI.

The erasure sources are genuinely executed. The registration maps in this focused suite are
independently trusted structural fixtures with placeholder guarantee credentials; they do not
establish GP block admission. Genuine admitted assignments, durable possession, signing, CE137/141
runtime and optional activation remain mandatory completion evidence. The feature stays in its
unpublished assurance layer until those parts are implemented and verified.

## Per-shard persistence record

The `RAGAS001` format stores one complete verified CE137 distribution. Records do not require
an archive-sized in-memory table or rewrite unrelated payloads. The forthcoming namespace owner
will enforce chain identity, aggregate disk/count budgets, single-writer exclusion and successful
file/directory synchronization before granting any durable possession. The record codec alone
confers none of those capabilities.

All integers below are fixed little-endian. Hash/key fields retain their complete 32 bytes.

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 8 | Exact ASCII `RAGAS001` |
| 8 | 32 | Independently expected configured chain identity |
| 40 | 104 | Package hash, E4 bundle length, erasure root, E2 shard count, segment root, E2 export count |
| 144 | 2 | Original assigned erasure-shard index |
| 146 | 8 | Promise time in whole seconds since the GP Common Era |
| 154 | 8 | Export retention deadline in the same time domain |
| 162 | 12 | E4 byte lengths of bundle shard, all segment shards and justification |
| 174 | 32 | Blake2b-256 of the preceding 174 metadata bytes |
| 206 | Variable | Exactly the three payloads, in their declared order, with no trailing data |

The deadline is at least 2419200 seconds after the promise time. Arithmetic refuses overflow;
renewal cannot move time backwards or shorten an existing promise. Both bundle and exports stay
in the complete record; the record's existence or deadline alone does not certify that a report
has completed auditing. No timeout or absent pending assignment grants deletion authority.

Directory accounting may check only the fixed header checksum and exact file extent. Before
serving or considering possession, full restore verifies all three CE137 payloads against the
record's precise root/coordinate. A self-rooted persisted descriptor still cannot substitute
for independently canonical metadata: `recordMatches` compares all six fields and the requested
coordinate. Construction detaches incoming verified data; serving extraction returns another
private copy. The signing path must still establish durable publication, fresh duty and every
original local index.

`availabilityVerificationInfo` supplies bounded expected extents and exact real proof work
without granting data or authority. Record restore charges the metadata checksum and all payload
verification before even its first hash. Exact file size, geometry and work deficits refuse
without hashing. The native record suite confirms empty, ordinary and proof-page distributions,
metadata/payload corruption, wrong chain, truncation/trailing data, exact/minus-one aggregate
budgets, actual immediate and delayed backend refusal, recovery, renewal and full-width time
boundaries. The actual primitive call counts match the preflight, and 1000 create/restore/serve/
refusal cycles retain 71344 occupied bytes unchanged.

The duty suite also now uses the actual GP null-validator record (`02` followed by zeros for its
Ed25519 key) and rejects that identity as well as an all-zero key. Its 1000-cycle result remains
122128 bytes unchanged. The existing availability suite passes with 714816 bytes unchanged.
Pinned formatting and verification inventory pass. Actual disk publication, restart I/O,
non-evicting capacity, managed acquisition and CE141 remain in progress; no durable assurance
promise or complete runtime flow is claimed by these record tests.
