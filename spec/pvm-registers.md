# PVM register-only instruction mutations

## Scope and normative source

This increment implements the register mutations for all 85 register-only opcodes:
20, 51, 100–110, 131–161 and 190–230. Source of truth is Gray Paper **0.8.0**,
commit `07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex`, Instruction
Tables, signed conversion/extension definitions, and the definitions of `smod`
and rounding toward zero. `spec/pins.json` retains the complete chapter hash.

`evaluateRegisters(program, pc, registers)` decodes a validated program instruction
and returns a copied thirteen-register array with precisely its designated register
changed. Default owners, unmarked addresses and out-of-range PCs fail as
`InvalidInstruction`. Valid instructions outside this scope return
`UnsupportedInstruction`; this local result must never be translated into a guest
trap merely because the interpreter has not implemented that opcode yet.

This is the register-mutation part of an instruction, not `Psi_1` or `Psi`.
It neither advances the PC nor reads/changes memory, gas or the block-charged flag.
GP 0.8.0 requires charging the **whole basic block** using its pipeline simulation
before any mutation may be committed. The [charged executor](pvm-step.md) performs those checks
and orders exceptional effects before using this result. It reuses an existing
[private validated instruction result](pvm-validated-register-evaluation.md)
through the second evaluator overload. No flat per-opcode gas
substitute, unchecked execution mode or fabricated VM exit is introduced.

## Arithmetic and ownership

All operands, including conditional-move fallbacks, come from the original register
array, so any destination/source alias is valid. The result has private status and
payload fields and a success-only accessor. Failures/defaults contain no register
array. Input and output arrays are copied values, with no new owner allocation or
back-reference; the program retains its existing immutable ARC ownership.

Arithmetic uses unsigned 64-bit bit patterns. Add/subtract/low multiply intentionally
wrap; 32-bit operations first select the low word and sign-extend their result,
including unsigned word division/remainder. Comparisons bias the sign bit instead
of narrowing to a signed host type. Shifts reduce counts modulo 32/64; arithmetic
right shifts explicitly fill sign bits. Rotations avoid a host shift by 64. Zero
inputs to bit-count operations return their specified full-width zero counts.

Signed division/remainder use unsigned magnitudes. This covers division by zero,
MIN_INT / -1 and negative dividends without executing overflowing host signed
division or using Python-style floor division/remainder semantics. The signed
remainder follows the dividend's sign. Word overflow results are sign-extended.

High-half multiplication uses four 32-bit limbs. A limb product is at most
`(2^32-1)^2`; adding the low-product carry to the first cross product and adding
the low cross-product limb to the second cross product each fit in 64 bits. The
final high word also fits. Signed high products subtract the opposite unsigned
operand for each signed-negative input, modulo 2^64. No native 128-bit extension,
foreign ABI or architecture-specific intrinsic is required.

## Independent coverage and upstream attribution

`tests/pvm_register_reference.py` is a test-only arbitrary-precision Python oracle.
It uses mathematical signed integers, full-width products, division magnitudes,
and binary-string rotation independently of the production limb/bit-pattern
implementation. It emits the checked-in `tests/fixtures/pvm-registers.bin`:

- 38,977 cases covering all 85 opcodes, Cartesian numeric boundaries, deterministic
  pseudorandom inputs, aliased sources/destinations and saturated register 12.
- 217 `TEST_RR_OP` witnesses extracted from twenty RV64 assembly tests bundled in
  PolkaVM at `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. Each original expected value
  must agree with the independent oracle before it is emitted. These cover
  arithmetic, shifts, divide/remainder and high products, including word variants.

`spec/polkavm-pins.json` hashes the complete consumed source files, the assembly
macro definitions and original license. Upstream sources remain pristine in the
pinned submodule; the original fixture extraction executes no upstream code or
build scripts. These are
compatible scalar value witnesses, **not** RISC-V instruction encodings, complete
PolkaVM programs, gas vectors or saved fuzz crash results. The `TEST_RR_OP` result
and operand order is verified against the pinned `test_macros.h`. The bundled
Regents license is retained beside the derived fixture as `pvm-registers.LICENSE`.

The fixture starts with `PVMREG01`, a four-byte little-endian record count, then
51-byte records: opcode, register descriptor, third destination byte, and six
little-endian 64-bit words (immediate, registers 0/1/2/12, expected destination).
Other registers start at `100 + index`. Python validates exact regeneration and
source hashes; the native runner checks the fixture hash before replay. The native
suite builds real program blobs, exercises operand decoding and compares every
register, including preservation of the input. Every valid out-of-scope opcode
and invalid/default address is checked separately. Four compiler guards protect
payload/status/accessor privacy and the nominal PC; three isolated misuse processes
must fail at the exact success-access contract.

A later [public interpreter cross-check](pvm-register-reference-crosscheck.md)
executes all38977 unchanged independent rows across85 register opcodes against
pinned PolkaVM JamV1 and compares every register plus the trap PC. It preserves
these independent expectations and their source-only extraction; Rust is optional
test tooling, with no production integration or full-VM conformance claim.

## Remaining execution work

Register-value agreement does not establish complete execution conformance.
[Charged stepping](pvm-step.md) and [recursive execution](pvm-execution.md) now
compose gas, control flow and scalar memory; [initialization](pvm-initialization.md)
and the scoped host/JAM adapters have their own contracts and completion evidence.
The [discrepancy register](graypaper-discrepancies.md) records the adopted memory/
pricing exceptions and unresolved specification questions. Local execution limits
and remaining integration scope still prevent an unrestricted PVM conformance claim.
M1 framing is complete; full state serialization, whole-block parity and full
chainspec equivalence remain open.


## Scalar write evaluation, 2026-10-23

`evaluateRegisterWrite(decoded, registers)` evaluates the same 85 operations into a
`RegisterWriteResult`. On success, `destination` returns a nominal register index
below thirteen and `writeValue` returns its copied 64-bit pattern. Both accessors
require success. Default, invalid and unsupported alternatives expose only their
`RegisterError`; callers cannot retag the result or construct its private fields.
Operands and conditional fallbacks still read the original register array before
any caller applies the write. Neither the input array nor any machine is mutated.

The executor applies this one scalar write to its private CPU cursor after gas and
capability checks. The existing `evaluateRegisters` overloads retain their complete
copied-array API, materializing that array only after successful scalar evaluation.
There is one arithmetic implementation for both forms; no alternate opcode table,
unchecked entry point or gas behavior is introduced.

The independent frozen arithmetic corpus checks the scalar destination/value and
both array entry points for every witness across all 85 operations. It also checks
input/result independence, default/invalid results and unsupported instructions.
Dependent register chains, charged-step snapshots and cached execution retain their
existing complete-state checks. Six runtime accessor failure probes and their actual
positive control verify both guarded fields across default/invalid/unsupported
origins; three compiler probes reject private payload/status access. These tests do
not change the existing complete-JAM parity gates or the scoped M1 framing status.


## Bounded word-level bit counts, 2026-10-23

All six 32/64-bit population/leading/trailing-count instructions now use bounded
unsigned word operations. The private helper requires width 32/64 and one of its
three count modes; every evaluator call supplies literals. The 32-bit path masks
the upper half before any count. Population count sums disjoint two/four/eight-bit
lanes and collects their total with intentional modulo-2^64 multiplication.
All shift counts are fixed below 64 and the final total is at most 64.

Both zero-count modes explicitly return the selected width for a zero low word.
Trailing count isolates the lowest set bit by modular negation and counts the
positions below it. Leading count spreads the highest one through lower positions,
then subtracts its population from the selected width. The filled word has at most
that many bits, so the subtraction cannot underflow. No zero-undefined intrinsic,
architecture-specific extension, unchecked shift, disabled contract or mutable owner
is introduced. Arithmetic result/error/alias semantics remain unchanged.

The independent arithmetic corpus remains the primary control across all 85 opcodes.
An additional 2304 literal one-hot/one-clear witnesses check every bit position,
both widths and alias/nonalias destinations through scalar and array APIs, comparing
all thirteen output registers. Upper-half-only words explicitly select 32-bit zero
behavior. Dependent-register, mixed-program and cached/nested execution consumers
remain controls, along with the pinned mixed-bit performance guest. Timing and
remaining interpreter gaps are recorded in the benchmark contract.


## Applying bounded scalar writes, 2026-10-23

Arithmetic evaluation now reads the genuine result's bounded A/B/D coordinates,
including the same original destination value and alias behavior. The private scalar
write index is constrained to0–12. Existing `destination` still returns the nominal
`RegisterIndex`, and all compatibility array/program/PC APIs retain their status and
copied-input contracts.

`applyRegisterWrite(registers, written)` applies exactly one successful write to a
caller-owned `var RegisterFile`. Success selection is a precondition; default,
invalid-instruction and unsupported results cannot authorize mutation. The helper
uses the private bounded index directly, allowing the compiler to eliminate a
redundant array guard without disabling bounds or assertions. Compatibility array
evaluation applies it only to its independent copied array; the executor applies
it only to its private CPU cursor.

Every independent arithmetic fixture now checks direct application against the
existing complete-array result, including untouched source registers. Retained
owner-release/operand-copy controls compare captured coordinates as well. Three
new application-failure controls join the existing payload-access family and its
genuine positive control. Independent dependent-register chains, both destination
profiles and memory/control/host/retry composition remain required.

The unchanged frozen scalar/chain oracles now qualify complete invocation policies and both
callback forms; see [register policy reference](pvm-register-policy-reference.md).


## Shared typed arithmetic expansion, 2026-10-24

The internal `src/pvm/internal/register_ops.nim` module owns the existing opcode
set and arithmetic helpers. Its typed `computeRegisterWrite` template computes a
bounded destination and copied value without constructing a tagged public result.
Both outputs are committed only after success; default/invalid/unsupported inputs
leave them unchanged. All source operands and conditional fallbacks are read before
either output is published. No program representation, mutable owner, unchecked
access or arithmetic rule changes.

Charged execution expands this computation at its private register dispatch and
applies exactly one write after the existing capability and whole-block gas checks.
The public `registerOnlyOpcode`, `evaluateRegisterWrite`, `applyRegisterWrite` and
both `evaluateRegisters` signatures and guarded result contracts remain unchanged.
Their wrapper shares the same arithmetic implementation. Helpers remain private
to the internal module; the module retains no execution state.

The independent frozen corpus now also checks the internal scalar outputs for all
38,977 witnesses across 85 opcodes. Sentinel controls check atomic refusal for
default instructions, invalid PCs and every valid out-of-scope opcode. Existing
register chains, charged-step, cache/ARC, mixed-program and host-reentry suites
remain the affected consumers. Snapshot census instrumentation and benchmark/
analyzer source identities recursively include internal Nim modules; a temporary
source-tree control verifies nested bytes and both original/generated hashes.

[CI40105931933](https://github.com/jacogr/ragnarok/actions/runs/40105931933)
qualifies runtime `194021ac` against control-inlining parent `d9c78943` on an
AMD EPYC7763 runner. It passes2808 paired state-checked invocations,2808
identical-source controls, assertion controls and the pinned interpreted pack.
Pinky CPU changes are -6.4% dynamic, -5.4% planned and -6.7% memo. Both process
orders agree: dynamic -6.35/-6.71%, planned -6.08/-4.77%, memo -6.82/-6.61%.
Long planned indirect calls improve9.8%, and planned sieve100000 improves5.1%.

Tradeoffs remain: dynamic synthetic crossing hosts regress3.9% overall
(+3.76/+3.69% per order, against -1.38/+0.91% same-source variation). Tiny memo
arithmetic1 regresses8.1%, about40ns. Other small changes overlap noise; all21
real and33 synthetic cells, both orders and cold data remain in
`build/pvm12/ci-40105931933/`. Generated dispatch C grows while removing the
arithmetic calls, so this is a measured workload tradeoff, not a code-size win.
Publication only adds documentation to the qualified runtime; native restacking
verifies complete runtime/tool tree equality. Ragnarök still trails PolkaVM on
these inputs. M1 framing completion and full-JAM parity gates remain unchanged.
