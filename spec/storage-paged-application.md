# Paged application context and startup

## Authorization and order

The maintainer authorized db #5 on2026-10-24 to continue the remaining paged application
integration, then hardware/filesystem power-loss qualification, then complete JAM serialization,
in at most15 further PRs. This explicitly authorizes the storage/state/application boundary for
this tranche. Preserve existing checkpoint trust, canonical ownership and asynchronous workers;
no partial light mapping may enter complete-map execution APIs. Merged storage-only V1 formats
and the full StateStore/light ProofView SDK consumers remain the baseline.

## Atomic context format

An application selection must authenticate its exact context in the same immutable paged artifact
as its state graph or proof inventory. Publishing CURRENT then selects both together. A second
independently selected sidecar cannot supply application head/history/finality authority. The
context remains opaque to storage; the application validates its existing bounded chain context,
full parameter profile, header/state bindings, retained roots and explicit finality. A locally
checksummed context is not an independently trusted checkpoint import.

V2 uses distinct full/light header and CURRENT labels of the same fixed widths as V1. Header,
index and payload offsets remain unchanged. Full header bytes136..143 and light header
bytes120..127 hold E8 context length. The context starts on the next4096-byte boundary after
payload padding, followed by zero padding to the next page. These physical pages participate in
the existing mode-specific page tree before its postorder digests. The unchanged V1 hash-domain
labels identify the page-hash algorithms; the distinct V2 header bytes and physical page ordinals
bind this format. Full retained-root slots remain at144 with at most64 exact56-byte claims.

V1 has no context section and retains its exact previous bytes and geometry. Context-required
selection is explicit: positive context limit requires V2 with nonzero length within that limit;
zero context limit requires V1. There is no automatic version fallback, format inference or
implicit database migration. Header and CURRENT versions must agree. Dataset bytes include the
entire padded context and tree, independently of the context byte ceiling. Overflow, hostile
lengths and exact/one-short physical ceilings must refuse before allocation or cryptography.

The initial codec layer does not enable native application startup. Unsupported native paths explicitly refuse V2 until their bounded context implementations land;
the following sections record each enabled implementation.
Later native authoring must require exact caller-supplied context, charge its IO/hash work,
authenticate every context byte, preserve it exactly in compaction and bind native replay cleanup
to the whole artifact. Context extraction returns owned bounded bytes, without file/pin aliases.

## Application and completion gates

Full startup restores every context-selected complete root through the existing independent
StateStore reconstruction, then reconstructs canonical history/finality under the configured
chain identity. Publication preserves the host sequence: private successor/context staging,
worker exclusion, native durable receipt, then canonical/RPC installation. Uncertain IO retains
the old in-memory head and requires fresh recovery; bootstrap remains exclusive and forensic.

Light startup has distinct storage and in-memory authority. Trusted root/head selection remains
separate from proof availability. Unknown evidence stays MissingWitness, authenticated absence
stays absent, and no partial ProofView can authorize a full-node transition. Mode, memory/disk
backend and physical layout remain separate choices; incompatible paths refuse without repair.

Required qualification includes independent V2 byte/geometry witnesses, V1 regressions, tampering,
truncation, exact/one-short quotas, owned snapshots, native IO failures, process-death publication
boundaries, unchanged canonical/RPC consumers, explicit startup mode/layout refusal and real
Linux native checks. Hardware/filesystem power-loss evidence requires a named target, actual
power interruption and externally retained before/after oracle; SIGKILL is separate evidence.
Complete JAM serialization remains a later ordered item under the pinned Gray Paper and exact
single-schema interpretation, rather than a claim inferred from transport or M1 framing.

## Observed codec qualification

Pinned checked ARC/Clang release passes the independent V2 context codec suite, including
whole-header/CURRENT byte equations, empty/nonempty graph geometry, context page boundaries,
exact/one-short physical and context ceilings, hostile lengths, malformed empty V2 context,
truncation, V1/V2 mismatch and native callback-dispatch refusal controls.1000 codec cycles retain
192 ->192 occupied bytes. Both original V1 codec suites pass unchanged byte witnesses. Full
build/graph and light streaming regressions pass, including their1000-cycle release controls.
All419 production modules and the peer entry point pass local semantic Smoke; source-owned
inventory and separate stable pinned formatting checks pass. Native V2 context IO and application
startup remain subsequent layers.

## Full native V2 context

FullPagedStreamLimits.contextBytes now selects full V1 at zero or requires full V2 under a finite
positive opaque-context cap. Both ordinary CURRENT and explicit old-epoch readers enforce that
choice before complete graph admission. Bootstrap and replacement require exact stable borrowed
context bytes, validated before candidate acquisition; unsupported bootstrap context refuses before
creating its directory/LOCK. Context and record/graph byte ceilings remain independent.

Construction appends separately padded context before the existing page tree, accounting every
write/hash/read. Complete admission authenticates all physical context pages and checks payload
and context padding independently. Compaction copies authenticated source pages exactly, preserving
opaque context without a resident context-sized buffer, producer or alternate context source.
Header, CURRENT, root union and context are selected by the existing one-file publication barriers.
V1 retains its previous bytes and construction IO schedule.

readContext on a selected reader or writer returns an immutable FullPagedContext. It owns its exact
captured manifest and opaque bytes, with no file, pin or callback alias. The guarded bytes getter
returns detached mutable transport. Per-call work can only tighten captured admission policy.
Extraction preflights a conservative four-context-transport working reservation before allocation,
matching full-value reservation discipline. Failed/default captures expose no partial prefix.
Application interpretation and independent checkpoint trust remain separate.

Candidate cleanup/bootstrap replay receives exact independently supplied replacement context and
reproduces the whole artifact before comparing every present forensic prefix. Source-derived
compaction cleanup accepts no caller context substitution. Reclamation receipts bind all16
admission-policy scalars, including the context cap; a mismatched policy remains InvalidCandidate
under the existing contract. Old-epoch context captures survive native close and reclamation.

The storage_full_paged_context suite passes on macOS ARM64 and Linux amd64 under Docker emulation
with pinned checked ARC/Clang. Independent byte/tree oracles cover context lengths1,31,4095,4096,
4097,65,537 and4,194,304 under cache0/1, retained complete roots, compaction, exact/one-short context/
working/work limits, inherited-budget refusal and detached mutation. Native controls cover all
observed context read and candidate write failures, unchanged CURRENT, unresealed corruption,
resealed noncanonical padding, explicit replay with wrong/correct context, bootstrap resume,
retained old-epoch reopen and exact context-policy reclamation.1000 successful captures plus late
private-prefix IO failures and fresh close/reopen cycles retain83,888 ->83,888 occupied bytes on
both platforms. The private context-backing compiler guard passes. Existing V1 publication,
recovery, old-epoch, compaction and StateStore transport suites pass. All419 production modules
and the peer entry point pass local Smoke, with stable pinned formatting and source inventory.
Light native V2 and application startup remain the next integration layers.

## Light native V2 context

PagedStreamLimits.contextBytes selects V1 at zero or requires V2 under a finite positive cap.
Construction, ordinary readers, replacement and explicit root advancement require that physical
format without inference or fallback. Bootstrap validates context presence and its ceiling before
creating the namespace. Complete admission authenticates all context pages and independently
checks proof payload padding and context padding. V1 bytes and construction IO remain unchanged.

readContext returns an immutable owned PagedContext with its exact captured manifest. Detached
bytes outlive reader retirement and reclamation; no file, pin or callback escapes. Extraction
preflights four context transports plus fixed workspace before allocation and can only tighten
all captured work limits. Context is opaque application metadata; it supplies no additional proof
availability, complete-state authority or external checkpoint trust.

Compaction copies all authenticated source data pages, including context, and preserves ordinary
sequence. Replay of a same-root/same-sequence compaction requires exact proof knowledge and opaque
context equality. Admission folds already visited context leaf digests under a separate local
domain, with charged hash work and constant memory, so even a forensic prefix ending before the
first context page cannot authorize substitution. Independently requested replacements and root
advancements instead bind the caller's exact target context through complete replay and prefix
comparison. Reclamation binds the additional context policy scalar with the existing policies.

The storage_paged_context suite compares independent whole-artifact and CURRENT bytes at context
lengths 1, 31, 4095, 4096, 4097, 65,537 and 4,194,304 with cache zero/one. It covers empty knowledge,
exact/one-short work and working ceilings, inherited-budget refusal, detached getter mutation,
retained readers, root advancement, compaction/replay, corruption and independently recommitted
padding, bootstrap resume, V1/V2 refusal and all observed native context read/candidate write
failure boundaries. The state ProofView bridge retains present-empty, authenticated absence and
MissingWitness distinctions on V2. Checked macOS ARC/Clang passes 1,000 successful capture plus
late private-prefix read failure and fresh close/reopen cycles with 35,504 -> 35,504 occupied bytes.
The same suite passes on Linux amd64 under Docker emulation with the same 35,504 -> 35,504
ARC result. The private backing compiler guard, affected V1 streaming/native/cleanup/compaction,
context codec and state ProofView suites pass. Source inventory, stable pinned formatting and
all 419 production modules plus the peer entry point pass local semantic Smoke. Application
startup and actual device power-loss qualification remain separate completion gates.
