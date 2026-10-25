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

The initial codec layer does not enable native application startup. Existing native builders
and graph admission explicitly refuse V2 until their bounded context implementations land.
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
