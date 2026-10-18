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
before any mutation may be committed. A future executor must perform those checks
and order exceptional effects before using this result. No flat per-opcode gas
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
pinned submodule; none of their code or build scripts is executed. These are
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

## Remaining execution work

Next bounded increment: the pinned basic-block gas cost model, with independent
pipeline/dependency witnesses. Only then compose instruction stepping, control flow
and memory operations with exact exceptional-state ordering. The wrapping memory
ambiguity in `pvm-machine.md` remains an explicit gate. Standard initialization,
host calls and complete JAM invocation remain unimplemented.
