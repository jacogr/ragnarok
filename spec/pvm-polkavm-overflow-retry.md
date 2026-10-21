# PolkaVM overflow-fault repair preserves paid execution state

Pins and authority: [the memory-order adoption](pvm-polkavm-memory-order.md),
PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`, GP0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401`. DynamicMemory overflow
checks final-page presence on each actual retry. Supplying that page after the
first fault must therefore change the next exit to Panic; making it inaccessible
again must restore Fault at0xfffff000. No pins or production behavior change.

Scope: extend the existing raw memory-instruction suite across all30 forms.
Each program starts atMAX32 (indirect forms derive it from base2^32 plus-1).
An exact block credit produces Fault and retains zero gas/charged=true. An actual
repeated execution with zero gas-analysis allowance must fault identically.
Map the high page as ReadOnly and ReadWrite in turn; both actual retries must
panic, including store forms, retaining the same CPU and every sentinel byte.
Recursive execute must agree. Remap the page to Inaccessible, keeping its bytes,
and retry again: Fault must return without charging again or exposing bytes.

Completion compares all registers, PC, gas and charge flags, precise physical
fault pages, unchanged page permissions/contents and all retained source/fault/
present/inaccessible aliases. Preserve the existing ordinary repair-to-success
witness. Run1000 complete all-opcode transition batches in the established ARC
workload, focused semantic checking and pinned formatting. This exercises trusted
raw memory repair; full JAM checkpoint publication remains in separate suites.
M1 framing complete; full state serialization, whole-block parity and full
chainspec equivalence remain open.

Observed: the selected native suite passes1000 complete transition batches,
retaining17664/17664 occupied bytes. Each batch includes the original successful
repair and all30 opcode forms through both ReadOnly/ReadWrite trap transitions
and subsequent inaccessible-page faults. Focused semantic checking and pinned
formatting pass. Local checked-release macOS/ARC/Clang LTO evidence; no Rust
engine run or remote Linux CI is claimed.
