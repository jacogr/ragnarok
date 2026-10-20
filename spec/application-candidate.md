# Application candidate preparation

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Compose existing block admission,
report planning and PVM stopped execution into a finalized successor producer.
This is implemented-prefix validation/execution, not consensus or full JAM parity.
No network acquisition, new codec or PVM effect-selection rule belongs here.

## Contract and completion tests

Prepare from one ApplicationChain, an immutable OwnedBlock, explicit ancestor
headers and explicit stage policies. Select the parent header, exact original map
and PVM parameter tuple from the retained canonical head; callers cannot substitute
an unrelated parent or parameter tuple. Refuse mismatched admission core/epoch/
validator domains before hashing. Retain existing explicit round gas configuration
and every lower-level bound/support gate without inferred budgets or silent clamping.

Fork the selected store privately, run advanceBlockState, planBlockReports, admitted
queue/initial-round planning, runBlockAccumulation, driveAccumulation and finalization.
Only complete finalized success exposes a successor. Every failed alternative
retains only its actual selected reason/failed child, never an earlier successful
prefix. Preparation leaves canonical state/history and RPC unchanged on success
and failure. Parameters are always taken from the selected head for PVM execution.

The enqueue adapter checks single-slot backpressure before any preparation work,
then retains the finalized certificate under explicit composition limits. Services
exposes that adapter without exposing its mutable canonical owner. Adoption still
happens on a later service tick and rechecks exact parent identity; no synchronous
preparation success publishes a partial prefix or bypasses the handoff contract.

Test genuinely signed blocks with real guest execution against configured seeds,
manual-stage parity, all reachable stage failure alternatives, selected head/profile binding,
unchanged canonical state, deferred RPC publication, Busy hash-free admission,
scoped input lifetime and failure/retry. Add default/selected-accessor runtime and
privacy guards, affected handoff/service and executable lifecycle checks, inventory,
tooling and pinned formatting. Measure repeated success/refusal ARC ownership.

## Observed verification

Checked optimized native `application_candidate` passes with signed blocks and two
actual halt guests consuming 44 gas. Prepared state/root and hash work match the
manual lower-level pipeline. The suite checks selected-head PVM parameters, all
reachable pipeline-stage refusals, unchanged canonical state, hash-free Busy
backpressure, deferred real loopback RPC publication, and retry after primitive
refusal. All 1,000 success/refusal cycles retain 151,968 occupied bytes before and
after. Affected `application_handoff` passes with 118,800 occupied bytes unchanged
over 1,000 cycles.

Three result privacy probes, the raw-wire nominal rejection and all eleven strict
default/selected-stage runtime guards pass. The executable builds; registered
state-policy standalone/mesh lifecycle checks and existing RPC/UI, configured
genesis/service queries and shared telemetry startup pass. The owned-block producer
is exercised through public component APIs and real RPC sockets; the executable
still has no network block-acquisition loop.

Inventory passes with 205 native suites, 140 failure families and 1,883 data-driven
probes. All 40 affected verification/failure/mesh/RPC harness Python tests pass.
Pinned Nim/Rust formatting and whitespace checks pass. These are local macOS
results; complete/Linux verification remains in CI.

## Remaining work

Network block acquisition, asynchronous execution scheduling and a live producer
loop remain open. Consensus/fork choice, durable restart and full/light database
modes remain open. PVM owns execution/effect selection and finalized successors.
M1 framing is complete; full state serialization and JAM/STF parity remain open.
