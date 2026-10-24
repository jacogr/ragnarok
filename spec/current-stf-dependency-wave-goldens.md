# Whole-map STF goldens for deferred dependency waves

Scope: seven authored seven-block chains at slots1→8, forty-nine complete current-candidate
transitions. Pins remain Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, Draft35 Thin
v1/ark-vrf0.6.0 and vectors `23061ae1f9b51171c01387e7dde0f15794c98e24`. Authority is the pinned
`accumulation.tex` immediate/deferred partition, E queue editing, Q priority waves, `accseq`
declared/actual gas equations and final ready/history equations, together with report package/root
relations, availability, statistics and literal guest write/yield/checkpoint behavior.
Production, dependency pins, upstream fixtures and the AmbiguousPrivileges guard are unchanged.

## Reachable authored chains and independent calculations

These cases reuse the exact complete originals of the report-driven guest cases, with no free
accumulation allowances. Every waiting report enters through genuine guarantees and availability
votes in the tested chain. No ready row or accumulated history is injected into the original.
The fixture binds the earlier guest-fixture SHA-256; all older fixture bytes remain unchanged.

Five chains use the literal create, replace, delete, panic-rollback and checkpoint-panic guests.
Their reports form the same graph, with A targeting halt service42 and B–E targeting service99:

| Block | Guarantees | Availability and queue effects |
| --- | --- | --- |
| 2 | None | Empty child, no guest operands |
| 3 | A on core0; B on core1 with prerequisite A | Both pending; same-block dependency is honestly signed |
| 4 | C on core1 with prerequisites A,B | Release B only; retain B→A in ready row4 while A stays assigned |
| 5 | D on core1 with segment-root lookup C | Release C; retain C→{A,B} in row5 |
| 6 | E on core1 with prerequisites B,D and lookup B | Release D; retain D→C in row6; repeated B dependency is a set union |
| 7 | None | Release A and E; A is immediate, then Q unlocks B, C, D, E in four successive waves |
| 8 | None | No guests; preserve accounts, clear outputs and age processed history |

Each lookup names the exact independently authored segment root of a previously reported package.
At block7, E removes immediate A from dependencies, and each Q wave removes its actual package
before finding the next wave. The reference orders rotated parent ready rows before newly deferred
reports, preserves report order and canonically sorts dependency sets.

Every report declares 100,000 accumulation gas. The first affordable prefix is exactly A,B,C under
the 300,000 block budget. Its actual guest consumption leaves enough for D,E in a continuation.
Service99 executes once with two operands in each batch; its statistics count four operands and
two independently calculated guest charges. Service42 executes once and costs22 gas. Literal gas
comes from the independent pinned PVM table simulator and GP host prices. Sequential mathematical
batches see the earlier batch's state, so repeated writes, deletes, rollback and checkpoint retention
have their correct footprints and terminal output set. Identical yields produce one retained pair.

Two further chains honestly admit A↔B mutual prerequisites in the same block, then make both
reports available. Q finds no dependency-free wave. Both full reports remain in ready row4 through
block8, with no guest execution, false processed history, timestamp changes or output commitment.
These are admitted unresolved cycles, not malformed-input rejection cases.

## Whole-map verification

The independent reference calculates all original checkpoints, signed children, complete successor
maps, Q waves and affordable-prefix traces before native execution. The existing report-guest driver
consumes only the independently authored extrinsic bodies; no second native runner is added.
Test-only policies explicitly allow five processed operands/hashes in a block and the same two
bounded payload records in initial and continuation dispatch. They do not weaken production checks.

The registered `current_stf_dependency_waves_corpus` compares every P/B/O line byte-for-byte.
Five resolving chains process twenty-five reports using fifteen guest invocations in total; the two
cycle chains process none. Complete expected entries include C14 dependency editing/removal,
C15 sorted package history, C16 output deduplication/clearing, C3 output-sensitive MMR/header
commitments, C10 release/replacement, C1 authorizer pools, and incoming/available/accumulation
statistics. Code, preimage requests, balances and unrelated namespace entries are preserved.

The shared helper extension must also retain all thirty-five earlier report-guest maps and exact
native output hash. Scoped Python invariants inspect waiting rows, lookup unions, wave order,
prefix boundaries, actual gas, timestamps, output deduplication and cycle non-progress. Pinned
formatting, fixture provenance and inventory checks accompany publication. Full observed evidence
is retained under `build/state9-stf-dependency-waves/`. The registered native runs passed all49 new
and35 prior transitions with identical expected/actual output hashes;83 affected Python checks
passed. Prior checked interpreter/ARC evidence remains applicable to unchanged production sources.

This is authored current-profile STF evidence, not full JAM parity. Transfer-driven re-entry,
budget-exhausted deferred retention and execution across epoch boundaries remain subsequent
whole-map work. Existing historical-profile mismatches and ambiguity guards remain recorded.
