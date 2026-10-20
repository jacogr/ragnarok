# Source-bound exported-segment commitment and paged proofs

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
merklization.tex N/C/constantdepthmerkleroot, constantdepthsubtreemerklejust and
constantdepthsubtreemerkleleafpage; work_packages_and_reports.tex exporting,
pagedproofs and availability specifier; serialization.tex length discriminators. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: derive only from a completed opaque ReportIdentity and its original
normalized ordered refinement exports. Hash each final 4104-byte segment with
ASCII `leaf` prefix; zero replacement segments are real leaves, distinct from
padding zero hashes. Pad to the next power of two (minimum one). Internal hashes
use ASCII `node` || left || right. The empty root is the zero hash; singleton
root is its leaf hash. Preserve the original identity/execution owner.

Retain a private immutable bounded heap tree. Local export count, allocated hash
slots (including unused heap slot zero) and exact hash-preimage byte budgets are
proved before segment extraction, allocation or hashing. Extract 4104-byte paged
proofs on demand: canonical natural path count, root-to-page sibling hashes,
canonical natural actual leaf count, at most 64 leaf hashes, then zero padding.
Final partial pages contain only actual leaf hashes; no invented padding leaves
are serialized. Full-width nominal page indices are checked before narrowing.

Completion: independent hashlib roots/page byte witnesses for empty, singleton,
nonpower-of-two, 63/64/65 and 3072 exports; verify proof reconstruction/order,
zero replacements and successful exported data across ordered items. Exact caps,
default owners/results, immutable copies, source retirement, 1000-cycle ARC;
optimized refusal guards and compiler privacy/source/index rejection. Native
suite, discovery/provenance checks and pinned formatting. Existing lower-layer
production trees are unchanged, so prior lower-layer evidence is retained.

Auditable bundle assembly from executed input owners is specified in
[pvm-auditable-bundle.md](pvm-auditable-bundle.md). Next: authenticated root/state
trust integration, erasure coding and complete availability/work-report construction. Imported-root correspondence, input
hash/proof authentication and state publication remain separate. State retains
block composition/final publication. M1 framing is complete; full state
serialization remains open.

Local evidence: checked optimized macOS `pvm_export_commitment` passes all fixed
hash witnesses and every-page reconstruction through 3072 exports, including the
asymmetric Success/BadExports/BadExports witness. Raw missing/panic outcomes with
positive declarations normalize to BadExports under the existing report I rules;
commitment construction consumes those final zero replacements unchanged.
Fresh 1000-cycle ARC release reports 22128/22128 occupied bytes. Five optimized
runtime result/owner/page guards, five exact compiler privacy/source/index
rejections, verification inventory, 19 inventory/provenance Python tests and
pinned formatting pass. These are local results; exact-head Linux CI remains
independent. All lower production modules and shared fixtures are unchanged.
