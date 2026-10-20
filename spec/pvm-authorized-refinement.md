# Authorization-bound refinement composition

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`work_packages_and_reports.tex` computereport, E's authorization-trace condition,
ordered I and item-to-digest C; `pvm_invocations.tex` Psi_I/Psi_R. Vector pin
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` remains unchanged.

Scope: consume only a completed opaque AuthorizationInvocation. Reject default
owners, all protocol work errors (preserving their kind), and successful traces
above 49152 bytes before copying trace or inspecting inputs/refinement/digest
policies. A separate local trace-copy cap refuses locally after the protocol gate.
Successful empty trace is valid. Extract state, package, parameters, core and trace
only from the original authorization owner; no public constructor accepts detached
replacement tuples, a previously prepared report, or caller-supplied trace bytes.

Run ordered report refinement with those exact inputs and then construct canonical
source-bound digests. Only full completion returns an immutable acyclic owner
retaining original authorization and matching digests/report/exports. Local child
refusals preserve the failed report alternative or digest reason with guarded
accessors; no partial report/digest prefix escapes. Authorization gas stays separate
from item gas. Shared blob budget, declared export offsets and I error replacement
are inherited from the existing report layer. External input preimages remain
borrowed synchronously and their authentication remains a separate gate.

Completion: real authorizer and multiple refinement services in one complete map;
actual fetched authorization trace propagation; immutable source/core/package/state/
parameter binding despite caller replacements; accepted empty and exact-limit trace,
over-limit and protocol-error precedence over invalid inputs/local caps; ordered
exports, normalized digests and shared output budget; typed late refinement/digest
refusal and replay/lifetime/copy isolation; optimized result/reason/owner guards,
compiler privacy/nominal/source rejection, fresh 1000-cycle ARC release. Regress
Is-Authorized and work-digest suites; inventory/tooling and pinned formatting.

Local evidence: checked optimized native `pvm_authorized_refinement`,
`pvm_authorization_invoke` and `pvm_work_digests` pass with fresh 1000-cycle ARC
release, respectively 217264/217264, 975440/975440 and 43408/43408 occupied bytes.
Ten optimized runtime alternative/reason/owner guards, six compiler privacy/nominal/
source rejections, 19 inventory/provenance Python tests, verification inventory and
pinned formatting pass. These are local macOS results; exact-head Linux CI remains
independent.

Next: report lookup/identity and availability assembly. Segment-root dictionary
certification, authorizer identity/availability commitments, authenticated state/
freshness/inputs, complete work-report construction and publication remain open.
State retains block composition and final publication. No full/light storage change.
M1 framing is complete; full state serialization remains open.
