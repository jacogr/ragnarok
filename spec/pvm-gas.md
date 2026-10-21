# PVM basic-block gas calculation

## Scope and source

`src/pvm/gas.nim` implements Gray Paper **0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex` sections
“Gas Cost Model” and “Gas Cost Tables”, including `gascostforblock`, the four
pipeline transitions and all 139 opcode profiles. `spec/pins.json` retains the
complete chapter hash. It uses the existing validated immutable program decoder.

`blockGas(program, start, limit)` accepts a basic-block start and returns a nominal
`BlockGas`. It simulates through the first termination instruction, including host
calls and unlikely markers inside the block. It neither executes instructions nor
charges machine gas. Interior instructions, unmarked bytes, out-of-range addresses
and default owners return `InvalidStart`; a default result is `Uninitialized`.
Private variant fields and a success-only accessor prevent partial costs escaping.

The separate `GasCycleLimit` is a local work ceiling on simulation cycles, before
the three-cycle startup adjustment. Exhaustion returns `CycleLimitExceeded`, not
a guest out-of-gas exit. Completion at exactly the limit succeeds; subtraction is
saturated to the normative minimum charge of one. Checking before increment keeps
the cycle counter safe even with the maximum unsigned limit. Callers must distinguish
local policy failure from guest consensus behavior.

## Pipeline and ownership

The simulator has four decode slots and five starts per cycle, with resource tuple
(ALU, load, store, multiply, divide) initially (4, 4, 4, 1, 1). Decoding takes
priority over issuing the oldest eligible waiting instruction. Execution resources
remain occupied for the instruction latency and are released on its transition to
zero remaining cycles. Dependents can issue then, before the producer transitions
to executed and retires. Retirement is in order and reads the previous cycle's
states; it cannot collapse these transitions into a single cycle.

All reads/writes are syntactic, including conditional-move destination fallbacks.
Renaming captures dependencies before replacing a writer. `move_reg` consumes one
decode slot but no reorder-buffer entry: it transfers or clears producer ownership.
Variable shifts use the value-source/destination overlap predicate, not overlap with
the shift-count register. Memory profiles use the GP's fixed 25-cycle latency;
`ecalli` uses 100 cycles and no register dependencies.

A fixed 32-entry stack array and 32-bit dependency masks bound storage independently
of block length. Removing only the retired prefix is equivalent to retaining those
historical entries: their remaining latency is zero, so they impose no dependency
stall. Remaining dependency bits are shifted by the removed prefix length. There
is no shift by 32: a fully retired buffer has no entries to shift. The simulator
retains no allocations or references after returning; the program owner is borrowed
and unchanged. No native intrinsics, unchecked execution mode or per-opcode gas
substitute is used.

## PolkaVM branch-byte lookup

Branch latency is one when either the static target or fallthrough byte is `trap`
or `unlikely`, and twenty otherwise. This inspects raw bytes even at unmarked
operand positions; jump admissibility is a separate execution check. The new
`instructionByte` accessor supplies the normative infinite zero suffix, including
addresses beyond the program. Signed backward targets within the program remain
ordinary raw-byte lookups.

The Gray Paper leaves negative-index branch pricing undefined; see GP-PVM-003 in
the [discrepancy register](graypaper-discrepancies.md). The scoped compatibility
interpretation uses PolkaVM u32-wrapped targets and its absent-byte prediction-hit rule.
See [the scoped adoption](pvm-polkavm-branch-cost.md). NegativeBranchTarget is a
historical compatibility identifier, not a current blockGas result. The fixed
25-cycle memory latency matches PolkaVM Full(L2Hit); this adoption changes only
target-byte selection and does not select a different cache/cost model.

## Independent evidence

The generated `build/` gas fixture contains **1,776** blocks. A Python test-only
reference reads numeric opcode mutations and cost macros directly from the pinned
TeX, then simulates with unbounded historical entries, dependency sets and separate
next-state copies. Production code uses handwritten profiles and a compact fixed
buffer. Native replay checks every charge and the exact successful/failing cycle
limit boundary, then repeats with the maximum limit.

Coverage includes every opcode with distinct, aliased and saturated registers;
long producers before every opcode; destination overwrites; conditional fallbacks;
move chains; 31/32/33-entry pressure; long blocks; all resource bottlenecks; relocated
block starts; raw branch target bytes and the zero suffix; and 400 deterministic
mixed blocks. Public API witnesses also reject invalid/interior/default starts and
negative branch targets. Five compiler guards protect result privacy and nominal
address/limit types; four isolated runtime misuse processes check failed access.

Ten compatible register-only/termination timelines are cross-checked against pinned
PolkaVM `crates/polkavm-common/src/simulator.rs` at
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. A restricted test-only adapter reads their assembly directly from the submodule and
translates register dependencies into GP encodings; expected costs come from the original timeline
widths minus three. Immediate values do not affect these profiles. Source and MIT
license hashes are retained in `spec/polkavm-pins.json`; the original MIT licence stays
in `vendor/polkavm/LICENSE-MIT`. No upstream code, licence or generated binary is
copied into project sources. No upstream source is executed. PolkaVM L1-load timelines are deliberately
excluded because their four-cycle load latency differs from the pinned GP model.
These are compatible cost witnesses, not complete cross-VM execution vectors or
saved fuzz crashes.

The binary format is `PVMGAS01`, a four-byte little-endian row count, then records of
start (4 bytes), expected charge (8), exact simulation cycles (8), blob length (4)
and that many blob bytes. Python checks deterministic regeneration; fixture preparation verifies the source pins
and writes under ignored `build/`. The native harness checks the prepared SHA-256
before replay. Standalone native launches require this freshly prepared manifest.

## Remaining work

The [single-step executor](pvm-step.md) now composes charging with immutable
successor snapshots, unchanged out-of-gas state and single-step terminal outcomes.
Memory faults preserve the paid block charge for repair/retry. The bounded
[executor](pvm-execution.md) now handles host suspension and recursive exit rules;
standard initialization and host functions remain separate work. Branch pricing follows the approved PolkaVM adoption; this is not a complete
PVM or JAM invocation implementation.
