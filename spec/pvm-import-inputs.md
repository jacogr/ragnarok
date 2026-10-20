# Package-bound imported input ownership

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex E, segrootlookup, importsegmentdata and
justifysegmentdata; merklization.tex constant-depth inclusion. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume VerifiedExtrinsics and derive its original OwnedWorkPackage;
accept exactly one ordered row of VerifiedImport handles per work item. Require
every original import occurrence, including repeats, and match each verified
leaf ordinal and root to its manifest reference. Direct-root imports resolve to
the literal root. Tagged package references resolve through an explicitly
supplied canonical SegmentLookup dictionary whose keys equal exactly the set of
package references across all items. Reject missing, extra, duplicate or descending
keys and preserve the shared eight-entry prerequisite/dependency ceiling.

Before retaining variable rows, check all geometry, verified handles, root/index
matches and local occurrence/witness-byte limits. Witness-byte accounting sums
4104 + 32 * sibling-count per occurrence, even when handles share storage.
Fixed lookup storage has at most eight entries; the original extrinsic owner
retains its separately budgeted payload. No hashing or leaf/proof copying is
needed: VerifiedImport already owns immutable authenticated bytes. Success owns
independent row descriptors, fixed copied lookup values and the original verified
extrinsics; extraction returns only immutable handles or independent copies.
Default/refused alternatives expose no partial package/input certificate.

This authenticates inclusion against the resolved roots and binds the original
manifest, dictionary and extrinsics together. It does not certify root freshness,
known/unexpired status, package-hash/root correspondence, actual export cardinality,
authorization, trace or prior execution. Supplying a different dictionary and a
matching valid inclusion proof can select a different root for a package key;
a later trust-policy layer must authenticate that correspondence. Consumers must
derive their package and inputs from this owner before execution; attaching it
after a run cannot certify old execution results.

Completion tests: independent inclusion witnesses for both sibling directions,
direct/package references, cross-item repeats, empty rows, exact dictionaries and
prerequisite ceilings, swapped/wrong root/index, default handles, protocol item/import
ceilings, exact local limits, copied/destructed caller inputs, full-width nominal
indices, zero additional hash calls, optimized failed-result guards, compiler
privacy/domain guards and fresh 1000-cycle ARC release.

Next: execute refinement using these original owned inputs and explicit root trust
policy, assemble auditable bundles and add erasure coding. State owns block
composition/publication. M1 framing is complete; full state serialization and
whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_import_inputs`
passes direct/package roots, exact key sets and shared prerequisite ceilings,
maximal twelve-sibling proofs across 3072 occurrences, sixteen items, exact caps,
zero additional hash calls, descriptor/copy/lifetime isolation and fresh 1000-cycle
ARC release (374640/374640 occupied bytes). Eight optimized result/owner guards
with genuine successful controls and five compiler privacy/domain rejections pass.
Formatted unit/driver semantic checks, verification inventory, 19 affected
inventory/provenance Python tests and pinned formatting pass. Lower production
modules and fixtures are unchanged; prior lower-layer evidence remains applicable.
Exact-head Linux CI is separate; remote checks were not requested.
