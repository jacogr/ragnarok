# Whole-map STF goldens for report-driven guest execution

Scope: five authored seven-block chains at slots1→8, thirty-five complete current-candidate
transitions. Pins remain Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, Draft35 Thin
v1/ark-vrf0.6.0 and vectors `23061ae1f9b51171c01387e7dde0f15794c98e24`. Authority is the pinned
`accumulation.tex` immediate/queued partition, `accseq`, service grouping, X/Y exceptional
selection, accumulated-history and ready-ring equations, together with availability, reporting,
statistics, service-account and host write/yield/checkpoint rules. Production and pins are unchanged.

## Independent authored inputs

The new fixture binds the exact earlier authored guest-fixture SHA-256. Its original complete maps
retain those literal code preimages, request histories, balances and namespace footprints. C12's
two always-accumulate allowances are removed before signing any tested child. The old inputs and
upstream fixtures remain unchanged. The native driver independently constructs the same originals
through the existing public fixture/state interfaces; neither side substitutes an observed successor.

Each incoming report has six erasure shards, an empty prerequisite/lookup set, the actual target
service code hash, a 100,000 gas limit and distinctive package, bundle, segment and refinement
fields. Two honestly assigned Ed25519 credentials sign its full report hash using the maintained
`jam_guarantee` domain. Recent and lookup anchors bind original slot1 and its actual complete-map
root. Assurances sign the actual parent under `jam_available`. Mathematical Thin supplies exact
independent child seals and entropy proofs. The inherited ring root is an input witness.

The independent Python reference calculates every child and entire map before native execution.
It reuses independent literal PVM instruction/gas-table calculations from the authored guest
reference, rather than deriving gas, storage or outputs from the implementation. No production
Python runtime, stored successor map or native gas observation supplies an expected result.

## Chain behavior

Each storage mode (create, replace, delete, panic rollback, checkpoint followed by panic) follows
the same genuine reporting sequence:

| Block | Input and expected effect |
| --- | --- |
| 2 | Empty body; no allowances or report operands, so no guest execution |
| 3 | Two guarantees: core0 targets the halt service42, core1 the storage/yield service99 |
| 4 | Four both-core assurances retain both assignments and execute neither guest |
| 5 | Five core1 assurances release only service99's report and execute its literal guest |
| 6 | Five core0 assurances execute service42; two replacement guarantees both target service99 |
| 7 | Five both-core assurances release the replacements; two operands share one service99 invocation |
| 8 | Empty body; service metadata/storage stay fixed, outputs clear and history ages |

There are fifteen guest invocations and twenty processed reports. The same-service two-report
batch counts two operands while charging the guest once. Retained writes yield one service99
commitment; ordinary panic rolls back its write/yield, whereas checkpoint-panic retains both.
Every invoked service updates its last-accumulation slot even on panic. Actual footprint replacement
and deletion are calculated from original storage lengths; balances and preimage requests stay fixed.

Complete expected maps also cover incoming guarantee statistics separately from released-report
DA load and accumulation statistics; per-core strict quorums; post-assurance vacancy/replacement;
C1 authorizer removal; C3 package dictionaries and output-sensitive MMR/header commitments;
C10 full assignment changes; C15 sorted processed-package rows shifted once per child; and C16
terminal implications. All reports are immediate and fit the block budget, so C14 stays empty.

## Completion checks and limits

The registered `current_stf_report_guests_corpus` uses the existing checked ARC/Clang native
harness and compares every original checkpoint, signed child and entire successor checkpoint.
`test_current_stf_report_guests_oracle` separately checks quorum isolation, absence of free execution,
per-service operand/gas statistics, rollback/checkpoint effects, timestamps, history aging and outputs.
Pinned formatting, fixture provenance and verification inventory checks accompany publication.
The native fixture explicitly permits two fetch operands, each with at most a two-byte successful
output and five-byte authorization trace; these are local test resource bounds, not protocol changes.
Observed results and full logs are retained under `build/state9-stf-report-guests/`.

This extends the authored current-profile STF evidence, not full JAM parity or regenerated historical
traces. The earlier thirty-five typed report/assurance refusal controls remain applicable. Deferred
prerequisite resolution across priority waves, transfer/re-entry effects and execution across epoch
boundaries remain subsequent whole-map work. The AmbiguousPrivileges guard remains unchanged.

Deferred resolution and actual-gas continuation are covered by
[the dependency-wave whole-map cases](current-stf-dependency-wave-goldens.md).
