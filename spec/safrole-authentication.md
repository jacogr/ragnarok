# Safrole author, seal and entropy authentication

Target: Gray Paper **0.8.0**, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/safrole.tex` equations `ticketconditiontrue`, `ticketconditionfalse` and `vrfsigcheck`,
and `text/header.tex` posterior-active author-index definition. The source/vector revisions and
ark-vrf 0.2.2 dependency remain unchanged; twenty newly consumed trace JSON blobs are SHA-256 pinned.

## Core contract

`src/state/safrole_authentication.nim` accepts an immutable complete signed header, exact posterior
C(4)/C(8), parent timeslot/entropy and independent finite chapter/roster/header ceilings. The actual
posterior active population bounds the author index independently of structural header limits.
The selected schedule entry is indexed cyclically by target slot modulo epoch length.

- Derive posterior entropy[3] as parent entropy[2] on **any** epoch crossing, otherwise parent
  entropy[3]. This history rotation does not depend on authenticated new entropy[0].
- Fallback mode requires the indexed active Bandersnatch key to equal the selected schedule key.
  Verify the seal under ASCII `jam_fallback_seal` || posterior entropy[3], with the **complete exact
  unsigned header serialization** as separate additional data.
- Ticket mode verifies the seal under ASCII `jam_ticket_seal` || posterior entropy[3] || E1(attempt),
  with the same unsigned additional data, then requires the verified seal output hash to equal
  the selected ticket identifier. The attempt is a single byte even at 200.
- Verify the entropy proof under the same indexed author, context ASCII `jam_entropy` || verified
  seal output, and **empty additional data**. No raw unverified signature-output extraction is used.
- Tokens contain no dollar, length prefix, terminator or implicit hash. The pinned ordinary VRF
  uses its maintained 96-byte output/challenge/response encoding; no new primitive ABI is added.

Only complete success publishes a retained exact header, typed verified entropy output, seal
output and ticketed classification. Default/failed results contain only their reason, behind
private discriminators/payloads and guarded extraction. Backend refusal/panic differs from an
invalid seal, ticket binding or entropy proof. Invalid slots, input suffixes, malformed/default
owners, actual-population author bounds and finite byte ceilings reject without implicit repair.
No native secret/setup owner is created by authentication. Allocation failure remains fail-stop.

The signing dependency is not circular: the VRF output is determined by key/context independently
of additional data. Test generation verifies a provisional seal to obtain that output, signs entropy,
then signs the final exact unsigned header. Production verification checks the complete seal first
and uses **only its verified output** to authenticate entropy. The returned `EntropyInput` can feed
`advanceEntropyTime`; a caller-supplied posterior accumulator is not trusted to authenticate itself.

## Evidence

The native profile authenticates twenty selected published tiny trace records: blocks
1, 11, 12, 13, 24, 25, 48, 49, 99 and 100 from both `traces/fallback` and `traces/safrole` at
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. The first/eleventh records are identical across families
(eighteen unique blobs); eighteen selected schedules are fallback; Safrole blocks **48 and 49 are ticket-sealed**.
Both ordinary signatures verify for both modes, and
actual entropy advancement reproduces each complete recorded posterior C(6). The Python helper
only transports pinned header/state fields using existing independent serialization equations.

Real authored ticket/fallback signatures complement the external credentials for both modes. They cover
same-epoch, adjacent and skipped-epoch history, E1 attempt 200, signed-header tampering, invalid
schedule key/ticket identifiers, bad author population, dollar-prefixed domains, nonempty entropy
additional data, another entropy key and first/second backend refusal. A scoped 1,000-call ARC
workload retires temporary rejected candidates. Test-only ordinary-verification observation is
separate from RingVRF counters and leaves successful production output and dependency sources
unchanged. Two result privacy checks and two runtime extraction probes protect authentication.
A failure-only result factory lets the context adapter preserve reasons without duplicating successful
payloads. Its success-forgery precondition is checked both by a compiler rejection and an isolated
runtime probe (the pinned diagnostic is `not reason == None`). Full-profile authored credentials
also cover E600 phase 599 and active index 1022 in a 1,023-record population. Non-author keys
and non-selected schedule entries differ from the valid selected ones, so wrong indexing cannot
pass through repeated-key fixtures.

Run `make check-modules check-unit check-failures check-guards check-python`; reports and fixture
hashes remain under ignored `build/tests/`. Cryptographic success is not a backend security audit.

## Read-only store context and entropy handoff

`src/state/authentication_state.nim` reads parent C(6)/C(11) and supplied posterior C(4)/C(8)
from retained immutable full-state snapshots. Fixed chapter shapes and both dynamic byte ceilings
are checked before copying. Missing chapters are `MissingState`, default snapshots `Uninitialized`,
and malformed exact shapes `InvalidState`. Native refusal and invalid proof/schedule/author causes
remain those of the core; no store write or root hashing is performed by authentication.

Staged C(6)/C(11) are deliberately **not inputs**. The existing entropy updater needs authenticated
entropy to compute the new accumulator; reading it as a prerequisite would create circular trust.
The history needed for seal verification is a fixed rotation of parent words and can be determined
first. The eventual coordinator must similarly derive schedule/admission history without committing
an unauthenticated accumulator, then publish canonical state only after all stages succeed.

The context suite checks all twenty published records even with malformed/absent staged entropy
and time, binds exact causes for required parent/posterior chapter damage, checks preflight ceilings,
first/second native refusal, complete map/root stability, zero store hashing and historical header/
map lifetimes. A separate correctly staged working map consumes the authenticated output through
`advanceEntropyTimeState`, reproducing each complete published posterior C(6) and target C(11)
while preserving schedule, active keys and unrelated state. Other state transitions are supplied
projections, not claimed as executed by this component suite.

The complete-map storage contract remains full-node specific. Future light-node context must use
its own verified state/proof contract; these operations do not compute roots over partial maps or
force full/light schemas into one database.

## Completed scope and next work

This completes the bounded author/seal/entropy authentication increment. The marker dependency
[#18](https://github.com/jacogr/ragnarok/pull/18) is merged, and this branch includes master.
The next planned slice is complete Safrole stage coordination and atomic whole-stage
publication, combining the existing rotation, admission, schedule, marker and authentication pieces.
Parent/extrinsic commitments, wall-clock admission and complete block execution remain separate
checks. Component authentication does not itself establish prior stage lineage or full JAM parity.
