# Charged PVM single steps

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
`stepMemory(machine, limit)` adds all 30 scalar load/store instructions to the
register/control subset; only host `ecalli` remains outside its opcode capability.
`stepOnce` adds host suspension, and `execute` provides bounded recursive exit
semantics; see [the execution contract](pvm-execution.md). The inherited specification
gates still prevent a full execution-conformance claim.
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
`Panic`, `Halt`, `Fault` or `Host` and its immutable `Machine`. Outcome `exit` is read-only;
only the private `Fault` alternative stores a physical page, exposed by a guarded
`faultPage` accessor. Only `Host` carries a nominal identifier, exposed by guarded
`hostCall`. Local errors carry no machine or tentative gas debit:
`InvalidMachine`, `UnsupportedInstruction`, `GasCycleLimitExceeded` and the inherited
`NegativeBranchTarget` and `AmbiguousAccessOrder` specification gates. Bounded
`execute` also returns local `StepLimitExceeded`. Default
results are `Uninitialized`.
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
wrapper `execute` resets panic/halt PCs to zero; see [its contract](pvm-execution.md).

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

## Memory instructions and exceptions

The pinned GP 0.8.0 instruction tables define absolute immediate stores (30–33),
absolute loads/register stores (52–62), indirect immediate stores (70–73), and
indirect register stores/loads (120–130). `stepMemory` implements all these widths
and operand roles using the existing immutable scalar memory API. Decoded register
indices remain saturated at 12. Indirect operands are read before any destination
write, including aliased loads. Address operands are reduced modulo 2^32 before
addition, so the intermediate fits 33 bits without overflowing a host register;
scalar byte addressing then preserves the specified cyclic memory domain.

Loads read little-endian bytes and sign-extend only i8/i16/i32 forms. Stores write
the low requested bytes, including sign-extended immediate values for 64-bit stores.
A successful access advances PC by `1 + skip`, preserves the charged flag, and
publishes only the specified register or memory mutation. Source snapshots and
unchanged pages remain immutable; cross-page stores preflight every byte before
publishing any write.

The final-state and charged-flag equations in “Single-Step State Transition” govern
exception ordering. Insufficient gas wins before memory inspection and returns the
original snapshot. After an affordable charge, a protected-memory `Panic` or a
`Fault` retains the debit and charged flag but restores the original PC, all
registers, and memory. Unlike trap, memory panic does not increment PC. The fault
reason is the aligned physical byte address of the first inaccessible page, not
its page ordinal. Default and non-fault outcomes cannot expose a fabricated page.

An environment may replace/remap memory through `withPage`/`withMemory` and retry
the faulting instruction. The retained charged flag bypasses cost simulation and
subtraction on both repeated faults and repaired retries, including zero gas and
a zero local simulation limit. This is state repair through existing trusted APIs,
not a host allocator or standard JAM initialization implementation.

For the existing ambiguous high-page-fault/low-page-wrap case, the step returns
local `AmbiguousAccessOrder` with no machine or gas progress. It does not turn the
pinned prose/equation disagreement into a guest fault or panic. Out-of-gas still
wins before inspection. See [the memory gate](pvm-machine.md#explicit-unresolved-specification-gate)
for the exact conflicting witness and behavior when the high page is accessible.

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

The memory suite independently encodes all 30 opcodes and compares complete CPU
states and page images across permission pairs, sign patterns, ordinary/page-edge
addresses, absent pages, low protection, cyclic wrap and aliased register roles.
Every witness runs prepaid, at exact gas, and underfunded. It checks sign extension,
low-byte stores, unchanged failure prefixes, physical fault pages, repeated faults,
repaired store/load retries, saturated indices and address sums exceeding 64 bits.
The existing independent arithmetic traces and control witnesses also execute through
`stepMemory`. Compiler guards protect outcome state/page privacy and nominal limits;
isolated runtime probes reject fault-page access on every non-fault alternative and
value access on the ambiguity gate. ARC release cycles include source/fault/repair/
success graphs. Inputs are original native witnesses; no upstream implementation,
licence or binary fixture is copied into the project.

## Remaining execution work

Host suspension and bounded recursive `Psi` are implemented in the
[execution contract](pvm-execution.md). Next: standard program/memory initialization.
Host functions and complete JAM invocation remain unimplemented. The negative
branch-price and wrapping-memory specification gates remain unresolved.
These APIs do not establish full JAM parity or unrestricted PVM conformance.
