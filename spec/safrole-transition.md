# Atomic authenticated Safrole stage

Target: Gray Paper **0.8.0**, revision `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
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

`make unit SUITE=safrole_transition` executes three independently authored current
Thin component cases: slots 0→1, 1→7 and 11→12. The mathematical VRF reference
supplies credentials; independent byte/hash equations supply markers, expected
entropy/time and all five posterior chapter encodings. Parent C(4)/C(6)/C(7)/C(8)/
C(9)/C(11) plus an unrelated sentinel are retained. This is Safrole component
publication, explicitly not complete sixteen-chapter state/STF parity.

Every expected chapter byte is compared. Parent immutability, replay rejection,
retained results, exact/one-short write budgets, malformed/missing state, marker
and signed-message damage, early/late digest refusal and first/second ordinary
verification refusal remain tested, including within-epoch and crossing rollback.
The first/last digest and 1000-cycle ARC checks retain no staged state on failure.

The advanced published traces cannot supply current positive credentials: their
Thin R positions are incompatible, as recorded by [authentication](safrole-authentication.md)
and [the primitive contract](bandersnatch.md). No fixture repair or synthesized
published post-state is made. The earlier twenty IETF trace passes remain
historical evidence; current upstream complete signed-trace parity is blocked by
that exact source defect, separately from current component execution.

## Next bounded work

After this stage, the next planned slice is a block-admission boundary: bind the immutable decoded
block to parent/header/extrinsic commitments and compose the supplied projections safely. Complete
disputes, accumulation, PVM execution and full block import remain separate future work.
