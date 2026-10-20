# Accumulation and consensus/report composition

## Scope and authority

Compose the [authorization-complete private candidate](accumulation-authorization.md) with the
exact authenticated consensus/report prefix retained in its source graph. Authority remains GP
0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`, merklization.tex C(4/5/6/8/9/10/11),
SHA-256 `1e05e9d1672ba94a72ba85b20843effeb721ff6fca8407d254a82d94116efdea`, plus the existing
[Safrole](safrole-transition.md), [disputes](disputes-transition.md),
[availability](availability-transition.md) and [report](report-transition.md) contracts.
No pins, algorithms, codecs, domains, PVM semantics or state-key construction change.

## Contract

Only PreparedAccumulationAuthorization constructs PreparedAccumulationConsensus. Retain the exact
source and derive its admission/block stage through the existing preimage/activity/validator/
timestamp/finalization graph. Do not accept independently supplied stages, assignments, maps,
headers or chapter lists. Copy C(4), C(5), C(6), C(8), C(9) and C(11) from that authenticated stage's
complete snapshot. C(10) comes from its exact completed report assignment plan, after incoming
guarantees, rather than the stage's earlier post-assurance table or the original parent table.

Preflight every selected chapter's actual byte length against a per-chapter ceiling and all seven
against an aggregate ceiling and native summed extent before materializing payloads. Add a copied
integer byte-length query to the retained report assignment owner so its existing entry extraction
can also be bounded before copying. This query does not encode, hash or expose writable storage.
The selected chapter list is fixed and contains seven unique keys; caller resource policies cannot
replace it. Genuine source constructors prove the retained complete chapter encodings.

Fork the exact accumulation authorization map with inherited store policies. Apply exactly seven
Puts in one atomic batch, including unchanged entries, and retain the resulting complete private
snapshot. Preserve C(1/2/3/7/12/13/14/15/16), all service metadata/storage/request/preimage entries
and opaque state. Do not copy the whole stage map over accumulation or replay disputes, Safrole,
assurances, signatures, guarantees, guests, history, statistics or preimage integration.

The acyclic immutable owner retains source, copied authenticated slot/chapter/byte observations
and complete successor. Failures/defaults carry reasons only; store lookup or atomic publication
causes have a separately guarded alternative. No original snapshot or canonical store is mutated
on success or failure. This is composition of the supported private candidate, not whole-block
validation/publication, transfer recursion, removal of account/privilege gates or light-state proof
support. M1 framing is complete; full state serialization and accumulation/block parity remain open.

## Completion tests

Use genuinely signed empty, incoming-only, newly-available and combined lookup/real-guest histories.
Include real culprit evidence, an epoch crossing with changed pending roster, and a genuine ticket
so copied C(5), C(8/9), C(4), entropy and time are observable. Independently construct C(10) from
verified guarantees and literal slot framing, assert exact C(11), and reconstruct complete expected
maps from the known source keys plus the six retained consensus entries and expected final C(10).
Require equal full-map roots, unchanged earlier chapters/account values, distinct post-assurance
versus final assignments, source identity, repeatability, copied observations and detached lifetime.

Exercise exact/one-below chapter and total ceilings, including an over-limit final assignment
entry, full-width policies and default owners. Policy refusals must precede hashing. Inject first
and final Merkle failures, require immutable sources and retry, and check 1,000 ARC success/
early-refusal/late-refusal cycles. Add strict extraction/privacy/source-substitution probes and
run selected native suites, affected fixture/assignment consumers, Python/inventory and pinned
formatting. Reuse unchanged lower-layer algorithms and published vector evidence.

## Local verification

Passed `make unit SUITE=accumulation_consensus`. Real signed empty/incoming/available/combined
histories, actual prior guest provisions, culprit evidence, an epoch crossing with changed pending
roster and a real RingVRF ticket compose the intended C(4/5/6/8/9/10/11) bytes. C(10) independently
framed from verified guarantees and literal registration slots differs from the earlier vacant
post-assurance table. C(11) matches literal E4 slot bytes while the source accumulator retains its
original parent time. Independent complete-map reconstructions match roots; earlier bookkeeping,
C(7)/C(12), every original account/request/preimage and opaque entries survive unchanged.

Exact and full-width byte policies pass. One-below chapter and aggregate limits (including the
final C(10) extent) refuse before hashing. A source whose inherited store permits six writes
refuses the fixed seven-Put batch without hashing or modifying the source. Immediate/final Merkle
failure preserves both accumulated and stage roots, and retry succeeds. Default/source guards,
assignment extent metadata, copied observations, source reuse and detached snapshot lifetime pass.
The 1,000-cycle success/first-hash-refusal/final-hash-refusal workload retains 1,992,704 occupied
bytes before and after.

Seven strict runtime extraction guards and six compiler privacy/source-substitution guards passed.
`make unit SUITE=accumulation_authorization` passed with 1,475,344 occupied bytes unchanged across
1,000 cycles; `make unit SUITE=report_assignments` passed its existing assignment/vector coverage
with 138,784 bytes unchanged. Python discovery passed 451 tests with seven skips. Inventory passed
119 failure families, 1,729 probes and 184 native suites. Pinned formatting passed 1,610 Nim files
and the Rust crate, and diff checks pass. No upstream pins or lower-layer protocol algorithms change.

Evidence remains under ignored `build/accumulation-consensus/`. These are local macOS checks,
separate from exact-head Linux CI and complete JAM/STF parity. Next bounded work is guarded
publication of the supported composed candidate against its exact original parent identity.
Transfer-aware recursion, remaining account/privilege merging and full block execution/validation
remain open. M1 framing remains complete; full state serialization and accumulation/block parity
remain open.
