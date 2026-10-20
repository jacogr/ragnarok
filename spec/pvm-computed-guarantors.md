# Authenticated guarantor assignments for computed reports

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
reporting_assurance.tex current/prior guarantor rotations, Phi and guarantee-slot
freshness; utilities.tex shuffle. Vectors remain
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume RosterEligibleComputedReport and independent local resource limits.
Derive core/epoch/rotation from original configured computation, candidate time
from its authenticated admitted header, and previous roster/C6 entropy/cumulative
C5 offenders from that exact posterior snapshot. Bound every serialized chapter
before copying, require exact decoding and bounded offender extraction, and use
the existing real planGuarantors implementation. Retain the computed source and
immutable current/prior plan after full success only.

Queries take nominal GuaranteeSlot and GuarantorIndex, delegate rotation freshness
and selected-roster index checks to guarantorAt, require the assigned core equal
the original computed core and reject a null Ed25519 identity after Phi. A copied
query result is ordinary data, not a signing certificate or constructor input.
No external roster, entropy, offender list, candidate time or loose plan is accepted.
Current core/shard eligibility stays certified by the source even for a larger
previous roster. Invalid original rotation profiles refuse before hashing.

Completion plan: original rotation 4 captured before real computation/configuration;
real signed ordinary, same-epoch rotation and parent9->posterior6 epoch fixtures;
independent literal shuffle/rotation tables; current/prior slot boundaries and
roster index populations; wrong core and cumulative-offender refusal; precise
byte/record/offender limits; early and late real backend failures with no partial
plan; no hashes during queries; immutable copies, detached lifetime, caller
publication and 1000-cycle ARC release; strict runtime and compiler guards.
Extend existing test fixture through default-preserving optional controls and run
its original native suite as an affected consumer. Never forge successful stages
to reach impossible malformed/missing posterior chapters.

Next: source-bound credential/transcript integration. Report inclusion, full
transition-policy/chainspec equivalence, exporter trust, availability, signature
verification and signing remain open. M1 framing is complete; full state
serialization and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit
SUITE=pvm_computed_guarantors` passes real signed original PVM/anchor/configuration/
roster sources at candidate slots 2, 8, 12. Original rotation 4 is captured before
computation. Independent hashlib zero-entropy permutations6=[5,2,1,4,3,0] and
9=[2,1,0,5,3,8,4,6,7] produce the exact literal current/same-epoch/prior-epoch core
tables checked by native queries. Slot 8 admits prior slots 4..7 and current 8;
slots 3/9 refuse. Epoch-crossing slot 12 admits previous 8..11 with nine validators
and current 12 with six; previous index 8 succeeds for computed core 1 while current
index 6 refuses. Pre-genesis, maximum nominal times/indices and wrong core refuse
precisely. Current core/shard eligibility remains retained independently.

An earlier C5 offender (real Ed25519 seed 16 identity) is absent from the candidate's
empty offender marker yet its otherwise correctly assigned key is rejected after
Phi. Exact previous-roster 3025 and judgment 36 byte ceilings pass; 3024/35, record 8
against previous 9 and offender 0 against one cumulative offender refuse. Oversized
local record ceilings are clamped to the configured protocol bound. Original
rotation 5 (not dividing epoch 12) and 65535 (greater than epoch 12) reject without
hash attempts. Real early/current and later prior-table hash failures return no
partial context, including refusal after one and two successful calls. Completed
queries make no new hash attempts even under backend refusal.

Copied records, detached owner lifetime and caller map publication preserve source
and tables. Fresh warmed 1000-cycle ARC occupancy, including repeated late planning
refusal, is 389440/389440 bytes. The affected original roster suite also passes,
with its previous 320176/320176 ARC result unchanged under default fixture controls.
Eleven strict optimized result/query guards, eight compiler privacy/source/nominal
slot/index guards, formatted semantic checks, inventory, 20 affected tooling tests
and pinned formatting pass. Only the default-preserving test helper changes among
previous source/build inputs; lower production modules and all pins are unchanged.
Remote CI has not been requested.
