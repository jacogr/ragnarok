# Export logical startup identities from the original source

Scope: original logical raw-key provenance and the existing v1 startup source syntax. The startup
parser consumes explicit identities, but previously callers needed to author those files separately.
`planLogicalSourceExport` now admits exact identity traversal, text bytes and one largest raw-key copy
before any output allocation or hashing. It retains the original qualified supplied logical companion,
not reconstructed physical hashes. Output contains service identities, raw storage keys, preimage
hashes and hash/actual-length requests; no metadata, storage/preimage values, histories or state root
are exported. Existing header, line cap, 64 KiB transport ceiling and single canonical syntax are
shared with the parser without changing accepted bytes or schema.

Execution accepts only the frozen plan and fills one exact detached string. Decimal/hex writing uses
fixed storage; empty raw keys and zero lengths retain their real representations. Independent limits
bound services/facts, per-key scratch and output-plus-largest-key bytes. Caller mutation cannot change
retained identities or subsequent output. Both Services planning and execution enforce all managed
native graph exclusions until actual matching collection or joined close.

The resulting text is data for the existing startup parser. Parsing alone grants no source authority;
`captureCurrentLogicalStartup` must read and fully match the explicitly selected actual state under
its own profile/global/logical/resource policies. Exported identities do not discover roots, certify
producer mutation propagation, install state, or authorize filesystem writes. No RPC, storage format,
CLI option, dependency pin, worker or scheduling changes are introduced.

Native qualification uses a genuine collected uninstalled logical child, exact comparison with the
maintained independent test serializer, parser acceptance and actual source requalification. Empty
keys, present-empty identities, requests, detached mutation, repeat export after joined shutdown,
exact/short/saturated budgets, hash-free admission/execution, guarded results/privacy and all three
managed lease alternatives are covered. This closes identity-file provisioning for retained logical
sources without claiming independent current-schema STF parity or a general mutation certificate.
