# Empty-operand allowances and unavailable-code transfer recipients

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, initial-only
always-accumulate gas, accseq transfer continuation, Psi_A post-credit missing-code
branch, exceptional checkpoint selection, sparse N/T/G statistics and timestamps.

Twelve complete histories compare132 signed transitions. Sender99 receives an
explicit prior100000-unit allowance but initially has no program payload. Empty
zero-gas skips produce no accumulation statistics/timestamp, even when the same
block supplies its code. Once code is available, literal halt/checkpoint-selected
transfers debit99 and credit42, whose own code arrives one block later. Accepted
credits survive recipient code absence with T1/G0; new report operands remain
separate from the later transfer round. Panic discards outgoing transfers while
retaining actual source gas. The final fresh report proves actual later execution
rather than retroactive replay of a skipped report or transfer.

Completion requires checked macOS/Linux complete signed-block/state comparisons,
independent sparse-statistics/timestamp/balance/rollback/order invariants, affected
original references and inventory. Expectations derive before native execution;
production defaults and old frozen cases remain fixed. Finite qualification and
M1 framing do not establish arbitrary-history or full JAM/client parity; mixed
histories and replay/operator qualification remain further bounded work.

Observed verification: all132 transitions/12 chains match on checked
macOS and Linux (ARC/Clang release, bounds/assertions retained, established non-LTO
corpus profile,180-second runtime limit). Linux image `sha256:1bf03405d43b22668d684b2865e7e2d80e5cdb4846281a6ef077fb033ed217cd`
freezes8,326 source/native inputs and matches the Mac request/expected hashes.
5 independent reference tests and inventory pass. Nim/Rust sources match the passing4,805-file Nim/Rust formatting baseline.
