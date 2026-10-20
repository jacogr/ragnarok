# Source-bound report identity and lookup

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex implied authorizer, computereport E and segment-root
lookup; C.1 canonical dictionary order. Vectors remain
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume an opaque completed AuthorizedRefinement. Derive package identity
from its entire canonical original package and authorizer identity from exactly
codehash || raw configuration (no length prefix/domain). Preserve original context,
core, authorization gas and the original execution owner. Accept only canonical
strictly ordered unique lookup pairs whose keys equal all unique package-hash
imports across all original items; direct roots contribute no keys. Prerequisites
and lookup keys share the existing eight-entry budget. Copy fixed entries into
private immutable storage. Separate nominal package/configuration byte policies
bound allocation and hashing before copies; no partial result escapes failures.

This checks dictionary shape, not correspondence of values to referenced reports
or authentication of imported segment bytes. No availability certificate, erasure
coding, complete work-report or state/block publication is produced.

Completion plan: real authorization/refinement owners with repeated package imports,
direct roots and prerequisites; missing/extra/duplicate/descending keys, shared
budget, exact byte caps, default owners/results, copied metadata isolation and
lifetime/replay. Independent fixed hash witnesses, canonical package hash witness,
1000-cycle ARC release; optimized failed-result guards and compiler privacy/nominal/
source rejection. Regress authorized refinement, inventory and formatting.

Next: availability commitments and authenticated input/root correspondence.
M1 framing is complete; full state serialization remains open.

Local evidence: checked optimized macOS native `pvm_report_identity` passes,
including independent Python-hashlib-derived fixed authorizer witnesses and
1000-cycle ARC release at 32576/32576 occupied bytes. The existing
`pvm_authorized_refinement` regression passes with 1000-cycle ARC release at
217264/217264. Five optimized runtime result/owner guards and five compiler
privacy/source/nominal rejections pass. Verification inventory, 19 inventory/
provenance Python tests and pinned formatting pass. Exact-head Linux CI is
independent. No existing production module or shared fixture was changed.
