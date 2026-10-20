# Authenticated transition binding for computed reports

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex computereport and existing authenticated
header/disputes/Safrole/assurance prefix contracts. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume ConfiguredComputedReport and completed BlockTransitionResult.
Require exact original execution map identity, framing cores/epoch/validator
ceiling/ticket limit matching original configured parameters, and byte equality
of the complete canonical sealed candidate header. Compare bounded encodings,
without hashing or re-executing authentication. Retain the original configured
source and the genuine private successful transition result, including its exact
post-assurance, pre-report snapshot. Never accept its public mutable payload as
constructor input. A copied payload cannot replace the retained posterior map.

This authenticates the existing prefix for the exact candidate, under the
transition policies supplied to that coordinator. It does not validate every
transition policy against chainspec, establish finality, include the computed
report in the block, verify exporter state, or authorize signing. Posterior roster,
assignment and evaluation-slot eligibility remain separate. The configured
parent C8 population is never used as posterior population here.

Completion plan: genuine original code/history committed before real signed
block creation; original PVM computation plus state/recent/lookup/profile stages;
ordinary and epoch-crossing transitions; same-map different candidate and seal-only
substitution refusal; equal-root independently rebuilt map refusal; failed/default
transition/source and bounded-header rejection; exact limit acceptance; copied
payload/source lifetime and caller publication isolation; zero hashing/backend
attempts in binding; 1000-cycle ARC release; strict runtime success-extraction
and compiler privacy/nominal guards with genuine controls.

Next: source-bound posterior roster/core/shard eligibility, then guarantor
assignment/evaluation-slot and availability/signing integration. M1 framing is
complete; full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit
SUITE=pvm_computed_transition` passes genuine original computation, all retained
anchor/configuration stages and real signed coordinator transitions. Exact
header byte limits pass and one-byte-short/zero limits refuse. Equal-root
reconstructed maps receive genuine successful coordinator results but cannot
replace the original map. A correctly signed different child of the same exact
map and an independently admitted seal-only alteration both return HeaderMismatch.
A differing original ticket ceiling returns ProfileMismatch. Failed/default
sources/coordinators/results/accessors remain typed refusals. Public payload
copies, caller publication and detached owner lifetimes cannot replace retained
original or posterior snapshots. Epoch crossing has a genuinely different active
roster. Binding under hash-backend refusal attempts no hashes. Fresh warmed ARC
occupancy is 292720/292720 bytes over 1000 cycles.

The entire native stack was synchronized onto merged fixture-discovery PR #316,
master `231d5544351834dd1d761c01ab94cc530de17e01`, through guarded native sync.
All sixteen pre-existing layer diffs are byte-identical after that restack. This
suite generates its own original signed/PVM inputs and declares no static fixture
dependency under the new descriptor contract. Six compiler privacy/nominal guards,
strict optimized result guards, formatted semantic checks, inventory, 20 inventory
tooling tests and all 13 new fixture-contract tests provide focused local evidence;
remote CI has not been requested.
