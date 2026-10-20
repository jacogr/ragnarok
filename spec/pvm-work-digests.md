# Source-bound refinement work digests

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`work_packages_and_reports.tex` item-to-digest C, `reporting_assurance.tex`
workdigest, and C.2 serialization. Vector pin
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` remains unchanged.

Scope: consume one opaque completed RefinedPackage, preserving its order and
original item/source selection. Derive service, code hash, accumulation gas limit,
import count, declared export count, extrinsic count and sum of declared extrinsic
lengths from each retained item. Hash the exact payload bytes with Blake2b-256,
without a length prefix or domain. Preserve final I output/error and consumed gas;
never substitute raw invocation output or actual export count after I rejection.
Encode canonical digests with the existing borrowed codec internally; public owners
expose copied metadata/bytes and original immutable report/item handles, never a
borrowed success span detached from its pool. Successful empty output remains
Success. All six protocol errors remain payload-free.

Check independent item, per/total payload hashing and per/total encoded-byte caps
before allocating payload/output/encoding scratch. Prove all sums and narrowing,
including full-width extrinsic lengths, before use. Any refusal discards the entire
private prefix. Invalid/default inputs and index/output refusals are typed; result
alternatives and retained storage are private and success-guarded. State composition
and publication stay with state. No full/light database or state-root changes.

Completion: real bound multi-item guests; independent raw-payload hash witnesses;
all fields and canonical encoding, nonempty/empty success and all six work errors;
manifest metrics including wide extrinsic sizes without preimages on BAD; exact/
one-short independent local budgets and late rollback; lifetime/replay/mutation
isolation; optimized result/owner/index/output guards and compiler privacy/source/
nominal rejection; fresh 1000-cycle ARC release; regress report results and digest
codec. Inventory, relevant tooling tests and pinned formatting must pass.

Local evidence: checked optimized native `pvm_work_digests`, `pvm_report_results`
and `work_digest` pass. Fresh 1000-cycle ARC release is unchanged at 43408/43408
and 448096/448096 bytes for the projection and report suites. Seven optimized
runtime guards, six compiler privacy/nominal/source rejections, 19 inventory/
provenance Python tests, verification inventory and pinned formatting pass.
These are local macOS results; exact-head Linux CI remains independent.

Next: authorization execution and subsequent availability/erasure report assembly.
Authorization/input/freshness authentication, segment-root lookup certification,
complete work-report construction and publication remain open.
M1 framing is complete; full state serialization and complete JAM parity remain open.
