# Guest consumption of the complete assured input list

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, fetch selector14
and canonical C.2 accumulation input-list framing; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author an original FetchList guest before any computation/signing. It fetches
three bytes at offset0 of the complete invocation input list, with both item
registers set to maximum uint64, then writes those bytes to storage. Selector14
must ignore both item registers. Keep original gas/funding and dual entry layout.

Independent oracle: the original single-input invocation begins[1,0,hash0],
whereas the actual two-input successor begins[2,0,hash0]. The first byte is the
single compact input count, the second the first C.2 operand tag0, and the third
its packageHash byte0. The oracle reads actual source metadata and uses literal
framing, not an encoder round-trip. The guest's selected bytes must survive full
state composition and atomic chain publication.

Measure the complete real capture extent as one count byte plus the two canonical
operand extents. Exact ceiling succeeds; one less must refuse before execution.
Actual guest copy and final effect-byte ceilings remain independent. Selector14
request3 costs287+ceil(400*3/1024)=289, storage write2447 and the single prepaid
block at most997 under the existing bound; assert actual gas>2736and<=3733.

Completion: both original/successor real terminals and exact bytes, complete
input capture, parameter/parent identity, history/activity, canonical state/view,
resource refusals, detached lifetime and1000 full guest/composition/publication
ownership cycles. Recheck existing shared-factory original/storage, successor
outcome and individual-operand suites. Inventory/tooling and pinned formatting
are required. Production APIs and protocol controls remain unchanged.

Next: exercise clipped input ranges and returned full lengths in actual guests.
M1 framing complete; full serialization, whole-block parity and full chainspec
equivalence remain open.

Observed local native evidence: real original storage begins[1,0,hash0] and the
successor begins[2,0,hash0], despite both ignored item registers containing maximum
uint64. Both actually Halt/Regular. The full canonical capture succeeds at its
exact count-plus-two-record extent and refuses at one byte less with RunnerFailure/
DispatchFailure/LimitExceeded. An exact three-byte guest copy passes; cap2 refuses.
A final effect-byte cap2 preserves CompletionFailure/BatchFailure/LimitExceeded.
The original parent and view stay unchanged after every refusal.

Actual selected bytes survive complete state composition and atomic slot3
publication, with footprint38/item1/balance50, timestamp3, history3, activity
reports2/refinement0/actualgas, all29 parameters and finality1. Detached canonical
receipt lifetime passes. Actual gas is greater than2736 and no more than3733.
One thousand full guest/composition/publication cycles retain1459632/1459632
occupied bytes.

All three affected older suites pass again: individual operand guests retain
1406672/1406672, seven original storage modes2933856/2933856, and seven assured
outcomes3162032/3162032 over1000 cycles each. Only the shared guest factory changes
among3443 prior inputs;3442 remain identical. All production code is unchanged.
Semantic checks,35 verification tooling tests, inventory194 families/2436 probes/
268 native suites, and pinned formatting2334 Nim files plus Rust pass. Local
macOS checked-release evidence; remote CI was not requested.
