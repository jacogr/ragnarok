# Report package context

`src/state/report_packages.nim` adds bounded read-only package relations and a state-backed
`PackageCheckedReports` owner after policy/recent-anchor validation. It does not establish lookup
ancestry, core vacancy, full report admission or C(10) publication.

## Pinned behavior

Gray Paper 0.8.0, `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/reporting_assurance.tex`, Contextual Validity of Reports:

- Incoming work-package identities must be unique, regardless of segment roots or core order.
- They must not occur in recent reported-package dictionaries, any accumulated set, any ready
  report's own package identity, or any **prior** availability assignment. A prior assignment still
  excludes its package if assurances/timeout would clear that core later in this block.
- Prerequisite hashes resolve only from recent history or the whole incoming batch. Queued or
  accumulated identity alone cannot satisfy a prerequisite. Ready dependency hashes are not
  themselves ready report identities and cannot incorrectly exclude an incoming package.
- Lookup pairs must belong to the union of recent and incoming package/segment-root pairs. Exact
  pair membership establishes both key eligibility and correct associated root. Missing keys and
  wrong roots both return `InvalidSegmentRoot`, matching the published STF error classification.
- Collect the whole incoming set before checking dependencies. Forward references, self references
  and cycles are allowed; do not add DAG rules or execute accumulation here.

`inspectReportPackages` returns a reason only, accepting verified credentials, a retained history
snapshot and a stable borrowed existing-package summary. It never constructs an application
certificate. This exposes the mathematical relation independently of how complete state or a
published STF contract supplies its prior-pipeline summary.

`checkReportPackages` requires `RecentAnchoredReports`. It derives the exact immutable parent from
that certificate's policy owner, then reads parent C(10), C(14) and C(15). It bounds chapter bytes
before copying, decodes under explicit matching core profiles, requires exact complete values and
collects every prior assignment/ready report/accumulated identity before using the shared relation
checker. Missing state, malformed state, resource limits and each relation refusal remain distinct.
Corrected history retains the parent's package dictionaries: parent-root correction changes no
package mapping. The earlier stage's actual-block/context preconditions still apply.

Independent caller byte/count policies bound parent decodes. `indexItems` separately bounds each
sorting index and checked aggregate growth before native conversion/allocation. Indices are private
copies; sorting these mathematical lookup structures does not normalize or repair protocol fields.
Membership uses binary search. Existing duplicate keys across union sources are ordinary repeated
set evidence, and exact key/root membership preserves the paper's union-of-pairs semantics.

Default/failed tagged results contain only reasons, never partial indices or reports. A successful
private acyclic ARC owner retains its exact preceding certificate and immutable decoded parent
views. Its `packageRecent` accessor supports later lookup/capacity composition. No hashing, state
writes, ancestry shortcuts or partial-light-state assumptions occur in this stage.

## Evidence and reproduction

Thirty-two unchanged tiny/full report STF JSON inputs at davxy/jam-test-vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` are pinned by raw blob SHA256 in `spec/pins.json`.
Twenty relation projections accept; ten refuse on duplicate, missing prerequisite or invalid lookup
pair; two oversized dependency unions stop at the existing combined-eight-entry codec boundary.
All thirty structurally valid cases first pass their original signatures, policy and recent-anchor
checks. Original nonempty segment-root dictionaries are now serialized by the independent JSON
oracle instead of being omitted; original order, keys, roots, signatures and expected values remain
unchanged. Earlier empty-lookup-only fixture families retain their explicit guard.

The reports STF supplies `known_packages`, not its physical C(14)/C(15) chapters. Tests feed that
original summary to reason-only relation inspection. They do not invent which chapter/slot held an
upstream identity or claim complete reports-STF/lookup-ancestry execution. Separate authored native
contexts verify the state-backed adapter and each actual exclusion source.

Authored tests cover incoming duplication, each prior pipeline source (including last ring rows),
ready dependency/identity separation, missing versus recent/current prerequisites, cycles and self
references, exact and wrong roots, malformed/missing/suffixed chapters, exact and exceeded index
budgets, profile mismatch, empty batches, default owners, detached-byte mutation and retained
certificates after temporary context scope. Provider refusal proves the stage does not hash.
A 1,000-cycle success/later-report-refusal workload requires equal live ARC occupancy. Three
compiler privacy probes and two isolated runtime extraction probes protect the result boundary.

Run `make check-modules check-unit check-failures check-guards check-python` using pinned Nimony,
ARC and checked Clang LTO. Generated source evidence, fixtures and logs stay under ignored `build/`.

## Next bounded work

Check post-assurance core vacancy and plan new C(10) assignments with candidate registration time.
Then bind the completed report stages to one admitted block and integrate atomic publication into
the block coordinator. Accumulation/PVM execution remains later work.
