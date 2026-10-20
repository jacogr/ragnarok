# Export and proof-page erasure chunks from executed bundles

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex availability specifier segment arm, pagedproofs
and normalized I export ordering; erasure_coding.tex erasurecoding and code-word
representation. Vector pin remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume completed BundleErasure, derive its original execution identity,
prepare that identity's export commitment, and erasure-code all final ordered
4104-byte exports followed by all 4104-byte canonical proof pages. Normalize
failed items through the retained report, never their rejected actual exports.
No caller-supplied export tree, report identity or replacement shard count is
accepted. The assuring-set geometry is inherited from the original bundle.

Each row is independently split into d contiguous original chunks, each
4104/d bytes. Transpose little-endian word columns through the existing scalar
encoder and regroup by validator. Retained wire ordering is validator-major,
then all original exports, then proof pages. Nominal ExportErasureIndex addresses
that combined row sequence; ErasureShardIndex addresses every systematic/parity
validator. Extraction copies one complete chunk. No segment padding is needed.
Empty exports have zero pages/rows and zero coding workspace/work/output, but
retain a genuine empty export commitment (including its two allocated tree slots).

Preflight all aggregate encoded bytes, coding workspace and field products
before export-tree hashing or payload extraction. At most 3072 exports and 48
pages give 3120 rows. With k=segmentChunkBytes/2, total products are rows*k times
31*(span-1)+d*(d-1)/2+(v-d)*(d-1), span=nextpow2(d). Nonempty coding workspace
is 2d input bytes plus 2*(v+d+span) scalar-buffer bytes. The byte policy covers
encoded output plus that workspace; separate ExportCommitmentLimits cover
export count, tree slots and hash preimages. Retained source storage, allocator
headers, fixed 4104-byte stack segments and returned copies are separate.
Validated dimensions bound all arithmetic below 2^44 before native conversion.
Scalar or commitment failures publish no successful prefix.

Completion: independent export-tree/page construction and Lagrange erasure
witnesses for empty/single/mixed exports and 65 zero exports; complete buffer
hashes and explicit parity chunks, systematic reconstruction of data and pages,
exact/refused aggregate/commitment budgets, backend refusal and preflight before
hashing, full-width index/source refusal, copy/provenance/lifetime isolation,
compiler privacy/nominal guards, optimized result guards and fresh ARC release.

Next: bundle chunk hashes, per-validator export/page Merkle roots and final
availability-root assembly from this shared source. Production recovery, faster
transforms and root/state trust integration remain open. M1 framing is complete;
full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_export_erasure`
passes independent complete encoded-buffer/root witnesses for empty, single,
mixed Success/BadExports/BadExports and 65-zero-export cases at 6/1023
validators; explicit data/page parity bytes, systematic reconstruction of every
4104-byte data/page row, exact/refused aggregate and tree-node policies, empty
zero-work success, default/source/full-width coordinate refusal and copy/source/
detached lifetime. Nonempty coding adds no hashes beyond the derived export tree;
aggregate refusals precede hashing, and a refused primitive backend produces
CommitmentFailure without a successful prefix. Fresh 1000-cycle ARC reports
726960/726960 occupied bytes. Nine strict optimized result guards include real
completed parity and backend-failure controls; six compiler privacy/nominal
guards pass. Three independent Python tests reproduce complete buffer/root and
parity witnesses, verify the 64/65 page split and reconstruct a real proof page
from parity-only chunks. Formatted unit/driver semantic checks, inventory, 20
affected inventory/provenance tests and pinned formatting pass. Lower production
modules and fixtures are unchanged. Exact-head Linux CI remains separate;
remote checks were not requested.
