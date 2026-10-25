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
| Manager/assigner handoffs, queue precedence and delayed allowances |210|[Privileged updates](current-stf-rotation-privileges.md)|
| Guest-designated staging, delegator handoff and delayed promotions |180|[Validator designation](current-stf-rotation-designation.md)|
| Direct/deferred transfers, memo execution, balance pools and gas refusals |320|[Transfers](current-stf-rotation-transfers.md)|
| Public/reserved creation, retirement/refunds and complete dynamic namespaces |180|[Creation and ejection](current-stf-rotation-creation.md)|
| Child code provision/readiness and pending-report current-code upgrades |100|[Code activation](current-stf-rotation-code.md)|
| Reservation cleanup, same-slot retirement refusal and fresh incarnations |140|[Retirement and recreation](current-stf-rotation-retirement.md)|
| Foreign funding, direct pools and concurrent junior-write annulment |140|[Foreign funding](current-stf-rotation-funding.md)|
| Supervised storage/requests, annulled yields and retained provisions |150|[Supervised effects](current-stf-rotation-supervision.md)|
| Immediate supervisor handoff, protected authority and foreign upgrades |150|[Authority transitions](current-stf-rotation-authority.md)|
| Request/provision ordering, strict expiry equality and restored histories |190|[Preimage lifecycle](current-stf-rotation-preimages.md)|
| Forwarded reentry and active-supervisor held duplicate-credit rounds |100|[Transfer waves](current-stf-rotation-transfer-waves.md)|
| Recreated supervisor bindings and exact queued old-report identity |100|[Supervisor incarnations](current-stf-rotation-incarnations.md)|
| Further offender-filtered promotions, surviving authors and fixed quorum |34|[Extended histories](current-stf-rotation-histories.md)|
| Host/lifecycle checkpoint restarts and complete authenticated traces |85 each|[Host-history replay](current-stf-rotation-replay.md)|
| Portable host-history bundles and actual public offline commands |85|[Host-history operator](current-stf-rotation-command.md)|
| Late code extrinsics at growth/shrinkage and exact non-retroactive execution |200|[Late code ordering](current-stf-late-rotation.md)|
| Deferred dependency waves with code arrival and resize clearing |360|[Late-code dependencies](current-stf-late-dependencies.md)|
| Missing-code skips versus genuine pooled gas exhaustion |240|[Late-code gas exits](current-stf-late-gas.md)|
| Exact deferred admission, zero-gas draining and ready-row expiry |216|[Late-code retention](current-stf-late-retention.md)|
| Unresolved cycles/published anchors through code arrival and exact row expiry |224|[Late-code cycles](current-stf-late-cycles.md)|
| Selected posterior request relevance and actual extrinsic accounting |100|[Selected posterior request relevance and actual extrinsic accounting](current-stf-late-relevance.md)|
| Strict code expunge, recreated requests and later actual reactivation |144|[Strict code expunge, recreated requests and later actual reactivation](current-stf-late-reactivation.md)|
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

The earlier operator qualification retains its original8,038-input Linux evidence
in its feature contract. The current host-history checkpoint/trace and operator
contracts record the extended independent workloads and their source identities.
PR publication and exact-head CI observations remain separate from these local
checked replay results.
