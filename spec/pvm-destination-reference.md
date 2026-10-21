# Three-register destination-byte comparisons

## Normative scope and discrepancy

Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/pvm.tex` lines 629–640, defines three-register D as the whole second operand
byte saturated to r12. Pinned PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` masks its low nibble before saturating.
This is [GP-PVM-009](graypaper-discrepancies.md#gp-pvm-009-three-register-destination-byte-high-bits).
[Upstream PR554](https://github.com/gavofyork/graypaper/pull/554) already merged the
exact low-nibble correction on2026-08-26 as
`e5375148597a45a99d31c9aa6bce6c7bf3a48998`. The pinned paper predates that fix.
No source/toolchain pins or dependency versions change.

Minimal original code is `[190,16,16,0]`, mask `[9]`, blob prefix `[0,0,4]`.
With r0=7, r1=11 and r12=55, add32 produces 18. The paper writes r12 and retains
r0=7; PolkaVM writes r0 and retains r12=55. The initial executed public checker
failed at row0/register0 with actual18 versus paper7. Bytes `0x0c`, `0x1c` and `0xff`
are controls that select r12 in both rules; `0x10` and `0x80` select r0 only under
the low-nibble rule.

The explicit JAM owner follows the reference rule; `decodeProgram` retains the
paper rule. Each immutable program privately stores its decoding profile, so caller
input release/mutation, parent machine capture and inner-program storage cannot lose
or switch it. Original bytes, code offsets and bitmap are unchanged. Other operand
shapes retain their existing rules. This is a scoped exception, not global PolkaVM
precedence or a rewrite of raw-paper semantics.

## Consolidated matrix

| Dimension | Coverage |
| --- | --- |
| Opcodes | Every three-register opcode, 190–230 (41 forms) |
| Encoded D | All 256 byte values |
| Inputs/aliases | Three deterministic rotations of thirteen frozen register edge values; distinct and aliased A/B |
| Expected values | Independent complete GP/JAM register results through the existing mathematical opcode reference |
| Prices | Independent GP pipeline gas/cycles for both decoded register roles |
| Native boundaries | Both owner profiles, input mutation after capture, all posterior/source registers, exact/one-less cycles and underfunded gas |
| Public boundary | Original bytecode, Sync/Full/L2Hit price, causing trap PC, remaining gas and all thirteen registers |

There are 31488 rows. Destination indices differ in 22140 rows; gas/cycle pairs
differ in 1050 rows. The frozen corpus retains both columns explicitly. Register
role normalization is used only in the independent gas model's shadow operands;
actual runtime code still carries the original destination byte.

`PVMDST01` contains a u32 count and thirteen shared u64 input values, followed by
52-byte rows: opcode, A/B descriptor, original D byte, rotation index, paper/JAM
scalar results and each profile's gas/cycle pair. The descriptor pins the complete
fixture hash. Engines never generate those expected values or prices.

## Actual JAM consumers

The real initializer captures a guest that loads r1=7 and r2=11, performs the same
addition with destination byte `0x10`, then returns through r0. JAM decoding writes
r0=18 and the invalid dynamic return panics; raw paper decoding writes r12=18 and
halts successfully through the original r0 return marker. Initial source registers
remain unchanged. A public probe executes the same prefix/return guest, including
a `0xff` positive return control.

Actual inner-machine creation retains a JAM program owner whose decoded destination
is r0, independently of a raw owner for the same original bytes (r12). The original
inner map remains unchanged. These checks ensure the compatibility choice survives
production preparation boundaries, rather than existing only in a standalone decoder.

## Reproduction and evidence

```sh
make unit SUITE=pvm_destination_reference
make unit SUITE=pvm_initialization
make unit SUITE=pvm_inner_lifecycle
make check-pvm-reference
```

Current public replay passes all 31488 original-byte cases, with 22140 named
profile differences and exact independently derived prices. Native complete owner/
value/gas and actual consumer evidence is recorded after the affected checks below.
The all-state duplicate review found merged PR554 and inspected its exact patch;
the local issue entry is marked resolved upstream, so no duplicate should be posted.
Both pinned competing rules and their practical control-flow effect remain documented.
No compiled/full-suite or fuzz execution is claimed for this matrix.


## Observed native completion

The complete matrix and existing program/register/gas/step suites pass. Real standard
initialization and inner capture pass with stable1000-cycle ARC observations (2320
and148832 occupied bytes respectively). Independent fixture/runner checks pass eight
selected Python tests. Both replay consumers reject forged JAM results/prices and
an inconsistent full-width count. The complete integrated runner passes all thirteen
paired groups; formatting and inventory pass. Evidence is macOS checked release
ARC/Clang LTO and pinned Rust interpreter execution. The earlier Linux benchmark
run belongs to its exact PR8 head and is separate from this new core semantic change.
