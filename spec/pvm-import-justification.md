# Verified imported-segment inclusion

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
merklization.tex N, T, C and constantdepthsubtreemerklejust with x=0;
work_packages_and_reports.tex segrootlookup/importsegmentdata/justifysegmentdata,
Cmaxexports=3072; serialization.tex variable-length sequence discrimination.
Vector pin remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: verify a typed 4104-byte segment against an explicit SegmentRoot,
ImportIndex and root-to-leaf sibling sequence. Hash ASCII `leaf` || segment,
then fold siblings bottom-up using index bits and ASCII `node` || left || right.
No dollar, terminator or sequence count is part of either hash preimage.
Maximum valid export cardinality 3072 implies at most twelve siblings and valid
indices 0..3071. Additionally the index must fit the path's padded tree width.
A singleton uses an empty path and its leaf hash as root; an empty tree's zero
root cannot authenticate a real zero-segment leaf.

Protocol geometry and independent local sibling count, payload-copy bytes and
hash-preimage bytes are checked before variable allocation/hashing. Successful
private immutable ownership binds original root/index/segment/path. Copy getters
and canonical E(path length) || path bytes expose no retained mutable storage.
Failures/defaults contain no authenticated segment or encoded proof prefix.

This proves inclusion only. It does not certify a root's known/unexpired status,
its package-hash correspondence, actual export cardinality, a matching package
manifest or input use by an earlier execution. Those stages must consume this
owner and bind their own original sources; callers cannot upgrade old execution
results by attaching newly authenticated inputs after execution.

Completion: independent hashlib literal roots/paths for singleton, three distinct
segments, partial trees and maximal exports; changed byte/index/root/sibling,
reordered/truncated/extended paths, real-zero versus padding, exact local caps,
full-width index rejection and protocol-before-local precedence. Interoperate
with source-bound export commitment roots; copy/lifetime isolation and 1000-cycle
ARC. Optimized failed-result guards, compiler privacy/domain rejection, selected
native suite, inventory/provenance tests and pinned formatting.

Next: package-bound authenticated extrinsic/import input ownership, execution
against those owned bytes, auditable bundle assembly and erasure coding. State
retains block composition/publication. M1 framing is complete; full state
serialization remains open.

Local evidence: checked optimized macOS `pvm_import_justification` passes all
independent literal proof witnesses, exact policies, mutation/shape/padded-slot
rejections and interoperability with the source-bound 3072-export commitment.
Fresh 1000-cycle ARC release reports 338096/338096 occupied bytes. Six optimized
runtime guards and six exact compiler privacy/nominal rejections pass. The pinned
compiler renders both generic root domains as ReportHash and sequence diagnostics
as seq; fixtures match the precise call and argument position. Inventory, 19
inventory/provenance Python tests, formatted-source semantic checking and pinned
formatting pass. Existing lower production modules/shared fixtures are unchanged;
prior lower-layer evidence remains applicable. Remote CI was not requested.
