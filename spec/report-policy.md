# Report admission policy

`src/state/report_policy.nim` consumes immutable `VerifiedGuaranteeCredentials` and a complete-map
`StateStoreSnapshot`. It returns a private immutable `PolicyCheckedReports` only after the whole
batch passes. The owner retains both exact inputs; guarded accessors return retained handles.
Defaults/refusals carry only typed reasons, with no partial values or gas totals.

## Normative scope

Gray Paper 0.8.0 (`07f041dabd073f9018b418e9ee72e79dd2185401`),
`text/reporting_assurance.tex`, `reportcoresareunused`, `reportgas` and `reportcodesarecorrect`:

- Read **parent C(1)**, not the advanced authorization pools or C(2) queues. Each report's
  authorizer must occur in its own core's pool. Preserve order/repeated hashes; no normalization.
- Sum accumulation gas separately for each report, rejecting before addition when the next value
  exceeds remaining capacity. This also prevents uint64 wrapping under Nimony. The caller supplies
  `ReportGasLimit`; both pinned profiles use `Creportaccgas = 10,000,000`.
- Resolve every digest's exact C(255,service) account. Missing service is a distinct refusal;
  present-empty, malformed, unsupported-version and suffixed metadata are invalid state.
  Require the predicted code hash and at least the service's minimum accumulation gas, including
  unsuccessful work. Refinement, authorization and minimum transfer gas do not enter this sum.

Pool value bytes and total hashes are bounded before extraction; metadata must have its exact
89-byte version-zero extent before copying. Stricter policy limits are checked again even though
credentials were certified under an earlier configuration. This stage performs no state writes,
state hashing or PVM execution. Future light-node proofs require a separate contract.

The caller must supply the real admitted parent and matching completed credential context. This
module does not independently authenticate that relationship or make loose extracted records into
admission certificates. Core vacancy is the other half of `reportcoresareunused` and must use the
**post-assurance** C(10), so it intentionally remains outside this parent-policy stage.

## Evidence

Twenty unchanged tiny/full `stf/reports` cases at davxy/jam-test-vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` are pinned individually in `spec/pins.json`.
They cover current/previous rotations, multiple reports, two unauthorized cases, missing service,
wrong code, insufficient gas and high/excess report gas. All original credentials must pass the
real native verifier before checking policy; eight policy projections accept, twelve refuse.
`high_work_report_gas-1` accepts two reports whose combined gas exceeds the per-report cap.
These are policy projections, not full report STF execution or complete-chain parent states.

Python transports original fields and independent codec bytes, checks blob hashes, and refuses
nonempty lookup projections rather than silently dropping them. Native Nim owns every assertion.
Authored cases cover exact/zero caps, uint64 overflow, per-item minimums (including failed work),
late service failure, malformed metadata/pools, absent/default inputs, resource ceilings,
wrong-core membership and retained parents after store/source mutation. Hash-provider refusal
demonstrates that the policy stage needs no hashing. A 1,000-cycle success/late-refusal workload
requires equal ARC live occupancy. Three compiler privacy probes and two isolated default/refused
result-extraction probes protect the certificate boundary.

Reproduce with `make check-modules check-unit check-failures check-guards check-python`, using
pinned Nimony, ARC and checked Clang LTO. Fixture evidence and logs remain under ignored `build/`.

## Next bounded work

[Recent-history and lookup-anchor validation](report-anchors.md) is implemented as separate
read-only stages. Next validate package uniqueness/dependencies and segment-root mappings. Post-assurance core capacity and atomic C(10) assignment follow before
integration into the block coordinator. Accumulation/PVM execution remains later work.
