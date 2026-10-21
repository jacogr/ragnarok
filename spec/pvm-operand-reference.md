# Complete operand-shape reference matrix

## Authority, scope and completion

Use the pinned Gray Paper `07f041dabd073f9018b418e9ee72e79dd2185401`, instruction
operand equations in `text/pvm.tex`, as primary. Compare to the public JamV1 parser
at pinned PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`; do not port its decoder.
The independent Python model reads whole code with an infinite zero suffix, rather
than truncating operands at the next instruction boundary. Preserve raw-paper and
explicit JAM destination-byte behavior documented in GP-PVM-009.

Cover all 139 paper opcodes, every skip 0–24, nine descriptor patterns and two actual
instruction addresses (0/3): 62,550 rows. Following instructions contain nonzero bytes
and the extended eight-byte form can read beyond the program into zero padding.
Widths include empty, sign-bit, saturated four-byte and fixed eight-byte reads;
register saturation, unused fields and signed displacement representations are checked.

Each frozen row includes the original full blob, both expected destination registers,
all other operands and source position. Native tests decode both owned profiles,
mutate the source input, and compare every exposed field. The reference constructs
expected public Instruction variants from frozen fields and compares the parsed
instruction, original offset and next offset. Static public enum mapping is an API
adapter only; expected operand values come from the paper model. Raw signed branch
displacements are converted explicitly to PolkaVM's wrapped absolute u32 targets.
This is decoding coverage, not new execution, gas, compiled correctness or fuzz coverage.

Completion requires frozen reproduction, field/extent tamper rejection by both
consumers, the selected native suite, public parser run, inventory, tooling checks
and pinned formatting. New discrepancies require a minimal witness and register entry;
never rewrite fixture expectations merely to hide a difference.

## Observed local verification

All 62,550 public-parser rows and both native owned-profile comparisons pass on
Apple Silicon with the pinned checked Nimony ARC/Clang LTO configuration and Rust
1.99.0. Nine selected Python/discovery checks, inventory and pinned formatting pass.
Both real consumers reject altered immediate values, the high count byte and an
overflowing record extent. All fourteen integrated public-reference/native groups pass through the Make target;
this parser-only probe is explicitly backend neutral and claims no compiled execution.
