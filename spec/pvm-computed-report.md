# Complete canonical work-report assembly

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex computereport and I/C; serialization.tex workreport,
workdigest, availability and context tuples; pvm_invocations.tex Psi_I and
standard argument-register initialization. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume completed AvailabilityCommitment and derive its original executed
identity, authorization, package context, ordered lookup and final digests. Build
all fixed report fields and payload spans privately, then use the existing
complete-report codec to measure and encode canonical bytes. Retain original
availability provenance and immutable wire. No detached context, trace, core,
lookup, digest, report header or byte pool is accepted by the constructor.

The core ceiling comes from the exact original authorization Parameters snapshot.
Codec validation includes that configured ceiling, erasureShards<=3*coreCount,
canonical prerequisites/lookup, digest counts and the 49152-byte shared trace/
successful-output ceiling. This does not establish active-roster equality or
authenticate the original claimed roots. A source that cannot form a structurally
valid report under its original parameters returns InvalidReport, separately
from a refused local memory policy.

Preflight fixed metadata, all final output spans and exact complete wire length
before trace/output extraction or variable allocation. The ByteLimit covers the
retained report wire, a temporary trace/output pool, and the largest transient
individual trace/output copy. Pool bytes are at most 49152; source-owned counts
bound all fixed metadata. Check native lengths and subtraction-based policy
remainders before allocation. The codec revalidates all fields before writing.
Metadata and byte extraction copy; defaults/refusals have only reasons and no
encoded prefix. No hashing, execution, erasure coding or report publication occurs.

Completion: independent full report wire/hash witnesses for empty/success/error/
page-boundary exports and a nonempty trace/output/import lookup/context case,
canonical decoding/re-encoding, original field/source matching, exact/refused
retained/workspace policy, original configured core/shard ceiling, no hashes,
copy/source/lifetime, compiler privacy/nominal rejection, optimized result guards
and fresh ARC release.

Next: [source-bound guarantee transcripts](pvm-computed-guarantee.md), then root/state trust
integration and guarantee/report publication.
Assembly alone does not certify import package-to-root correspondence, root/state
freshness, distribution/assurance, active-roster equality or signing eligibility.
Production recovery, faster transforms and whole-block parity remain open. M1
framing is complete; full state serialization remains open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_computed_report`
passes five independent complete report wire/hash witnesses, canonical complete
codec decode/re-encode, empty/success/normalized-error/page-boundary exports,
nonzero context, two ordered prerequisites, one exact lookup entry and nonempty
trace/outputs. The context case has nine shared blob bytes and twelve workspace
bytes. Halt-only authorizers return their initialized E2(core) argument as the
two-byte trace; the literal oracle models that pinned behavior explicitly.
Original two-core parameters reject a nine-shard report as InvalidReport even
when a caller supplies a generous local policy. Exact retained/workspace policy,
one-byte-short refusal, no new hashes, full source/copy/detached lifetime and
fresh 1000-cycle ARC (932672/932672 occupied bytes) pass. Seven strict optimized
result guards with genuine independent complete-wire/domain controls and six
compiler privacy/nominal guards pass. Three independent Python tests regenerate
literal complete report encodings/hashes and use the pinned-table simultaneous
pipeline gas reference plus normative host charges; generation and tests share
one fresh oracle cache. Formatted unit/driver semantic checks, inventory, 20
affected inventory/provenance tests and pinned formatting pass. Lower production
modules/fixtures and all pins are unchanged. Exact-head Linux CI remains separate;
remote checks were not requested.
