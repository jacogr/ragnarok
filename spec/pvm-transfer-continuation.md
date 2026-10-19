# Completed-round transfer continuation

## Scope and authority

GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex equations `accpar`, `accseq` and `accone` order selected service
outputs numerically, concatenate outgoing transfers without deduplication, and
use `g* = g - actualGas + outgoingGas` for the recursive budget. The next call
reserves outgoing gas before choosing its affordable whole-report prefix.
Thus the report-only remainder remains `g - actualGas`. Free allowances do not
recur. Pins and wire formats remain unchanged.

Bind collection to an actual `CompletedBlockAccumulation`, retaining its admitted
round and complete common-source batch. Canonicalize executed outcomes by numeric
service ID; certified skips contribute no outgoing records. Preserve each
terminal-selected append sequence, duplicates and complete fixed memos. Bound
execution descriptors, transfer count and memo bytes independently before copying.
The sum of selected outgoing gas cannot exceed actual completed gas: each retained
transfer paid its offered gas before committing. Check this invariant by bounded
subtraction, then prove the restored recursive budget fits within the original
budget. No arbitrary source, gas observation or transfer array can replace the
completed round's effects.

Initial continuation selection reserves that gas, retains its bound transfer plan
and dispatches when either reports or transfers exist, including zero-gas transfers
with an empty queue. Materialize transfers before report operands in each service's
inputs, with no recurring allowances. Apply the original batch privately before
resolving destination services, so destination credit occurs only when those
services are prepared from the actual posterior map. No caller state is published.
Explicit zero transfer/memo capacity authorizes no nonempty collection.

Completion witnesses use genuine admitted rounds and authored transfer hosts.
Check canonical service order independent of execution order, terminal/checkpoint
selection, exact gas restoration/reservation, mixed/transfer-only/empty work,
destination gas/input order and credit, no allowance recurrence, exact work limits,
default/source ownership and immutable extraction, atomic backend failure and
1,000 ARC cycles. Add runtime extraction, privacy and nominal guards as relevant.

Later reentry still refuses newly emitted transfers until its own selection/input
binding is extended. This is initial recursive preparation, not full accseq, final
processed-transfer publication or whole-block parity. M1 framing is complete;
full state serialization remains open.

## Local verification (2026-10-19)

Seven native suites passed: initial continuation, continuation inputs,
continuation invocation, continuation execution, initial execution, reentry and
reentry execution. Every suite retained fresh 1,000-cycle ARC evidence with
unchanged occupied memory. The expanded input suite stayed at 524,768 bytes;
its separate new 1,000-cycle transfer planning/input/state workload also checked
unchanged occupied memory.

The genuine signed fixtures cover canonical source ordering with reversed
execution arrays, duplicate opaque memos, checkpoint/panic/fault/OOG/hash-return
selection, mixed transfer/report groups, transfer-only zero-gas dispatch, skipped
services, exact refund/reservation and a maximum-uint64 original budget. Source
99's balance changes from 20 to 15 in the private post-debit map; destination
77 remains at 10 there and becomes 15 only in its prepared service state.
Initial allowance-only sender 42 does not recur. Combined transfer/report and
late destination-union caps refuse before hashing; private backend failure
retains the original parent. Copied observations and detached owners remain
independent.

Twenty-one strict runtime extraction checks, eighteen privacy rejections and
one nominal batch-as-round rejection passed. Four downstream modules (outputs,
statistics, finalization and history) passed semantic compilation, in addition
to the three directly changed/new production modules. Inventory, pinned
formatting, feature links and whitespace checks passed. The scratch driver
requested a nonexistent optional reentry-cycle module after its four real
module checks had passed; its list was corrected without repeating passing
checks. Final selected checks are audited in
`build/pvm-transfer-continuation/summary.json`. Logs are under
`build/pvm-transfer-continuation-*.log` and the native runner's selected folder.

Only the recorded ark-vrf and Bandersnatch-spec gitlinks were initialized for
these newly exercised real-round tests. Repository providers verified their
source hashes, SRS, locked dependency closure, pinned Rust and native tests
before preparing libraries. No upstream source, gitlink, lockfile or toolchain
was changed. These are local macOS checks; exact-head Linux CI is separate.

Next bounded work: extend canonical collection, paid-gas restoration and input
binding to later reentry rounds while retaining cumulative queue/state provenance.
