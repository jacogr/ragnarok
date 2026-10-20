# Complete configured parameter binding for computed reports

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix B
fetch parameter tuple and work_packages_and_reports.tex computereport; existing
configured chain-snapshot/header contracts. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume LookupAnchoredComputedReport and a completed BlockSnapshotResult
from the configured parent chain context. Require exact original execution-state
snapshot identity, the full parent header identity and slot already selected by
admission, and equality of every one of the 29 original Parameters fields with
the configured context. Retain original computed provenance and only fixed copied
context facts/immutable map/header handles after complete success. No detached
parameter tuple, map, header, validator count or mutable copied facts can replace
the completed configured parent input.

Add blockSnapshotContext to the existing chain snapshot result API. Its success
contract directly projects only fixed Parameters, state/header handles, full
header hash, slot and parent active-population metadata from private completed
storage. It excludes RPC key/service indexes and exposes no mutable map. Public
copied facts are not a certificate and are never accepted as constructor input.
The projection and new composition perform no hashing, map/index copying,
variable-length allocation, guest execution or state publication; only fixed
acyclic provenance ownership is newly retained.

The configured snapshot inherits the caller's trusted chainspec/parent context;
this is an exact configuration binding, not consensus/finality authentication.
Parent C8 population is metadata only. Reporting eligibility requires the
posterior active set after Safrole, which may change at an epoch boundary; do not
check report erasure shards or select guarantors using the parent population here.
Posterior roster/assignment/evaluation-slot eligibility, exporter-state trust,
availability assurance, report inclusion, credentials and signing remain open.

Completion coverage: genuine C8/C3/C11 original computation,
block/state/recent/lookup owners and configured parent capture; exact parent/map/
all-field acceptance, equal-root rebuilt-owner and foreign parent refusal;
independent mutation of each parameter field including matching core/epoch with
other fields changed; failed/default contexts, copied facts unable to forge a
context, no new hashes or index allocation on successful/refused projection and
binding, source/map/header/config-copy and detached lifetime, caller-store
publication isolation and 1000-cycle ARC release. Compiler privacy/nominal and
strict optimized result/projection/accessor guards have genuine positive controls.

Next: source-bound posterior active-roster and guarantor assignment eligibility,
then availability/signing integration. M1 framing is complete; full state
serialization and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit SUITE=pvm_computed_profile`
passes genuine C8/C3/C11-bearing original PVM computation, block/state/recent/
lookup stages and configured parent capture. Each of all 29 parameter fields
is independently changed in another successfully captured same-parent/map
context and returns ParameterMismatch, including a deposit change with identical
cores/epoch. Independently admitted equal-root rebuilt maps and changed full
parent seals return StateMismatch and ParentMismatch respectively. Failed/default
contexts and result/accessor defaults preserve typed refusal.

Fixed context extraction leaves occupied memory unchanged while the projected
value remains live. Generated optimized C was inspected: the projection takes
a borrowed GenesisResult pointer, reads fixed fields directly and retains only
state/header references; it never accesses key/service indexes or allocates them.
Copied facts cannot replace the retained map, parent or parameters. Caller-store
publication isolation, detached source/context lifetime and zero new hashes under
backend refusal pass. Fresh 1000-cycle ARC occupancy is 48768/48768 bytes in the
isolated warmed workload.

Ten strict optimized result/accessor/projection probes and six compiler privacy/
nominal guards pass with genuine configured-parent controls. Failed projections
are selected dynamically to exercise runtime contracts beyond the compiler's
literal-variant rejection. Formatted unit/driver semantic checks, inventory,
20 affected tooling tests and pinned formatting pass. All 3025 other prior
source/build inputs are identical; removing only the new context type/projection
from genesis.nim reproduces its prior bytes exactly. Existing capture behavior
and all pins remain unchanged. Full local logs, source identity, lowering excerpt
and reuse proof remain in ignored `build/computed-profile-*` files. Exact-head
Linux CI remains separate; remote checks were not requested.
