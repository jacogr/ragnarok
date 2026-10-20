# Full-width clipped guest fetches and returned lengths

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, host fetch
selector15, natural copy intervals, NONE and full returned lengths; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author two original guests before computation/signing. Both request3 bytes into
an invalid maximum uint64 destination. WideOffset uses offset2^32/index0: a
present record clips to an empty interval, tolerates any destination and returns
its full canonical length. WideIndex uses offset0/index2^32: absence tolerates
any destination and returns full uint64 NONE. The low32 bits of2^32 are zero;
incorrect narrowing would try to copy the first record to an invalid destination.

Immediately after fetch, a real store_u64 instruction writes all eight r7 bytes
atRW+3. The original RW21/22/23 prefix must stay intact. Persist all eleven bytes
through the storage host, real terminal selection, complete state composition and
atomic publication. Independent oracle is the literal RW prefix plus LE64 of the
actual canonical operand size, or eight0xff bytes for NONE. No result, guest
memory or completed report is patched.

Only these new fixture modes receive original balance58 before roots/signing:
base10+item2+footprint(35+11)=58. Only their original/successor local final-value
capture budget becomes11; old budgets and protocol parameters stay unchanged.
Selector15 request3 costs357, eleven-byte write2449 and one block at most997,
so assert actual gas>2806and<=3803. Original credit10000 and successor20000 remain.

Completion: exact original/successor full words, unchanged prefix, actual
Halt/Regular, metadata footprint46/item1/balance58, full parameter and parent
identity, canonical history/statistics/state/view, real copy/effect limits,
1000 full two-mode execution/composition/publication ARC cycles. Recheck affected
older storage/outcome/operand/list suites, source-owned inventory/tooling and
formatting. Production APIs remain unchanged.

Next: consume a clipped nonempty tail using the returned record length.
M1 framing complete; full serialization, whole-block parity and full chainspec
equivalence remain open.

Observed local evidence: both genuinely authored original/successor guests Halt/
Regular with preserved RW21/22/23 bytes. WideOffset persists the full canonical
record length in eight LE bytes; WideIndex persists all eight0xff bytes of NONE.
Both use natural2^32 with zero low32 bits and invalid destinationMAX64, so a
narrowed index/offset would attempt a nonempty invalid copy instead of succeeding.
Real store_u64, eleven-byte write and exact deposit58 succeed without changing
protocol parameters or old fixture funding/capture behavior.

Copy ceiling11 succeeds and10 refuses with RunnerFailure/DispatchFailure/
LimitExceeded at the actual storage capture. Final-value ceiling10 preserves
CompletionFailure/BatchFailure/LimitExceeded. Every refusal leaves the original
canonical state/view untouched. Exact full words survive composition/publication
with footprint46/item1/balance58, timestamp3, history3, activity reports2/
refinement0/actualgas, all29 parameters and finality1. Gas is greater than2806
and no more than3803 under the unchanged execution limits.

One thousand two-mode full execution/composition/publication cycles retain
938352/938352 occupied bytes. All four affected older suites pass again at1000
cycles: storage2933856/2933856, outcomes3162032/3162032, individual inputs
1406672/1406672 and list framing1459632/1459632. Three original fixture helpers
changed among3446 predecessor inputs;3443 remain identical. Production code is
unchanged. Semantic checks,35 tooling tests, inventory194 families/2436 probes/
269 native suites, and pinned formatting2335 Nim files plus Rust pass. Local
macOS checked-release evidence; remote CI was not requested.
