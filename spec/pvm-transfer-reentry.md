# Transfer-aware accumulation reentry

## Scope and authority

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex `accseq`, `accpar` and `accone`, with unchanged vectors/pins.
Extend initial transfer continuation to the first and repeated later reentries:
collect only the just-completed batch's terminal-selected transfers in numeric
service order, preserve append order/duplicates/memos, and restore only their
paid gas. The next budget is prior budget minus actual gas plus outgoing gas;
reserve the outgoing gas before selecting reports. The refund cannot exceed
actual spent gas because each retained transfer paid its offer before commit.

Share canonical collection at the verified batch boundary. A batch collection
alone does not certify admitted-round provenance or a gas refund; the initial
round wrapper and private reentry step retain their own actual completion proofs.
No raw budget, replacement state, arbitrary transfer array or unverified outcome
can replace those proofs. Explicit source/transfer/memo limits bound every capture.

Each reentry retains only its immediate genuine predecessor and original root,
cumulative report offset, depth, canonical selected transfers and actual private
post-batch map. Transfer-only rounds dispatch even when gas is zero or reports
are blocked/absent; their report progress stays zero. No recurring allowances
are introduced. Inputs place transfers before operands by destination. Credits
occur from the actual post-debit map when services are prepared, then publish
only through the existing complete batch. Repeated advance still checks depth
before work; a certified stopped entry cannot restart.

Completion witnesses cover first/repeated transfers, exact gas restoration and
report reservation, zero-gas transfer-only dispatch, credit once per round,
checkpoint rollback, canonical duplicates/memos, source ownership, independent
and combined limits, stopped/depth refusals, backend rollback and ARC release.
Use genuine signed admitted roots and actual guest executions; preserve existing
report-only cases and result/privacy guards.

[Processed-transfer statistics](pvm-transfer-statistics.md) now derives destination
counts and reconciles gross gas from genuine completed inputs. It replaces the
historical statistics scope gate; independent transfer limits and uint64 aggregate
representability remain explicit local limits. Account timestamp/C(13) integration
and whole-block publication remain separate.
M1 framing remains complete; full state serialization remains open.

## Local verification (2026-10-19)

Seven selected native suites passed using the supported native runner with the
pinned compiler, ARC/Clang LTO, bounds/assertions and already prepared libraries:
accumulation_continuation_inputs, accumulation_batch, accumulation_reentry,
accumulation_reentry_execution, accumulation_reentry_cycle,
accumulation_statistics and accumulation_finalization. Every suite retained fresh
1,000-cycle ARC evidence with equal occupied memory before/after. The expanded
cycle suite retained 920,480 bytes and also checked a separate 1,000-cycle real
transfer prepare/execute/repeated-advance workload without retained growth.

The authored chain completes three dispatched later rounds and a stopped
entry, checking independently authored full-map roots and literal balances at
each step. Reversed completion arrival still produces source order 77/99/99,
with both identical 99 records and all 128 memo octets preserved. Mixed selection
reserves 30,000 outgoing gas before choosing the 150,000-gas report; the next
20,000-gas report cannot consume that reservation. Near-uint64-maximum budgeting,
terminal/checkpoint selection and hash-backend refusal cases passed. Histories
with transfers first appearing in later reentry, including zero-gas records,
finalize successfully but explicitly refuse report-only statistics without hashing.

Forty strict runtime extraction checks passed across batch, reentry, statistics
and completed-round transfers, including both new public collection APIs.
Twenty-three privacy rejections and the batch-as-admitted-round nominal rejection
passed with their exact intended diagnostics. Changed production modules and the
outputs, finalization, history and statistics consumers passed semantic checks.
Nine inventory tooling tests, source-owned inventory, pinned changed-source
formatting, local documentation links and whitespace checks passed.

The scratch regression selector initially named a nonexistent optional invocation
suite after four suites had passed. Removing that name resumed only the remaining
checks; the passed suites were retained. Actual reentry invocation is covered by
the real guest cycle and reentry-execution suites. No compiler, vendor source,
gitlink or dependency pin changed. Logs and detailed results are retained under
ignored `build/pvm-transfer-reentry*`; these are local macOS checks, distinct from
exact-head Linux CI.

[Processed-transfer statistics](pvm-transfer-statistics.md) implements that next
bounded item and removes the statistics scope gate. Account last-accumulation
updates and complete C(13) coordination remain subsequent work. M1 framing remains complete; full state
serialization and full accumulation/block parity remain open.
