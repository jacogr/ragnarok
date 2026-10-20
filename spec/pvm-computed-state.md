# Exact execution-state binding for computed reports

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, header.tex
parent/prior-state/extrinsic commitments; work_packages_and_reports.tex computereport
and historical authorizer lookup. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume completed ComputedReportLinks and BlockAdmissionResult. Derive the
original report's retained authorization execution snapshot through its immutable
source chain. Require sameStateSnapshot with the completed admission's exact
parent-state snapshot. Retain the original links and BoundBlock only after the
whole check succeeds. No caller-supplied map, root, header, report or replacement
execution context can stand in for either completed owner.

Snapshot identity is deliberate: copied handles and unchanged forks retain the
same version, while independently rebuilt equal-root maps and changed/new versions
do not. This is a composition ownership rule, not a new consensus rejection rule.
Callers must execute from the exact snapshot they intend to bind. The admitted block need not contain this report; report inclusion and credential
publication are not established. The existing block admission checks that map's C11 time against the parent header and its root
against the child's prior-state field, plus complete sealed-parent hash and all
extrinsic commitments. It does not authenticate the parent's consensus lineage.

This stage binds only the main report's original execution map. It does not bind
exporter witnesses' independent execution states, certify the complete Parameters
snapshot, establish chain finality or full block validity, validate claimed recent/
lookup anchor tuples or ancestry, enforce freshness, active assignment/population,
prove distribution/assurance or authorize signing/publication. Historical lookup
may run from a later state; do not invent equality between that state's root and
the package's claimed lookup-state root. Those distinct checks remain open.

Default sources/admissions and mismatched versions return typed reasons alone.
Source validation precedes admission validation. Fixed acyclic handles are the
only new retained allocation; no variable-size allocation, hash, re-execution,
map copying or state mutation occurs. Getters retain immutable source, admitted
block and exact original state. Allocation exhaustion keeps the existing fail-stop
policy.

Completion coverage: genuine original PVM execution from a
complete map with C11, real successful block commitment admission, fixed literal
sealed-parent hash witness, exact/copy/unchanged-fork identity acceptance,
independently rebuilt equal-root and changed/stale-state refusal, default/failed
admissions, preserved claimed lookup-root distinction, no new hashes even under
backend refusal, retained source/state/admission and detached lifetime, caller-store
mutation isolation and 1000-cycle ARC release. Compiler privacy/nominal rejections
and strict optimized result/accessor guards include genuine positive controls.

Next: bind recent/lookup anchor tuples and ancestry to admitted chain context
before signing eligibility and guarantee publication. M1 framing is complete;
full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit SUITE=pvm_computed_state`
passes real original PVM execution and completed block commitment admission over
one exact C11-bearing complete map. The full 297-byte sealed-parent identity
matches a frozen independent hashlib witness; the Python reference test also
rejects its unsigned-prefix hash. Exact/copied/unchanged-fork snapshots succeed;
an independently admitted equal-root rebuild and a valid changed-map admission
return StateMismatch. A genuinely incorrect child prior-state commitment is
refused by block admission and cannot produce a state-bound report. Default
source/admission/getter results preserve typed refusal and precedence.

The test deliberately retains a claimed lookup-state root different from the
actual execution root, demonstrating this boundary does not impose a new
historical-lookup restriction. Original wire/source/admission/map retention,
caller-store publication isolation, detached lifetime and zero new hashes under
backend refusal pass. Fresh 1000-cycle ARC occupancy is 40816/40816 bytes in the
isolated warmed workload. Seven strict optimized result/accessor guard probes
and five compiler privacy/nominal guards pass with genuine admitted-state
controls. Formatted unit/driver semantic checks, inventory, 20 affected tooling
tests, the independent parent-hash reference test and pinned formatting pass.
All 2985 prior source/build inputs are byte-identical; prior primitive/report/
lookup evidence remains reusable. Full logs, source identity and reuse proof
remain in ignored `build/computed-state-*` files. Exact-head Linux CI remains
separate; remote checks were not requested.
