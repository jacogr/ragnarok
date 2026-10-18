# Charged register and control-flow PVM steps

## Scope and normative ordering

`stepRegisters(machine, limit)` composes program decoding, whole-block gas pricing
and all 85 register-only mutations into immutable successor snapshots. Source of
truth is Gray Paper **0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex`, “Basic Blocks and
Termination Instructions”, “Single-Step State Transition” and the instruction
mutation tables. The chapter hash remains in `spec/pins.json`.

`stepControl(machine, limit)` extends this to all block terminators and `unlikely`:
static/dynamic jumps, both load-and-jump forms, all conditional branches, trap and
dynamic halt. Both entry points implement subsets of `Psi_1`, not the recursive
`Psi` executor. `stepRegisters` preserves its existing capability boundary.
Each API first validates its owner and supported opcode. Instructions outside its
capability boundary (host calls and memory accesses for `stepControl`) return a
local `UnsupportedInstruction` with no outcome, even when guest gas is zero.
Capability checks are outside the claimed guest transition domain; they must not
be translated into a guest panic or out-of-gas exit.

For a supported instruction, an uncharged snapshot pays for its **whole containing
block**, even when execution starts at an interior instruction. Pricing includes
skipped prefix instructions and the block's terminator, using the existing gas
simulator. When gas is insufficient, the completed evaluation reports `OutOfGas`
and returns the original snapshot: PC, gas, charged flag, every register and memory
remain unchanged. No register mutation is evaluated before affordability is known.

For `stepRegisters`, an affordable step subtracts the cost, sets the charged flag, evaluates the
register mutation against the original register array, and advances PC by
`1 + skip(pc)`. All supported instructions are nonterminating, so the charged flag
stays true and the validated program guarantees a following instruction. With a
true input charged flag, cost lookup and subtraction are skipped entirely, even
with zero remaining gas and a zero local simulation limit.

## API and ownership

`StepResult` has private status/payload fields and a success-only `value` accessor.
Successful evaluation carries a copied `StepOutcome` with `Continued`, `OutOfGas`,
`Panic` or `Halt`
and its immutable `Machine`. Local errors carry no machine or tentative gas debit:
`InvalidMachine`, `UnsupportedInstruction`, `GasCycleLimitExceeded` and the inherited
`NegativeBranchTarget` specification gate. Default results are `Uninitialized`.
Guest out-of-gas is a completed evaluation, not one of those local errors.

The program is extracted from the source snapshot via `programOf`; callers cannot
supply a substitute program for the same machine state. Program and memory owners
are shared immutably; registers and scalar state are copied. A charged or prepaid completed step
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

## Control-flow semantics

The same pinned chapter defines `sjump`, `branch`, `djump`, the final charged-flag
equation, and instruction-table mutations (opcodes 0–2, 40, 50, 80–90, 170–175,
180). `stepControl` applies them only after whole-block affordability is established:

- Static destinations must be marked basic-block starts. Signed relative offsets
  are resolved mathematically; a negative target never wraps into the address space.
- Conditional branches validate **both** the taken target and the fallthrough,
  regardless of the condition. Unsigned comparisons use register bit patterns;
  signed comparisons use two's-complement order. A valid untaken branch advances
  by its decoded skip, and a missing final fallthrough panics.
- Dynamic addresses are the specified register-plus-immediate sum modulo 2^32.
  The halt sentinel `0xffff0000` takes precedence over jump-table validation.
  Otherwise, zero, odd, out-of-table and non-block destinations panic. Table index
  calculation uses division to avoid overflowing a length-times-alignment check.
- Load-and-jump reads original operands before writing the destination register,
  including when source and destination alias. The instruction table's register
  write also applies when its jump panics or halts; no memory-access fault overrides
  that mutation in these instructions.
- A successful terminator clears `blockCharged`, even for a self-loop or untaken
  branch. The next step must pay for its destination block. Panic/halt retains the
  successfully charged flag and gas debit. `unlikely` is a nonterminating no-op.

`Psi_1` terminal PCs are deliberately not normalized to zero. Invalid jumps and
sentinel halt retain the current PC as specified by the jump helpers. Trap only
overrides the exit reason in its instruction row, so it retains the default PC
increment, potentially beyond the end of code. The separate recursive `Psi`
wrapper resets panic/halt PCs to zero; it is not implemented here.

`captureTerminalMachine` is a trusted snapshot boundary that validates program and
memory ownership but permits a non-executable PC. It exists to represent these
terminal states without weakening `captureMachine`'s executable-entry validation.
The exit reason remains in `StepOutcome`; the machine itself is not a tagged
executor lifecycle. Callers must inspect the exit before scheduling another step.
Passing a terminal snapshot with an invalid PC to either step API returns local
`InvalidMachine`, not a claimed recursive-`Psi` result. Read-only snapshot access
remains available, and no mutable owner storage escapes.

The inherited negative conditional-target **gas** gate remains: uncharged execution
returns local `NegativeBranchTarget`, because the pinned price definition does not
define negative byte indices. A trusted prepaid snapshot bypasses pricing and the
instruction itself correctly panics on the invalid destination. Static unconditional
negative targets have no such pricing dependency and panic after normal charging.

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

The native suite also supplies directly encoded control-flow witnesses independent
of the production decoder's encoding logic. Literal signed-order ranks and unsigned
boundary values cover every conditional opcode, equality and both outcomes. Tests
exercise invalid untaken targets, missing fallthroughs, interior and operand targets,
negative-target pricing gates, dynamic alignment/table bounds, address wrap,
saturated operands, aliased and separate load-and-jump registers, panic/halt writes,
trap PC advancement, terminal-owner checks, and repeated self-loop charging.
Each witness with defined pricing is checked prepaid, charged and underfunded;
all CPU fields, original snapshots and retained memory are compared. Existing
independent arithmetic traces also run through the broader entry point, and ARC
release cycles now include terminal snapshots.

## Remaining execution work

Next bounded increment: memory instructions and their fault/panic ordering.
Host calls, recursive `Psi`, standard initialization and complete JAM invocation
remain unimplemented. The
negative branch-price and wrapping-memory specification gates remain unresolved.
This bounded subset is not a complete runnable PVM or a claim of full JAM parity.
