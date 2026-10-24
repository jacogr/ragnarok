# Safrole author, seal and entropy authentication

Target: Gray Paper **0.8.0**, revision `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/safrole.tex` equations `ticketconditiontrue`, `ticketconditionfalse` and `vrfsigcheck`,
and `text/header.tex` posterior-active author-index definition. The aligned gp-next vector revision and ark-vrf 0.6.0 Thin v1 backend are recorded
in [the primitive contract](bandersnatch.md); all twenty consumed trace JSON blobs are SHA-256 pinned.

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

## Current evidence and reproduction

The aligned gp-next revision `23061ae1f9b51171c01387e7dde0f15794c98e24`
contains current Safrole stage proofs, but the twenty selected signed tiny traces
retain incompatible ordinary credentials. The first fallback header's seal and
entropy proof have nonsquares in the Thin R position. All twenty unmodified
headers are required to fail as `InvalidSeal` after one verification attempt;
there is no historical verifier fallback or successful entropy handoff claim.

Three current Thin positives use a separate mathematical hash-to-curve/signature
oracle, verified against all seven complete Draft 35 vectors. They cover slots
0→1, 1→7 and 11→12 with independently encoded expected C(6), complete signed
headers, schedule and active records. They are component maps, not full JAM states.
The existing authored native ticket/fallback, wrong-domain/AD/key/index, ceiling,
backend-refusal and full-population boundary cases remain active. The 1000-cycle
checked ARC measurement retains equal before/after occupancy.

Run `make unit SUITE=safrole_authentication`; source hashes and refusal scope are
preserved in preparation evidence. `tests/test_safrole_current_fixtures.py`
independently freezes the current output anchors, component-scope limits and
exact source incompatibility witness. Historical twenty-positive IETF results
belong to the earlier `d3c089c...`/0.2.2 profile, not current Thin evidence.

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

The context suite rejects all twenty unchanged historical trace credentials as `InvalidSeal`,
with exactly one ordinary verification, zero store hashing and unchanged parent/staged maps.
Three independently authored current Thin contexts authenticate with malformed/absent staged
entropy and time. Those positive contexts retain the required parent/posterior chapter damage
checks, preflight ceilings, first/second native refusal, complete map/root stability and retained
header/map lifetimes. A correctly staged working map consumes each authenticated output through
`advanceEntropyTimeState`, reproducing the independent posterior C(6) and target C(11) while
preserving schedule, active keys and unrelated state. Other state transitions are supplied
projections, not claimed as executed by this component suite.

The GP/Thin pin migration updated fixture preparation and the core authentication suite but
missed this state-context consumer. Master CI run 40088339613, unit shard 11/16, exposed its stale
20-case successful-authentication assumption. The focused repair accepts the complete 23-case
transport and preserves both historical refusals and current positive state-publication checks.

The complete-map storage contract remains full-node specific. Future light-node context must use
its own verified state/proof contract; these operations do not compute roots over partial maps or
force full/light schemas into one database.

## Completed scope and next work

This completes the bounded author/seal/entropy authentication increment. The marker dependency
[#18](https://github.com/jacogr/ragnarok/pull/18) is merged, and this branch includes master.
[Complete Safrole stage coordination and atomic whole-stage publication](safrole-transition.md)
now combines the rotation, admission, schedule, marker and authentication pieces. The next planned
slice binds block admission to parent/header/extrinsic commitments.
Parent/extrinsic commitments, wall-clock admission and complete block execution remain separate
checks. Component authentication does not itself establish prior stage lineage or full JAM parity.

## Related block and report consumers

The same master run also failed `block_admission` and `report_admission` in unit
shards 6/16 and 9/16. Their ten unchanged historical blocks retain exact commitment,
parent linkage and root checks, then assert current-profile refusal: `safrole/12`
and `safrole/13` fail ticket admission with `InvalidProof`; the other eight fail
seal authentication with `InvalidSeal`. Failure preserves every original state entry.

Three independently signed Thin blocks provide positive block/state/report paths.
Their explicit parent headers are opaque historical inputs; current child seals
bind those exact parents, independently Merklized component maps and empty-body
commitments. Same-epoch and epoch-crossing expected Safrole chapters come from
the existing mathematical reference. These component maps do not claim complete
JAM state or historical trace parity. Existing commitment-tampering, ticket ceiling,
backend refusal, staged disputes rollback, lifetime and ARC witnesses remain active.
