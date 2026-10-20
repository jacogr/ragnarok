# Posterior active-roster eligibility for computed reports

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex computereport and reporting_assurance.tex
current active core and erasure-shard population rules. Vector revision remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume only TransitionBoundComputedReport. Read C8 from its exact retained
authenticated post-assurance, pre-report snapshot. Bound the serialized chapter
before copying and decode it exactly using original configured core count and
independent local record/byte ceilings. Reject missing, malformed or suffixed
state. Derive population from the decoded posterior roster, require the original
computed report core below population/3, and require erasure shards equal that
population. Never substitute configured parent population or the structural
3*cores ceiling. Retain original transition/computation provenance and immutable
roster only after complete success; copied population facts are not certificates.

This checks current population eligibility, including for eventual previous-rotation
credentials. Assignment, evaluation-slot age, offender nulling, credentials,
exporter state, report inclusion, availability and signing remain open. It inherits
the authenticated prefix's policy/chainspec limits and establishes no finality.

Completion plan: genuine signed ordinary and epoch-crossing computation sources;
three configured cores with six posterior validators; core1 acceptance/core2
refusal and structurally valid shards9 refusal; real parent population9 ->
posterior6 epoch shrink proving both checks use posterior state; exact/short
record and byte limits; default/source/result/accessor refusals; immutable copied
records/facts, caller publication and detached lifetime; zero new hashing/execution/
publication; 1000-cycle ARC release; strict runtime and compiler privacy/nominal
guards with real successful controls. Defensive malformed/missing chapter branches
must never be covered by forging a successful transition result.

Next: guarantor assignment/evaluation-slot eligibility from this same authenticated
posterior context. M1 framing is complete; full state serialization and whole-block
parity remain open.

Local evidence: optimized checked macOS ARM64 `make unit
SUITE=pvm_computed_roster` passes genuine original PVM computation, all retained
state/recent/lookup/configuration bindings and signed block-prefix authentication.
The three-core fixture preserves original authorizer membership across its
three-row C1 and authors exact three-row absent C10 before committing the parent
root and re-signing the candidate. Epoch shrink extends only parent C8 to nine
real validator identities while pending/staging retain six; real Safrole rotates
the active set down to six. Parent metadata is independently nine, returned
posterior population is six, core1 passes/core2 fails, and six shards pass while
nine shards fail. These negative reports genuinely completed the earlier
structural/computation/authentication boundaries.

The exact canonical six-validator chapter is 2017 bytes. Record ceiling6 and
byte ceiling2017 pass; ceilings5 and2016 independently refuse. A looser caller
record ceiling cannot change the configured protocol bound or actual population.
All 336 bytes of each ordered posterior record match a separate decode of the
retained exact chapter. Copied records/facts, caller store publication and detached
lifetimes preserve immutable provenance. Eligibility under hash-backend refusal
makes zero hash attempts. Fresh warmed 1000-cycle ARC occupancy is
320176/320176 bytes. Default sources/results and all three accessor defaults
retain typed refusal. Missing/malformed-state defenses are not reached through
forged successful coordinators.

Seven strict compiler privacy/nominal guards, optimized runtime extraction guards,
formatted semantic checks, inventory, 20 affected tooling tests and pinned
formatting provide local evidence. Existing lower-layer source/build inputs and
specification/toolchain pins remain unchanged. Remote CI has not been requested.
