# Current-source guarantor eligibility for builder work

Target: Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`, reporting/assurance
sections on guarantor assignments, and JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`
CE133/146. Link membership alone does not establish that the local validator can guarantee a
submission on its selected core.

A network work CPU job must derive eligibility from its original complete canonical source:
C(5) offenders, C(6) entropy, C(8)/C(9) current/previous rosters and C(11) time. It executes the
existing GP shuffled/rotated assignment planner, preserving posterior offender nulling. Requested
cores must exist and the actual local Ed25519 identity must occupy that core. As the pinned GP
states, only the first N/3 configured cores are active; N may be smaller than 3C. No roster or
entropy is inferred from the core count or an untrusted peer claim.

Observed time must not precede the source and must remain in the source epoch; an unknown next
epoch is refused until canonical progress supplies its context. Source/codec/assignment failures
retain their genuine selected causes. Success contains detached fixed eligibility facts, not a
canonical owner, private signer, signature, availability or inclusion certificate. Services remains
the full/light selection boundary and keeps all selected-state aliases inside the shared CPU lease.

Completion evidence must cover real nontrivial assignments, inactive cores, changed rotation,
unknown epoch, absent local membership, actual offender nulling, current/previous populations,
malformed/missing/oversized components, real worker collection and repeated release. Application
activation, transport dispatch and report credentials remain separately identified work.

Verified locally: `jamnp_work_duty`, `jamnp_staged_work_streams`,
`jamnp_managed_work_submission`, `application_proof_worker`, `application_proof_services`
and `light_runtime`; application build and actual lowering rejection of copied Services and
StateProofWorker owners. The live stream suite rejects wrong-core and unknown-epoch requests
before body admission. Independent six/nine-validator assignments, rotation changes, inactive
cores, actual C(5) offender nulling and the GP null-validator identity have focused witnesses.
The duty suite releases 1,000 cycles without retained ARC growth (58,864 bytes before/after).
