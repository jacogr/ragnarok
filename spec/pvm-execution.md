# Host suspension and bounded PVM execution

Source of truth is Gray Paper **0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm.tex`: “Basic Definition”
(the recursive `Psi` and `deblob` equations), “Single-Step State Transition”
(gas, final-state and charged-flag equations), and the `ecalli` row in
“Instructions with Arguments of One Immediate”. Its source hash remains in
`spec/pins.json`; no upstream pins change.

## APIs and scope

`stepOnce(machine, gasLimit)` implements the single-step opcode capability for
all valid instructions, including `ecalli`. The narrower `stepRegisters`,
`stepControl` and `stepMemory` entry points preserve their existing capability
boundaries. All return guarded `StepResult` values; branch-target pricing and wrapping
memory follow the maintainer-approved pinned PolkaVM behavior.

`execute(machine, stepLimit, gasLimit)` evaluates the recursive `Psi` exit rules
using a loop over immutable snapshots. Its input program is already validated
and owned by the machine. Raw blob parsing, standard initialization, host-function
implementation and complete JAM invocation are outside this API. A default machine
is local `InvalidMachine`, not a fabricated guest panic for an absent program.
A valid owned program paired with an invalid PC through trusted terminal-state
capture follows the `deblob` failure branch: guest panic, PC zero, unchanged gas,
charged flag, registers and memory. The single-step APIs keep returning local
`InvalidMachine` for that non-executable input.

`ExecutionStepLimit` is a nominal unsigned local instruction-attempt budget,
separate from guest gas and `GasCycleLimit`. Owner validation precedes the budget;
a zero budget attempts no instruction and returns local `StepLimitExceeded`.
Every attempted instruction, including an exit or invalid-entry check, consumes
one attempt. An exit on the last permitted attempt succeeds; needing another
attempt fails locally. Counter increment follows a strict less-than check so even
UINT64_MAX cannot overflow. Each gas simulation has its own `GasCycleLimit`, and
existing containing-block scans remain bounded by the captured program size.
This is a deterministic work bound, not a wall-clock deadline.

Limit exhaustion and other local errors carry no machine, host identifier, gas
debit or completed-prefix progress. Previously created private snapshots are
released; the caller's original snapshot is unchanged. These failures are not
out-of-gas, guest exits or resumable scheduler yields. A future yielding API would
need an explicit successful progress contract rather than attaching state to a
failure alternative.

## Host-call semantics

Opcode 10 selects `Host` with the decoded immediate's full register-width bit
pattern as nominal `HostCallId`. The immediate uses at most four sign-extended
bytes; zero-width and negative compact encodings are valid. Extra skipped bytes
do not alter the identifier. No host function or external side effect executes.
`hostCall(outcome)` requires `Host`; the private variant stores no host metadata
on any other exit. `faultPage` likewise rejects a host outcome. `exit` stays
read-only, so callers cannot retag an outcome into either metadata alternative.

Gas affordability is checked before host suspension. An uncharged call pays for
its entire containing block, including instructions after the call. Insufficient
gas returns the original out-of-gas snapshot. A prepaid call needs no gas lookup,
even with zero gas or a zero gas-simulation limit. Host calls are not basic-block
terminators and preserve the charged flag.

The `ecalli` instruction row only overrides the exit reason: `Psi_1` retains its
default `1 + skip` PC increment. Thus `stepOnce` returns the following instruction
PC, while `execute` applies the outer `Psi` rule and returns the PC of the host
instruction that caused suspension. Execution does not automatically skip a host
call on retry. The trusted environment must perform its host transition and advance
PC before resuming; otherwise the same call suspends again without another charge.
The host identifier alone does not establish that a particular host function exists.

## Recursive exit rules and ownership

For `Continued`, execution retains the completed successor and loops. For final
`Panic` or `Halt`, it sets PC to zero and preserves posterior gas, charged flag,
registers and memory. This retains load-and-jump register writes even when that
instruction panics or halts; trap's single-step PC increment is normalized only
at this boundary.

For `Fault`, `OutOfGas` and `Host`, execution returns the causing instruction's
prior PC, registers and memory with posterior gas and charged flag, retaining the
selected fault-page or host-call metadata. “Prior” means the state immediately
before the exiting instruction, including completed earlier instructions—not
the invocation's initial state. Memory repair/retry therefore retains the paid
block charge and all earlier successful mutations.

The loop retains only its current machine root plus bounded per-step temporaries;
it does not recurse on the host stack or retain an execution history. Program
and unchanged memory pages remain shared immutable children. Normalization creates
one owned machine root. Returning a local error releases temporary progress without
mutating source aliases or external state.

## Verification and remaining scope

Original native witnesses cover compact host identifiers, maximum skip, charged/
prepaid/underfunded calls, exact step budgets, invalid entry, terminal normalization,
load-and-jump writes, long decrement loops, out-of-gas after a completed block,
local gates after a successful store, per-block gas-simulation exhaustion, repeated
fault/host suspension and environment-driven resumption. They compare complete CPU
state and retained memory, including an independently known loop instruction count.

Existing independent arithmetic traces and control witnesses run through `stepOnce`;
the memory permission/boundary matrix also runs through `execute` to the exit.
Compiler guards enforce host metadata privacy and distinct local limit domains.
Isolated runtime probes reject host metadata on all non-host outcomes, fault metadata
on Host, and value access on local failures. ARC evidence covers complete execution,
fault, repair, host and terminal snapshot lifetimes. No upstream code, licences or
binary fixtures are copied.

Opcode execution is implemented within the existing explicit specification gates.
This is not complete JAM invocation or a claim of unrestricted PVM conformance.
Standard program/memory initialization is implemented by the separate
[initialization adapter](pvm-initialization.md), and trusted posterior host state can be
applied through [host-response application](pvm-host-response.md); host functions and JAM-specific
invocation wrappers remain separate work.

A private [block-price memo](pvm-interpreter-block-cache.md) reuses only
successful immutable program/cycle-limit calculations within one execution call. [Host invocation reuse](pvm-host-price-reuse.md) binds that
memo across continuations because host replies retain the program and cycle limit. Gas
affordability/debit, local failure behavior and all exported snapshot contracts remain
unchanged; direct single-step calls and independent execution invocations start fresh.
