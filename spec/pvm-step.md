# Charged register-only PVM steps

## Scope and normative ordering

`stepRegisters(machine, limit)` composes program decoding, whole-block gas pricing
and all 85 register-only mutations into immutable successor snapshots. Source of
truth is Gray Paper **0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex`, “Basic Blocks and
Termination Instructions”, “Single-Step State Transition” and the instruction
mutation tables. The chapter hash remains in `spec/pins.json`.

This is the register-only subset of `Psi_1`, not the recursive `Psi` executor.
The API first validates its owner and supported opcode. Unsupported instructions
(including trap, unlikely, host calls, control flow and memory accesses) return a
local `UnsupportedInstruction` with no outcome, even when guest gas is zero.
Capability checks are outside the claimed guest transition domain; they must not
be translated into a guest panic or out-of-gas exit.

For a supported instruction, an uncharged snapshot pays for its **whole containing
block**, even when execution starts at an interior instruction. Pricing includes
skipped prefix instructions and the block's terminator, using the existing gas
simulator. When gas is insufficient, the completed evaluation reports `OutOfGas`
and returns the original snapshot: PC, gas, charged flag, every register and memory
remain unchanged. No register mutation is evaluated before affordability is known.

When affordable, the step subtracts the cost, sets the charged flag, evaluates the
register mutation against the original register array, and advances PC by
`1 + skip(pc)`. All supported instructions are nonterminating, so the charged flag
stays true and the validated program guarantees a following instruction. With a
true input charged flag, cost lookup and subtraction are skipped entirely, even
with zero remaining gas and a zero local simulation limit.

## API and ownership

`StepResult` has private status/payload fields and a success-only `value` accessor.
Successful evaluation carries a copied `StepOutcome` with `Continued` or `OutOfGas`
and its immutable `Machine`. Local errors carry no machine or tentative gas debit:
`InvalidMachine`, `UnsupportedInstruction`, `GasCycleLimitExceeded` and the inherited
`NegativeBranchTarget` specification gate. Default results are `Uninitialized`.
Guest out-of-gas is a completed evaluation, not one of those local errors.

The program is extracted from the source snapshot via `programOf`; callers cannot
supply a substitute program for the same machine state. Program and memory owners
are shared immutably; registers and scalar state are copied. A continued step
allocates one new machine root without any back-reference to its source. Out-of-gas
retains the original root. Updating a later register or memory snapshot cannot alter
any retained source or earlier step.

`containingBlockStart` validates the instruction address, then scans backwards for
the closest marked terminator. Terminator-valued operand bytes are ignored. The scan
is bounded by the validated program size, independently of `GasCycleLimit`, which
bounds only pipeline simulation. No cost cache or scan optimization is introduced.
The existing program byte limit controls owner capture size.

`captureMachine` remains a trusted environment/import API, not proof that gas was
previously charged. Its supplied charged flag is followed exactly as specified;
the executor does not add a second gas policy or silently reset imported state.
This increment does not implement standard initialization or host resumption.

## Evidence

A test-only reference composes the existing independent mathematical register oracle
and literal-GP gas simulator into **186 execution traces**. They cover all 85 opcodes,
random aliasing/saturated operands, signed immediates, chains of updates, nonzero
block starts, interior uncharged entry, and an interior entry after a skipped host
call that still contributes to block cost. The native suite repeats traces with
exact gas, surplus gas and zero prepaid gas, comparing every CPU field after every
step. It also checks one-less-than-required gas, exact simulation limits, unchanged
source snapshots and retained memory bytes.

Additional native cases cover every unsupported valid opcode at both charged-flag
values; default owners/results; raw containing-block boundaries; propagation of a
later negative branch's gas gate before an earlier register write; trusted prepaid
bypass; maximum unsigned gas subtraction; copied-result isolation; and 1,000 complete
ARC release cycles. Four compiler guards protect result privacy and the nominal
work limit. Five isolated runtime probes reject value access on each local failure
alternative, including default results.

Native inputs are generated only under ignored `build/`, with pinned source checks
and prepared-file hashes. Python records a deterministic digest rather than a
checked-in binary. PolkaVM remains solely in its pinned `vendor/polkavm` submodule;
this increment adds no copied upstream code, licence or binary. Existing independent
oracles and original upstream licences remain at their established source locations.

## Remaining execution work

Next bounded increment: control flow and terminal outcomes, with exact PC and
charged-flag behavior for `Psi_1` versus `Psi`. Memory instructions, host calls,
standard initialization and complete JAM invocation remain unimplemented. The
negative branch-price and wrapping-memory specification gates remain unresolved.
This bounded subset is not a complete runnable PVM or a claim of full JAM parity.
