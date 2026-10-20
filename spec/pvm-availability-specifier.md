# Availability specifier from one executed bundle/export source

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex availability specifier and merklization.tex
merklenode/simplemerkleroot. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume completed ExportErasure and derive the exact original BundleErasure.
For each validator hash its raw bundle chunk with Blake2b-256. Compute a GP
well-balanced root of its export chunks in final export-then-page order. Form
one raw 64-byte item bundleHash||exportChunkRoot per validator, then compute the
well-balanced root of these items. Return the six nominal availability fields:
original package hash, original E4 bundle length, computed erasure root, inherited
E2 validator count, original export segment root and E2 original export count.
Proof pages contribute chunks, not exported segment count. No caller can attach
a detached bundle, export tree, geometry or replacement availability tuple.

GP N splits at ceil(n/2), with unpadded raw leaves and ASCII `node` prefixes.
Internal singleton subtrees return raw leaves; the standalone well-balanced
singleton case hashes its one raw item. Empty sequences return 32 zero bytes
without hashing. Do not hash all leaves, pad to a power of two, duplicate an odd
leaf or substitute the constant-depth export tree. Original exports imply zero
rows or at least two rows; the helper also implements GP's singleton case.

Preflight complete logical buffer, hash-call and hash-preimage-byte policies
before allocation, chunk extraction or hashing. For n fixed-width w-byte items,
WB calls C(n)=0,1,n-1 for n=0,1,>=2; WB preimage bytes B(n,w)=0,w,
n*w+4*(n-1)+32*(n-2), respectively. Thus total calls are
v*(1+C(rows))+C(v) and hash bytes v*(bundleChunkBytes+B(rows,w))+B(v,64).
Retain 64*v leaf bytes. Reusable workspace is rows*w export bytes, one bundle
chunk and (for nonempty rows) one returned export chunk. Source retention,
allocator headers and bounded fixed stack storage are separate. Recursive
node preimages are at most 2740 bytes and depth at most twelve; dimensions
inherited from the immutable source bound arithmetic below 2^44.

Success retains private original provenance and leaf bytes; metadata/per-validator
hash access copies. Default/local/backend refusals have reasons only and expose
no partial root or validator prefix. This computes availability metadata, not
network distribution, assurance votes, active-roster equality, root/state freshness
or package-to-import-root trust. Report publication remains a separate boundary.

Completion: independent literal package/bundle construction, Lagrange chunks,
unpadded well-balanced roots and six-field witnesses for empty/single/mixed/65
exports at 6/1023 validators; explicit per-validator hashes, exact hash-call/byte/
buffer limits, raw-leaf and ceil-split counterexamples, preflight/backend refusal,
copy/source/lifetime, full-width index and compiler source/privacy guards,
optimized result guards and fresh ARC release.

Complete report assembly continues in [pvm-computed-report.md](pvm-computed-report.md).

Next: assemble complete work-report metadata from retained execution/availability
owners and integrate root/state trust checks before publication. Production
recovery, faster transforms and whole-block parity remain open. M1 framing is
complete; full state serialization remains open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_availability_specifier`
passes independent literal original bundles, complete 104-byte six-field tuples,
first/last validator hash pairs and exact observed hash-call/preimage-byte facts
for empty/single/mixed/65 exports at 6/1023 validators. Exact buffer/hash-call/
hash-byte caps succeed; one-unit-short caps refuse before hashing. Empty export
roots are zero without extra hashes. Failed initial bundle hashes, export roots,
later validators, first outer nodes and final root hashes expose no successful
prefix. Copy/source/detached lifetime and full-width index refusals pass. Fresh
1000-cycle ARC includes complete and partial-prefix/backend cleanup and reports
843328/843328 occupied bytes. Nine strict optimized result guards with independent
completed-root controls and six compiler privacy/nominal guards pass. Three
independent Python tests reproduce all source/metadata/validator witnesses,
anchor empty/singleton/binary WB rules and reject floor-split, padded and
prehashed-leaf alternatives. Formatted unit/driver semantic checks, inventory,
20 affected inventory/provenance tests and pinned formatting pass. Lower production
modules and fixtures are unchanged. Exact-head Linux CI remains separate;
remote checks were not requested.
