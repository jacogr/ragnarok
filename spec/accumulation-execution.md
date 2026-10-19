# Admitted initial accumulation execution and gas

## Scope and authority

Bind complete common-input batches to genuine `BlockAccumulationRound` plans and expose the
service-indexed actual gas sequence and its total. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f` (`accpar` gas sequence,
`accseq` budget) and pvm_invocations.tex SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb` (`accinvocation`, collapse).
The basic-block affordability rule is from pvm.tex at the same revision, SHA-256
`b5b4a54ae77aea6b0a599e85d895c377841b89d039206cafc277473bc8f8aa97`.
Pins, public encoding interpretations and the parked request-domain question do not change.

Derive the exact input owner, admitted parent complete-map snapshot and authenticated candidate slot
from the retained round. For executed services, also require the original bootstrap entropy to equal
the completed stage's posterior C(6) word, checking its exact 128-byte extent before decoding.
All-skip/empty alternatives do not initialize I or read entropy. Accept only actual dispatches and certified skips, then invoke the existing
complete batch preparation once. Do not accept replacement input/state/slot or caller-authored gas.
Retain one gas row per service, sorted numerically, with actual terminal gas from normalized outcomes
and zero for skips. Check descriptor bounds before allocation and remaining budget before addition.
Keep declared reservations distinct from actual usage; checkpoint rollback does not refund gas.
The pinned PVM's basic-block affordability rule (`pvm.tex` gas transition) leaves positive gas
unchanged on an unpaid block, whereas an underfunded host call produces negative posterior gas.
Collapse charges the former only for earlier paid work and caps the latter at the initial credit;
never assume every out-of-gas exit consumes the full allowance.

Retain the original round and complete batch as separate immutable certificates. Batch extraction
uses existing atomic application and exact-prior stale protection; completion itself publishes no
state. Nested batch failures carry only the failed parent's reasons and preserve all guarded nested
normalization/provision/store diagnostics. No successful batch accompanies a refused completion.

This certifies initial-round source binding, supported batch state and gas accounting. It does not
complete privilege/account mutation merging, deferred transfer/yield collection, later-round
scheduling or full block publication. Existing selected-account and halt-return/provisions gates
remain. M1 framing remains complete; full state serialization and accumulation/block parity remain
outside this increment.

## Completion tests

Use genuinely signed admitted rounds with multiple services and actual PVM halt, panic/checkpoint,
out-of-gas and certified skip outcomes. Compare literal actual gas, numeric service order and totals
against declared reservations. Cover complete/all-skip/empty rounds, limits, default/local-refused
sources, foreign equal-content round owners, wrong parent/slot/posterior entropy, retained source lifetimes, immutable
observations and full-map atomic batch application. Check nested failure/default extraction,
privacy and nominal rejection, no extra hashes for gas collection and 1,000 ARC release cycles.
Run the new suite through the maintained runner, reusing unchanged complete-batch evidence;
verify inventory/provenance and formatting.

## API and ownership

`completeBlockAccumulation` accepts a genuine bound round, actual completed dispatches, certified
skips and independent gas-row/batch ceilings. It derives the inputs, admitted parent and slot from
that round and checks actual invocation entropy against the block stage's posterior C(6) before
union hashing. Counts bound this preflight; invalid dispatches retain the batch adapter's refusal.
No replacements for those protocol inputs are accepted by the API.

`CompletedBlockAccumulation` privately retains the exact round, one complete batch and an owned
numeric-service-ordered gas sequence. `executionInfo` copies declared reservation/batch observations
and actual total. `executionGasAt` uses the retained input-service ordinal and proves full-width
bounds before narrowing. `executionRound` and `executionBatch` retain genuine immutable source and
publication handles. Callers publish through the existing `applyAccumulationBatch`; its atomic and
exact-prior stale checks remain authoritative. No state is published by completion itself.

`AccumulationExecutionResult` has private tags and success payloads. `batchFailure` exposes only
an actually refused `AccumulationBatchResult`, which retains reasons alone; all nested terminal,
normalization, provision and store extraction contracts remain intact. No earlier successful batch
is stored in a completion refusal. Gas-row bounds precede allocation and remaining-budget
subtraction precedes every total addition. Default owners never become empty successful rounds.

## Local verification

Passed the maintained `make unit SUITE=accumulation_execution` checked ARC/Clang-LTO suite. Authored
signed rounds distinguish 200,000 reserved allowance gas plus 10 report gas from 44 actual gas.
Canonical rows remain service 42 then 99 even with reversed execution order. A checkpoint/panic
costs 203 gas, a rejected unaffordable block uses zero, and a negative host-gas terminal consumes
its full 200 credit; certified skips and empty rounds use zero. The suite also verifies exact source
and posterior-entropy rejection, copied observations, retained lifetimes, hash-free completion and
batch queries/publication, nested parent reasons and stale publication against intervening changes.
Its 1,000-cycle ownership workload retained 1,063,584 occupied bytes before and after.

Seven strict runtime extraction probes and five privacy/nominal compiler rejections passed.
Python discovery passed 441 tests with six skips. Source-owned inventory/provenance, pinned
formatting and diff checks passed. The new suite registers the existing checksum-verified static
report witness and explicitly needs no generated corpus setup. Unchanged complete-batch production
and tests reuse the parent's verification; no PVM or existing merger implementation changed.
Public documentation follows the Nim API/doc-comment conventions; rendered Nim 2 docs remain
unavailable for the pinned Nimony dialect as recorded in the earlier API cleanup.

Logs and diagnostics are retained under `build/accumulation-execution/`. These are local macOS
results; exact-head Linux CI remains separate. The [output projection](accumulation-outputs.md) now collects terminal-selected round commitments.
Later-round planning and selected mutable account/privilege merging remain subsequent bounded work.
