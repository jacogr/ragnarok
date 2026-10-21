# Coordinated unreleased Gray Paper upgrade

## Authorization, exact target and scope

The maintainer authorized unreleased specification pins on2026-10-21 after reviewing
GP-PVM-010 and merged PR533. Target upstream main at exact commit
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, after release0.8.0 at
`07f041dabd073f9018b418e9ee72e79dd2185401`. VERSION still reads0.8.0;
record this as an unreleased commit, never claim a new release tag.

Audit the exact tree delta, not an unbounded shallow-history log. Eighteen source
files differ. The target includes unsigned host gas/clamping, removal of host Halt,
new inner-module compilation and shifted selectors, supervisor/junior service state
and transfer operands, bounded preimage request lengths, canonical three-register
nibbles, code/table limits, conditional-move dependency clarification, Ed25519 ZIP215
wording, a Thin VRF reference and small Safrole/reporting corrections.

The source is authoritative. Published0.8.0 vectors remain a separately identified
historical test corpus unless a reviewed compatible replacement exists. Current
vector master already contains vectors for still-open GP563, so do not blindly
advance that unrelated source. No alternate production encoding or automatic
fallback is permitted. Do not copy upstream runtime code or patch dependencies.

## Migration requirements and completion checks

- Update the gitlink, exact source hashes and provenance tests together. Preserve
  historical evidence/version references explicitly; distinguish current contracts.
- Use unsigned gas throughout active/terminal outcomes. All host underfunding
  drains gas to zero. If legacy deficit fields are retained for source compatibility,
  they are reserved-zero values and nonzero input must fail locally on every path.
  Update wide cost/reservation arithmetic without narrowing or overflowing.
- Apply current opcode/table/cap equations to the paper decoder; retain only
  still-applicable, documented PolkaVM compatibility differences. Regenerate original
  fixtures from independent current-paper models and compare public PolkaVM.
- Review every shifted host selector and changed argument/context shape. Newly
  unimplemented features must remain explicit typed gates, never unknown-call WHAT
  or successful old-argument execution. Migrate existing implemented paths and tests.
- Review supervisor metadata, deferred-transfer framing, state-key namespaces,
  Thin VRF and state transitions against their owning contracts. Do not claim full
  state/crypto/JAM parity from successful interpreter checks or retain an obsolete
  source hash as if it described the new normative chapter.
- Run source inventory/provenance controls, affected compiler/runtime guards and
  native suites; broaden to the complete maintained verification path for this
  cross-cutting pin change. Retain interpreted public-reference comparisons and
  validated benchmark reports, with compiled performance still deferred.

No merge, upstream issue/comment or unrelated toolchain upgrade is authorized.
The maintainer confirmed the previous batch merged on2026-10-21 and lifted the
publication hold. The first upgrade PR starts a fresh stack with a20-PR limit.
Complete the coordinated migration and required checks before publishing it.

## Explicit incomplete capabilities during migration

The module catalogue and memory compilation path use the current refinement IDs9–15.
Database-backed compilation remains `UnsupportedHostCall` until its authenticated
historical source adapter is implemented. Native compilation and compiled benchmarks
remain outside this interpreted-engine work.

Self-funded liquid `new`, self `upgrade`, and liquid deferred `transfer` use current
argument layouts. Foreign supervised mutations, alternative funding modes, direct
transfers, and supervisor reassignment are explicit `UnsupportedHostCall` gates while
their account mutation/publication proofs are migrated. The previous argument layout
is never accepted as a production fallback. These gates are incomplete implementation,
not discrepancies in the normative paper.

The legacy Bandersnatch backend remains a verified release-reference IETF profile;
its gate now identifies the current Thin VRF requirement. No current Thin parity is
claimed from historical vector success.

## Lifecycle ownership regression

Current module/instance hosts construct their owned response directly in the complete
transition. With the pinned checked ARC build, nesting the owned result of the former
`charged` helper retained one extra caller-memory owner per fresh compilation. The
isolated regression observed8,240 retained bytes per iteration. Direct response
construction preserves identical gas checks and releases all owners in1,000 fresh-memory
compile/instantiate/catalogue-removal/instance-removal cycles. Inner page and invoke
cycles retain their independent release checks. No runtime/compiler dependency is patched.

## Current local migration checkpoint

Focused native suites `pvm_fetch_accumulation`, `pvm_accumulation_info` and
`accumulation_credit` pass with1,000 ownership cycles each. Transfer capture uses
154-byte records and account-info uses112 bytes. Incoming-credit witnesses exercise
separate full-width liquid/supervisor balances and independent overflow refusal.
The independent credit fixture checks pass; historical release balance projections
are embedded explicitly into current metadata and have derived roots.

This is partial local verification, not complete native-suite or Linux CI evidence.
The `eject` implementation and direct guest witnesses now use current supervisor
authorization, empty-item eligibility and reclamation of both balances. Bounded
deletion proofs/publication remove only metadata. The broader batch integration
fixtures are migrated and pass their retained interaction cases.
The focused current eject guest suite and full deletion/publication interaction
suite each pass1,000 ownership cycles with unchanged occupied memory; all three changed production modules pass semantic compilation,
and the exact nominal target-domain rejection passes. Other shifted host-call fixtures and current account mutation arguments
also remain pending. Do not publish the upgrade while these obsolete paths remain.

## Ed25519 verification compatibility blocker

The target explicitly adds ZIP215 validation. The pinned BoringSSL bridge rejects
three fixed valid ZIP215 witnesses, with working signing/verification controls.
See [the compatibility audit](crypto-zip215-upgrade.md). This is an implementation
gap, not a specification discrepancy. A maintained verification backend is required;
the maintainer authorized a crypto foundation PR before this upgrade. Do not publish this pin
upgrade with the known incompatible verifier presented as current protocol behavior.
