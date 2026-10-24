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
publication hold. The crypto foundation and this upgrade begin the fresh stack with a30-PR limit.
Complete the coordinated migration and required checks before publishing it.

## Explicit incomplete capabilities during migration

The module catalogue and memory compilation path use the current refinement IDs9–15.
Database-backed compilation now uses the retained historical source adapter,
with anchor-time lookup and clipped interpreted module capture; see
[inner lifecycle](pvm-inner-lifecycle.md). Native compilation and compiled benchmarks
remain outside this interpreted-engine work.

All four `new` and deferred `transfer` funding modes, plus self `upgrade`, use
current argument layouts. Creation authenticates self/supervised sources, debits only
the selected pool and binds child identity to the invoker. Self funding retains creation
publication proof; foreign funding retains the explicit parallel conflict-selection
gate. Supervised upgrade now executes against retained invocation state;
its parallel batch publication still requires modified-account conflict selection.
Supervisor29 now authenticates current effective authority and atomically reassigns
self/foreign metadata, with self publication and the same foreign batch gate.
Supervised storage writes now authenticate and mutate the target account in retained
invocation state; their foreign publication still needs the same conflict selection.
Supervised solicit/forget now mutate target requests in retained invocation state,
using actual invocation time and the same explicit foreign publication boundary.
Deferred transfers authenticate self/supervised sources, debit the selected pool
and preserve the destination-protected flag through next-invocation credit. Foreign
transfer publication retains the parallel conflict-selection gate. Direct transfers
now enforce both-endpoint authority and atomically debit/credit the selected pools
for575 gas, with no memo or deferred output. Self cross-pool effects publish through
the existing self metadata proof; foreign endpoints retain the same parallel gate.
The previous argument layout
is never accepted as a production fallback. These gates are incomplete implementation,
not discrepancies in the normative paper.

[Exact modified-account membership](pvm-modified-accounts.md) is now available
through bounded immutable invocation facts, including successful no-ops, restored
writes and zero incoming credits. This is a prerequisite for current parallel
selection; it does not remove the foreign publication gate by itself.


Bandersnatch now selects the qualified Draft 35 Thin v1 profile using pristine
ark-vrf 0.6.0 and advances the JAM vector pin to gp-next
`23061ae1f9b51171c01387e7dde0f15794c98e24`. Its upstream changelog explicitly
names the target GP changes and Draft 35/0.6.0. Positive Thin/ring/current JAM
vectors and retained historical rejection witnesses are separate evidence; see
[the primitive contract](bandersnatch.md). Complete current-schema STF parity
remains separately qualified.

## Lifecycle ownership regression

Current module/instance hosts construct their owned response directly in the complete
transition. With the pinned checked ARC build, nesting the owned result of the former
`charged` helper retained one extra caller-memory owner per fresh compilation. The
isolated regression observed8,240 retained bytes per iteration. Direct response
construction preserves identical gas checks and releases all owners in1,000 fresh-memory
compile/instantiate/catalogue-removal/instance-removal cycles. Inner page and invoke
cycles retain their independent release checks. No runtime/compiler dependency is patched.

## Current local verification

The broad checked native sweep executed463 suites:435 passed initially and28 exposed
remaining release-era fixtures or the computed-guarantor null-key predicate. All28
now have passing focused reruns, retained separately from the original failed report.
All41 independent corpora passed. Affected ARC suites retain fresh1,000-cycle release
observations. This is aggregate local regression evidence, not a claim that the original
failed invocation passed or that exact-head Linux CI ran.

All264 production modules pass semantic compilation after the eligibility correction.
Python provenance/tooling checks cover639 tests. The obsolete namespace-policy skip
is replaced by an active current-domain boundary test; remaining skips are individually
documented implementation/specification gates. The16 interpreted
PolkaVM comparison pairs passed; subsequent changes affect state adapters and fixtures,
with their covered interpreter/reference inputs unchanged. Compiler rejection guards pass.
The full runtime-failure sweep plus source-owned repaired-family reruns validate all
planned current cases, retaining the original failed reports. The production build and
fresh-process runtime load pass. The interpreted benchmark validates equivalent results
before timing. All17 E2E workloads and6 selftests pass across the full sweep and the
complete RPC rerun after its authored account-fixture projection.

Current105-byte accounts and154-byte transfers are used by the tested consumers.
Release account/marker witnesses are explicitly projected into current supervisor/null-key
fields while retaining their original upstream source hashes. Request boundaries exclude
both reserved E4 prefixes. Integration guests use current selectors and independently
counted instruction ceilings, including exact and one-short refusal cases.

## Ed25519 verification compatibility resolution

The target explicitly adds ZIP215 validation. The historical BoringSSL bridge rejected
three fixed valid ZIP215 witnesses, with working signing/verification controls. The crypto
foundation now supplies a maintained verifier; this layer activates it together with the
new invalid null-validator key.
See [the compatibility audit](crypto-zip215-upgrade.md). This is an implementation
gap, not a specification discrepancy. The maintainer authorized the crypto foundation PR before this upgrade. Current-policy
corpus results explicitly record the normative ZIP215 difference in Wycheproof case151.

## Current account-selector migration

The current paper's write (5), query (24), solicit (25) and forget (26) rows add an
account selector in r7. Their pointer/length arguments move to r8 onward. Native
request-boundary tests reject both reserved E4 lengths and prove storage/request
separation. Production and guest programs use the current register layout.
Query supports current foreign-account reads; supervised foreign mutations remain
explicit implementation gates until their account mutation/publication paths are complete.

Undefined `new`/`transfer` modes return protocol HUH after the applicable memory and
service-existence checks. Transfer refusals charge only575 gas and never enqueue or
debit. Defined deferred modes execute against the selected liquid/protected source pool.

## Runtime probe migration

Runtime probes use current154-byte transfer controls and explicit memory-compilation
arguments. Host Halt now fails response validation. Overwide page/invoke/provide prices
produce completed unsigned OOG, so their misuse probes reject engine-reason extraction
instead of incorrectly rejecting the valid OOG owner. Positive controls check the exact
alternative before the intentional misuse; helper procedures preserve dynamic guard
checks rather than accepting a compiler rejection as runtime evidence. Source-owned
case identities and exact assertion diagnostics changed together.

## Publication evidence and remaining boundaries

Checks ran locally on macOS with the pinned toolchain; production uses checked release
ARC/Clang LTO. Full-sweep failure reports are preserved alongside focused repaired-case
results. They are aggregate regression evidence, not rewritten green reports or exact-head
Linux CI. The interpreted benchmark retains raw measurements/environment metadata and
keeps compiled comparisons deferred by maintainer direction.

M1 framing is complete. Full state serialization, whole-block parity and the explicitly
gated host capabilities above remain separate from qualified Thin primitive integration. Full
upstream PolkaVM fuzzing remains a required future independent CI job.
