# Input-controlled exceptional state selection

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, PVM input-list
fetch, branch equality and exceptional accumulation selection; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author FetchBranchPanic before computation/signing. Fetch the actual list count
into RW memory and load r11. Real write5 stores [count,22,23] before a forward
branch_eq_imm compares r11 with2. Count1 halts and commits; assured count2 traps
and selects the initial exceptional account, retaining [1,22,23] rather than the
discarded [2,22,23]. Both branch targets are marked real instruction boundaries.
No report, memory, terminal, parameters or completed sources are patched.
Original funding50, capture3, gas10000 then20000 and runner ceilings remain.

Completion requires actual first Halt/Regular and successor Panic/Exceptional,
zero selected self writes/value bytes/account deletions, unchanged account code,
balance50, footprint38/item1. Full composition/publication retains timestamp3,
history3, activity reports2/refinement0/actual gas, all29 parameters, finality1 and
original parent/view aliases. Count fetch costs288 and write costs2447; two
completed instruction blocks each cost at most997, giving gas>2735and<=4729.

Copy ceiling2 must fail at the actual three-byte write before the planned panic;
one host call must fail before that write too. A planned guest trap must not hide
local runner refusal. Zero captured-key/final-key/final-value budgets together
must succeed for the selected original exceptional state, with no discarded
regular write leaking into its certificate. Run1000 full guest/composition/
publication ARC cycles, affected predecessor native suites, semantic checks,
source-owned inventory/tooling and pinned formatting. Production APIs unchanged.

Next: exercise storage reads following real writes in the same invocation.
M1 framing complete; full state serialization, whole-block parity and full
chainspec equivalence remain open.

Observed local evidence: actual original Halt/Regular stores[1,22,23]; actual
assured Panic/Exceptional retains that account after the guest attempts to write
[2,22,23]. Selected selfWrites/valueBytes/deletedAccounts are zero; the account
retains balance50, footprint38/item1 and its original code. Actual gas satisfies
the independent bounds. Zero captured-key/final-key/final-value budgets succeed
together; copy2 refuses DispatchFailure/LimitExceeded at the attempted write,
and calls1 refuses DispatchFailure/ExecutionFailure/HostCallLimitExceeded.
Composition/publication and all retained alias/parameter/finality checks pass.

The new suite releases1000 actual execution/composition/publication successors
with occupied memory687792/687792. All seven affected predecessor suites pass
again at1000 cycles: delete753424, tail753792, ranges938352, list1459632,
individual inputs1406672, original storage2933856 and outcomes3162032 bytes
unchanged. Only the shared guest factory changes among3455 predecessor inputs;
3454 remain identical. Affected semantic checks,35 tooling tests, inventory194
families/2436 probes/272 native suites, and formatting2338 Nim sources plus Rust
pass. Evidence is local checked-release macOS; remote CI remains separate.
