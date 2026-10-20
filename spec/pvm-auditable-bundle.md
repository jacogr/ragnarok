# Auditable bundle assembly from executed inputs

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex makebundle (including its explicit no-prefix note),
extrinsicdata/importsegmentdata/justifysegmentdata; serialization.tex tuple,
sequence and variable-length discrimination. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume a completed InputRefinement and derive its original package,
verified extrinsics/imports and lookup through retained provenance. Serialize the
canonical package, then all raw extrinsic bytes in item/occurrence order, then all
raw 4104-byte imported segments in that order, then each canonical length-prefixed
root-to-leaf sibling path. There are no additional package/blob/item/row/segment
counts or lengths. Only each Merkle path carries E(sibling count). Empty rows and
empty extrinsics contribute no bytes; a singleton path still contributes E(0).
Do not interleave segments with proofs. Lookup dictionaries, authorization traces,
refinement outputs and exported segments are not additional bundle fields.

Preflight the complete retained wire byte budget and E4 BundleLength/native-int
representability before payload extraction/allocation. The original package owner
bounds imports to 3072 and sibling counts to twelve. Compute imported bytes as
4104*count and proof bytes as witnessBytes-importedBytes+count; each sibling count
is 0..12, so its canonical natural prefix occupies exactly one byte. Accumulate
section sizes by subtraction from remaining E4/native/local budgets. MaxBundleBytes
is the package codec's extraction-footprint ceiling, not an extra serialized-bundle
wire limit. No hashing or erasure coding is performed by assembly.

Success retains private immutable bytes, copied section facts and the original
execution owner. Byte extraction copies; default/refused results have no successful
prefix or fabricated empty bundle. This binds auditable bytes to their actual
execution and report identity, but does not certify root/state freshness or
package-to-root correspondence. Those trust obligations remain as recorded in
pvm-input-refinement.md. Availability/erasure roots and work-report publication
remain separate; state retains block composition/publication.

Completion tests: independent Python-built literal package bytes and full-bundle
hash/length witnesses, section boundaries and path order, multiple items/occurrences,
empty rows/extrinsics and singleton paths, repeated inputs, exports exclusion,
exact/insufficient local budgets, no additional hashes, copy/lifetime isolation,
optimized failed-result guards, compiler privacy/source rejection and fresh
1000-cycle ARC release.

Systematic bundle input layout is continued in [pvm-erasure-layout.md](pvm-erasure-layout.md).

Next: authenticated root/state trust integration, erasure coding and availability
specification from original bundle/export owners. M1 framing is complete; full
state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_auditable_bundle`
passes independent complete package/full-bundle witnesses (8813 and 17637 bytes),
raw 128/129-byte extrinsics, repeated/singleton paths, exports exclusion, exact
section/total caps, zero additional hash calls and copy/lifetime isolation. Fresh
1000-cycle ARC reports 343696/343696 occupied bytes. Six optimized result/owner
guards with genuine successful controls and six compiler privacy/source/budget
rejections pass. Formatted unit/driver semantic checks, verification inventory,
20 affected inventory/provenance Python tests, three independent witness
reproducibility tests and pinned formatting pass. Lower production modules and
fixtures are unchanged; prior lower-layer evidence remains applicable. Exact-head
Linux CI is separate; remote checks were not requested.
