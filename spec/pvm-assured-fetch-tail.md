# Guest-derived nonempty fetch tails

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, fetch selector15,
full returned lengths, clipped copy intervals and64-bit immediate arithmetic;
vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author an original FetchTail guest before computation/signing. It first queries
record0 with requested length0 and an invalid destination, receiving full lengthN.
Actual add_imm_64 derives offsetN-1 from that returned register. A second fetch
requests3 bytes into RW, copies only the final record byte, and returns fullN
rather than copied count1. Real store_u64 retains this complete return word at
RW+3; write all eleven bytes through the normal storage host and state pipeline.

The independent canonical tail oracle is the last raw authorization-trace byte,
or literal0 for an empty trace's final count byte. Preserve initial RW22/23 beside
the one copied byte. Append independently encoded LE64 of the actual canonical
operand extent. No guest memory, completed input or report is patched. Existing
full-return fixture funding58 and local capture11 apply only to this new mode;
original gas, parameters and all prior mode policies remain unchanged.

Query costs355, request3 costs357 and write11 costs2449. The single prepaid block
is at most997 under the unchanged analysis bound: assert actual gas>3161and<=4158.
The authored path uses18 instructions and3 hosts within existing20/4 limits.

Completion: original and assured successor actualHalt/Regular, exact clipped byte,
untouched suffix and full returned word, canonical metadata/history/statistics/
parameters/state/view, real host-call/copy/effect refusals and1000 full guest/
composition/publication ownership cycles. Recheck all affected older storage,
outcome, operand, list and full-width range suites. Inventory/tooling and pinned
formatting required; production code remains unchanged.

Next: use actual input data to control guest storage mutations.
M1 framing complete; full serialization, whole-block parity and full chainspec
equivalence remain open.

Observed local native evidence: both original and successor guests actually query
length, computeN-1, copy the final canonical byte and Halt/Regular. The copied byte
matches the source's last raw authorization-trace byte, or the literal empty-trace
count0; it differs from initialRW21. The next bytes22/23 remain untouched, and all
eight stored return bytes equal fullN, not clipped copied count1. Canonical operand
extent also matches its independently retained consumed metadata. Actual gas is
greater than3161 and no more than4158.

A two-host ceiling refuses before the storage call with RunnerFailure/
DispatchFailure/ExecutionFailure/HostCallLimitExceeded. Copy ceiling11 succeeds
and10 refuses with DispatchFailure/LimitExceeded at actual storage capture. Final
value ceiling10 preserves CompletionFailure/BatchFailure/LimitExceeded. Original
canonical state/view remain exact after all refusals. Successful composition and
publication retain exact bytes, footprint46/item1/balance58, timestamp3, history3,
activity reports2/refinement0/actualgas, all29 parameters and finality1.

One thousand full dynamic guest executions/compositions/publications retain
753792/753792 occupied bytes. Five affected older suites pass again at1000 cycles:
ranges938352, list1459632, individual inputs1406672, storage2933856 and outcomes
3162032 bytes unchanged each. Three fixture helpers changed among3449 prior inputs;
3446 remain identical and production code is unchanged. Semantic checks,35 tooling
tests, inventory194 families/2436 probes/270 native suites, and pinned formatting
2336 Nim files plus Rust pass. Local macOS checked-release evidence; remote CI
was not requested.
