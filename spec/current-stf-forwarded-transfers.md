# Whole-map repeated transfer re-entry

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`accumulation.tex` accseq/accone and `pvm_invocations.tex` transfer/checkpoint.

A real report invokes service 99, sending seven tokens and 10000 gas to service 42.
That recipient forwards three tokens and 1000 gas back. The third invocation
receives its credit but cannot afford the sender's next 10575-gas host call, so
it emits no further record. A zero-offer variant cannot afford even the initial
basic block, but still receives the incoming credit and records T=1 with G=0.
Panic rollback discards the recipient's forward/debit; checkpoint-panic retains
it. A zero-amount variant still produces and processes a distinct transfer.

Twenty complete signed transitions compare every original/block/successor octet
with independent Python maps. Gas uses the pinned instruction-table reference
and literal host prices. Balances, C13 N/T/G, timestamps, no-replay behavior,
processed package history and empty C16 are independently frozen before native
execution. Earlier fixtures and upstream vectors remain unchanged.
M1 framing is complete; balance-pool variants, wider lifecycle and full JAM
serialization/parity remain subsequent work.

Local checked ARC/Clang runs pass all twenty forwarded transitions, the twenty
supervisor scheduling transitions and the twenty initial transfer transitions.
Independent Python invariants, pinned formatting and source-owned inventory also
pass. No production logic or dependency pins change; Linux CI remains separate.
