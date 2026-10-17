# Atomic authenticated Safrole stage

Target: Gray Paper **0.8.0**, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/safrole.tex`: validator rotation/blacklist filtering, historical entropy rotation, ticket
admission, slot-sealer selection, epoch/winning-ticket markers, seal/entropy authentication and
entropy advancement. Existing source, vector and primitive dependency pins are unchanged.

## Boundary and ordering

`advanceSafroleState` takes an initialized full-state store, a structurally decoded signed header,
its structurally decoded tickets, supplied **posterior disputes offenders**, and one shared finite
chain/resource policy. Offenders must already be canonical. It does not execute disputes, bind the
submitted ticket projection to a complete block commitment, validate parent/extrinsic commitments,
check wall-clock admission or execute the other block transitions.

The coordinator retains the exact parent snapshot and uses the header slot as its sole target:

1. Validate fixed parent entropy/time and input ceilings before private work.
2. Copy the store handle, sharing only immutable parent bytes. Rotate pending/active/previous
   validators and compute the pending ring on this private handle, while parent time is retained.
3. Derive **only historical entropy[2]** from parent history: parent entropy[1] on any epoch
   crossing, otherwise parent entropy[2]. Admission and schedule selection need no new accumulator.
   No dummy VRF, placeholder accumulator or unauthenticated entropy hash is introduced.
4. Authenticate/admit every submitted RingVRF ticket against the rotated pending ring. Select the
   schedule using the **parent** contest and posterior active roster; preserve admitted tickets.
5. Derive/check header markers using the original contest/entropy and posterior pending keys.
6. Authenticate the seal and entropy proof under the selected indexed author. Advance entropy
   using only the verified output and original parent accumulator/history.
7. Apply changed C(4), C(6), C(8), C(9) and C(11) together to the original store. This is the sole
   canonical publication point; earlier rotation roots remain private and are discarded.

Any refusal leaves every original byte and commitment unchanged, including after successful
rotation, ticket verification or seal authentication. Success retains the immutable complete-map
snapshot and authenticated exact header. Replaying it rejects on the already advanced slot.
Private tagged results expose only successful payloads or the selected stage's typed refusal;
preflight failures contain only a reason. Allocation exhaustion remains fail-stop.

Store limits still apply to the private rotation batch (three writes on crossing) and independently
to the final atomic changed-chapter batch (at most five writes). Unchanged entries are not written.
C(7), C(5) and unrelated entries are preserved. These are complete full-node maps; partial light
state requires its own verified state/proof contract and must not be treated as a complete root.

## Evidence and reproduction

The native `safrole_transition` profile executes twenty signed tiny trace records already pinned
for [authentication](safrole-authentication.md): blocks 1, 11, 12, 13, 24, 25, 48, 49, 99 and 100 in
both `traces/fallback` and `traces/safrole`, at vector revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Eighteen use fallback seals and two use ticket seals.
The helper transports original parent chapters, actual ticket proofs, the supplied posterior
disputes chapter and five expected posterior chapters. It implements no transition algorithm.
The native test supplies no posterior roster, ring, schedule or entropy projection to the stage.

Every complete changed chapter matches the published posterior bytes. Input maps retain C(7) and
an unrelated sentinel; the tests verify parent immutability, replay rejection, retained snapshots
and first/second ordinary-verification plus first/last digest refusal. Native setup owners retire
on all exercised paths. These projected complete maps do not claim to reproduce a whole-block
post-state root: other JAM transitions are intentionally outside this bounded stage.

Run `make check-modules check-unit check-failures check-guards check-python`; native profiles,
exact source/fixture hashes and logs remain under ignored `build/`. Live networking is unchanged.

## Next bounded work

After this stage, the next planned slice is a block-admission boundary: bind the immutable decoded
block to parent/header/extrinsic commitments and compose the supplied projections safely. Complete
disputes, accumulation, PVM execution and full block import remain separate future work.
