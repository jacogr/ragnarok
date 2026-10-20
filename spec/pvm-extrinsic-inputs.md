# Package-bound extrinsic input authentication

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex extrinsicdata and work-item extrinsic commitments;
vector pin `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. No pin changes.

Scope: authenticate one complete ordered extrinsic table against an original
OwnedWorkPackage. Require exactly one row per item and one byte sequence per
commitment, preserving duplicate occurrences and empty rows/preimages. Compare
exact lengths, then Blake2b-256 of raw bytes against each nominal ExtrinsicHash.
No prefix, domain or terminator is hashed. All shape/length validation and
independent local entry/copy/hash caps precede hashing and retained allocation.
The owned manifest's protocol bundle and occurrence limits prove accumulation
bounds; entry limits also bound empty-preimage hash work.

Success retains private immutable deep copies plus the exact original package.
Checked extraction returns independent bytes and the original package handle;
nominal item/input ordinals are checked at full width before narrowing.
Default/failure alternatives contain only a reason and cannot expose a verified prefix. Borrowed nested input
tables must remain stable for the synchronous call.

Completion tests: independent hashlib literals for empty and nonempty bytes,
multiple items, sixteen-item/128-occurrence ceilings, repeats/order, wrong
lengths/hashes, late failure, each exact local cap, invalid/default handles, full-width indices, detached lifetime and mutation
isolation, backend failure at every hash position, zero hash calls on preflight
refusals, optimized result guards, compiler privacy/domain guards and 1000-cycle ARC.

This owner authenticates extrinsic commitments only. It does not authenticate
imports, trace, root freshness or package/root correspondence, and it cannot
retroactively certify earlier refinement execution. Existing execution entry
points retain their documented caller obligations. Next: bind authenticated
imports to package manifests, then execute refinement using the original input
owners, assemble auditable bundles and add erasure coding. State continues to
own block composition/publication. M1 framing is complete; full state
serialization and whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_extrinsic_inputs`
passes independent literal commitments, protocol ceilings, exact caps, preflight
call counts and every injected backend-failure position. Fresh 1000-cycle ARC
reports 48880/48880 occupied bytes. Five optimized failed-result guards with real
successful controls and four compiler privacy/nominal rejections pass. Formatted
source semantic checking, verification inventory, 19 affected inventory/provenance
Python tests and pinned formatting pass. Production consumers are unchanged;
existing lower-layer evidence remains applicable. Exact-head Linux CI is separate
and remote checks were not requested.
