# PolkaVM wrapped branch-target pricing

The Gray Paper remains primary; GP-PVM-003 in the
[discrepancy register](graypaper-discrepancies.md) records the missing negative-index
gas definition and the scoped PolkaVM-compatible fixture interpretation.
Pins remain PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`,
GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`.
Program read_args_offset wraps instruction_offset plus signed offset to u32;
Simulator::get_branch_cost inspects that raw target byte and treats an absent
byte as a cheap prediction hit. Therefore negative mathematical targets must
receive the corresponding wrapped target price, not NegativeBranchTarget.

Scope: use bounded u64 arithmetic to form the exact low32-bit target before
existing raw-byte lookup. The existing deterministic25-cycle memory profile
matches PolkaVM Full(L2Hit); no cache-latency or gas-model selection changes.
Keep the local simulation cycle ceiling and immutable program ownership.
Historical NegativeBranchTarget reason names remain compatible but are not
emitted by current blockGas. Jump-target admissibility stays a separate actual
execution check; out-of-program wrapped destinations cause guest panic.

Completion: independent Python and native rows cover all16 conditional branch
opcodes at-1,-128 andINT32_MIN with noncheap fallthrough bytes, plus exact
4/3-cycle and1-gas boundaries. Preserve every pre-existing independent fixture
record byte-for-byte, append new cases and freeze the new fixture hash. Remove
the former pending negative-charge test. Recursive execution must now reach the
actual invalid-target panic after successful register/store prefixes while source
aliases stay unchanged. Existing wrapped memory faults remain covered separately.
Run affected gas/control/execution and full computed-storage consumers, Python
reference/pin/harness checks, inventory and pinned formatting. Record exact
source hashes; no upstream code or dependency pins change. M1 framing complete;
full state serialization, whole-block parity and chainspec equivalence remain open.

Strict runtime result probes track the resolved behavior: the former negative
branch inputs now serve as successful same-binary positive controls. Gas refusal
uses a valid program with an unmarked operand start; step refusal uses a four-cycle
whole-block limit that prevents the first register mutation. Preserve exact
result-value contract diagnostics for every declared negative case. Include the
updated memory-step failure family and its fault-page positive control.

Independent prefix control: load_imm into r0 followed by the dependent register
branch has a two-gas/five-cycle price. The four-cycle scan refusal precedes its
first actual register mutation. Charged execution stores literal7 over sentinel99;
trusted prepaid execution performs the same mutation at zero gas. These are
separate from the one-branch one-gas/four-cycle corpus witnesses.

Observed local evidence: all1776 independent/native gas rows pass; all1728 prior
record bytes are preserved. Gas cycles4/3 and dependency-prefix cycles5/4 have
exact successful/refused boundaries. Stepping, recursive execution, genuine
wrapping-checkpoint publication and computed-storage consumers pass1000 ARC
cycles each, retaining166208,28688,753888 and2933856 bytes respectively.
All15 strict runtime refusal probes and three same-binary positive controls pass.
The gas reference passes6 tests with no pending negative-target skip; source-pin
specification tests pass3 with the existing unrelated Bandersnatch skip, failure
harness7 tests and inventory pass. Pinned formatting passes2581 Nim sources and
the Rust crate. Local checked-release macOS/ARC/Clang LTO evidence; remote Linux
CI and the full PolkaVM Rust test suite are not claimed. A separate targeted
public-API JamV1/L2Hit Rust probe confirms block cost1 for the register-branch
witness recorded in GP-PVM-003; it changes no upstream source or production dependency. Exact records/logs remain under
`build/polkavm-branch-cost-*`.
