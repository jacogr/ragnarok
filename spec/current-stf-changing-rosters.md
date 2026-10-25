# Current STF qualification while validator populations change

Authority remains Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and
pinned gp-next `23061ae1f9b51171c01387e7dde0f15794c98e24`. Expected current
encodings and successors derive independently from the GP and authored inputs.
Original compatible published witnesses corroborate their stated scope. No other
JAM client's emitted state supplies an expected answer.

The bounded three-core profile has independent active/previous/pending/staging
populations up to nine, including six→nine→six promotion, retained previous-roster
credentials and delayed full null-record activation. Structural C10 capture covers
both current and previous populations; admission selects the actual roster, while
erasure shards remain tied to the current population.

| Qualified interaction/boundary | Complete transitions per corpus | Contract |
| --- | ---: | --- |
| Prior/current credentials, quorum and resize clearing |20|[Population reporting](current-stf-population-reporting.md)|
| Offender Phi, cancellation/replacement and delayed nulling |22|[Offender reporting](current-stf-offender-reporting.md)|
| Actual report-triggered writes, panic and checkpoint effects |30|[Population guests](current-stf-population-guests.md)|
| Ticket contests, winner/fallback sealing and later growth |32|[Ticket reporting](current-stf-ticket-reporting.md)|
| Deferred waves, release/resize-clear and actual-gas continuation |72|[Dependency waves](current-stf-population-waves.md)|
| Exact residual budgets, retention/expiry and pooled gas exits |144|[Gas behavior](current-stf-population-gas.md)|
| Complete lookup tuples and inclusive configured age |26|[Historical anchors](current-stf-population-anchors.md)|
| Full checkpoint continuation under external expected roots |102|[Checkpoint restart](current-stf-population-restart.md)|
| Authenticated complete TraceStep imports and wrong-map/seal refusal |102|[Trace import](current-stf-population-trace.md)|
| Portable configured bundles and actual offline commands |70|[Operator command](current-stf-population-command.md)|

These corpora overlap; the rows are separate observed workloads, not a sum of
unique blocks. Feature contracts retain exact refusal counts, source identities,
checked macOS/Linux evidence and limitations. Checkpoint envelopes remain local
storage; published RawState/TraceStep framing remains a separate wire boundary.

[Serialization status](jam-serialization-status.md) records complete current GP
serialization qualification within its finite scope. M1 framing completion alone
never establishes complete state serialization, valid-state relationships or STF
correctness. The interaction cases above extend independently derived whole-map
execution and operator qualification without changing that distinction.

Remaining scope includes arbitrary population/offender histories, all host-operation
combinations under resizing, full JAM/STF and live client/network/finality conformance.
No external-client execution or physical power-loss qualification is inferred.

The final operator qualification also replays the repaired authenticated trace
driver on checked Linux. Its complete outputs and all8,038 frozen source/native
inputs match the macOS qualification; the retained final image identity and exact
workload counts are recorded in the operator contract. All15 native stacked PRs
were observed open/ready with exact published heads and green exact-head Smoke
checks before this evidence-only documentation update.
