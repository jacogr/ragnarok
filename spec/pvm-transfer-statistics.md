# Processed-transfer accumulation statistics

## Scope and authority

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex `accseq` and `accumulationstatisticsdef`, with unchanged vectors
and dependency pins. Extend the existing genuine-finalization statistics owner:
N counts processed work-digests, T counts each processed transfer by destination,
and G sums actual certified service gas, including skipped/zero-gas input groups.
Duplicate and zero-value/zero-gas transfers count separately. Failed host calls
and terminal-discarded outputs never enter later inputs and must not count.

Derive counts from each completed round's exact bound input groups, whose full
service coverage is already proved by completion. Initial inputs contain no
transfers. Continuation and repeated reentry inputs include exactly the selected
outgoing records from their genuine predecessor, before report operands. An idle
terminal entry contributes no transfer inputs; a transfer-only round dispatches.
No raw transfer sequence, substituted count, usage row or replacement state can
authorize statistics.

Add an independent processed-transfer ceiling alongside rounds, gas rows, reports,
digests and retained services. Preflight aggregate transfer cardinality before
reading input groups or allocating candidate rows. Reuse one candidate per
certified service gas row to carry that destination's transfer count, avoiding
per-transfer copies or memo traversal. Combine counts and gas by numeric service;
omit only (N,T,G)=(0,0,0), retaining transfer-only destinations even at zero gas.

Gross gas is initial budget minus terminal remaining budget plus all outgoing-gas
refunds represented by the completed continuation/reentry inputs. Check additions
before arithmetic; the public aggregate Gas and service gas remain uint64. A
history whose gross total exceeds that representation returns local LimitExceeded,
not protocol invalidity. Compare the independently accumulated actual rows against
that gross total; per-service sums are bounded nonnegative subsets.

Completion tests use genuine signed initial and repeated guest executions. Check
literal destination counts, duplicate/zero records, missing-code destinations,
terminal/checkpoint selection, mixed work-items, gross/refund reconciliation,
independent exact/short/full-width ceilings, retained identity/copied values,
hash-free preparation and 1,000 ARC cycles. Preserve report-only regression,
strict result/privacy/nominal contracts and canonical statistics codec behavior.

This layer derives activity deltas; C(13) coordination, account last-accumulation
updates and whole-block publication remain separate. M1 framing remains complete;
full state serialization and accumulation/block parity remain open.

## Local verification (2026-10-19)

Passed the selected native accumulation_reentry_cycle, accumulation_statistics
and state_statistics suites with the pinned compiler, ARC/Clang LTO and checked
bounds/assertions, reusing the existing prepared crypto/Bandersnatch libraries.
Both ownership suites retained fresh 1,000-cycle ARC evidence with unchanged
occupied memory: 920,480 and 1,116,064 bytes respectively. The expanded transfer
workload also performs 1,000 genuine prepare/execute/advance cycles with successful
and refused statistics preparation, checking no retained growth.

The real signed transfer chain gives literal destination counts 77=4, 88=2,
99=1, seven total. Its actual per-service gas matches the independently selected
certified execution rows; gross gas reconciles only after restoring all 90,000
paid outgoing gas. The mixed history processes all three reports, counts ten
transfers (77=6, 88=3, 99=1), and reconciles a 120,000 gas refund. Checkpoint,
hash-return, panic, fault and host OOG selections retain seven or five processed
records as appropriate. A missing-code destination receives four transfers and
has zero actual gas; its independently authored pre-C(16) complete-map root and
retained finalization owner remain intact. Zero-gas transfer-only destinations
survive all-zero omission, and transfers first emitted in later rounds are counted.

Exact/short/zero/full-width count, history, service-row and dictionary policies,
copied values/observations, hash-free queries and source ownership passed. A
genuine finite chain forwards offers near uint64 maximum and reaches stopped
finalization; its gross gas exceeds uint64, so statistics returns LimitExceeded
before scratch allocation rather than wrapping or labeling the history invalid.
The original report-only suite and canonical statistics codec suite also pass.

Five strict result-extraction probes, three privacy rejections, two nominal
rejections and the changed production module's semantic check passed. Pinned
formatting, local documentation links and whitespace checks passed. No PVM runtime,
codec, vendor source, gitlink or dependency pin changed. Witness development
corrected a root comparison to use the map before C(16), and explicitly enlarged
the mixed fixture's account capacity for its three service groups. Detailed logs
and results are retained under ignored `build/pvm-transfer-statistics*`. These are
local macOS checks, separate from exact-head Linux CI.

Next bounded work: update existing accounts' last-accumulation timestamps from
the genuine statistics mapping on an actual private finalized state. Complete
C(13) coordination and block publication remain separate. M1 framing remains
complete; full state serialization and accumulation/block parity remain open.
