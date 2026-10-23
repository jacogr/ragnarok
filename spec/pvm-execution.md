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
using an invocation-owned CPU cursor with immutable memory handles. Observable exits retain
immutable machine snapshots. Its input program is already validated
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
debit or completed-prefix progress. The private cursor and intermediate memory owners are
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

For `Continued`, execution retains the private CPU values and immutable memory successor and loops. For final
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

The loop retains only its copied CPU state, immutable program/memory handles and bounded per-step temporaries;
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


## Private execution cursor

The evaluator separates instruction effects from observable machine capture. Single-step APIs
still capture a complete immutable successor for every successful step, and an unaffordable
single step returns the exact original root. Bounded execution keeps CPU values local and
immutable memory handles between instructions, materializing a machine only for a successful
observable exit. There is no exported mutable machine, retained caller register pointer, global
cache or mutation of shared pages. Host callbacks still receive immutable suspension snapshots;
they cannot observe an interior cursor.

Every successful nonterminal successor still passes the original executable-PC validation before
another attempt or local budget check. Program capture continues to require a final terminator;
the cursor adds no fallback or alternate invalid-entry representation. Existing gas precedence,
capability rejection, local failure without
progress, fault atomicity, terminal PC normalization and load-and-jump mutations are unchanged.
Private evaluation failures contain only their reason and never expose a cursor prefix.

The execution suite retains all four intermediate single-step roots while independent cursor
runs overwrite the same page twice, exhaust local budgets, resume from each root and suspend at
an exact host PC. Every old CPU/page stays unchanged. Repeating this witness together with the
existing fault/repair/host lifecycle for 1,000 cycles returns occupied ARC memory to its warm
baseline. The existing single-step, host response/failure, mixed-program and metered fault/host
corpora remain regression controls. A compiler privacy fixture rejects external mutable evaluator
access. Local benchmark evidence and limits are recorded in the
[performance comparison contract](pvm-benchmark-comparison.md).


## Invocation-scoped decoded instructions

Bounded execution retains sixteen scalar decoder results in eight paired sets. The natural
address-modulo-sixteen slot is checked first, preserving ordinary direct hits; toggling index bit
three selects its alternative. Complete instruction addresses tag both ways. A successful miss
fills a free natural/paired entry, or alternates replacement between two occupied residents.
Failed/default results never populate, evict or advance replacement. Hits do not reorder/copy the
other way. No input owner, callback, memory page, mutable register or partial state is retained.
The inline helper retains the same fixed sixteen-result capacity and eight bounded replacement flags.

The program and decode profile remain fixed through one `execute` or `executeWithHost` invocation.
Host continuations retain this invocation's memo; nested executions and new calls always start with
an explicitly empty independent memo. Single-step entry points still decode directly. Hits skip
operand reconstruction only: instruction-attempt accounting, gas/cycle limits, successor validation,
capability checks and every observable exit rule still execute. Space is constant, independent of
guest length or host-call count, with no new caller resource default or unbounded preprocessing.

`pvm_execution_cache` compares complete execution CPU results with uncached public single-step
traces for colliding PCs 0/16 and a repeated block exceeding memo capacity. Literal expectations
check decrements and all twenty-one additions. Nested callbacks run a different program with
incompatible operands at the outer continuation PC; both ordinary and fallible host APIs preserve
outer identity, resource refusals and callback side effects. Separate programs reuse PC 0 without
sharing operands. A thousand repeated collision/host groups return ARC memory to baseline.
The private decoder helper has a compiler rejection guard. Existing execution, mixed-program,
host-failure and metered fault references remain regression controls. Run
`make unit SUITE=pvm_execution_cache` and `make check-inventory`.


## Causing-PC exit cursor, 2026-10-23

The private iterative loop retains only the causing PC for each attempted instruction.
It no longer copies all registers and retains an extra memory handle for rollback.
This relies on the evaluator's explicit effect contract: OutOfGas returns before
mutation; failed memory preflight changes neither registers nor memory; Host changes
only PC. Those exits retain posterior gas/charged state and restore the causing PC.
Final Panic/Halt still preserve specified posterior register mutations and normalize
PC to zero. Local errors retire all private progress without exposing a snapshot.
Public single-step snapshots and their terminal-PC rules remain unchanged.

The execution suite compares complete CPU fields (including reserved-zero deficit)
and all page bytes at fault/host exits after an arithmetic/store prefix against
retained public single-step roots. Earlier roots and their pages stay unchanged.
These cases join the existing 1000-cycle ARC release group. Existing gas shortages,
load-and-jump terminal mutations, repeated faults/hosts, nested callbacks, cached
execution and dependent arithmetic-chain controls also pass. See the benchmark
record for the measured arithmetic improvement and unchanged parity limits.


## Adaptive private scalar writes, 2026-10-23

The bounded transition loop keeps its first three successful stores on the existing
immutable path. Its fourth successful store activates a private scalar writer for
that segment. Subsequent loads observe staged bytes, and subsequent stores reuse
private touched chunks. Arithmetic/load-only runs allocate no writer; short segments
such as one-store host loops retain their direct path. The threshold is an internal
implementation choice, with no new caller budget or guest-visible behavior.

Every actual host/fault/panic/halt/out-of-gas observation seals the current epoch
before publishing a machine. Host replies resume from the actual frozen callback
memory and begin an independent epoch. Local errors, including step exhaustion,
release private progress without granting a machine or resumable prefix. Public
single-step APIs keep their existing immutable store path.

The execution suite compares full CPU and page contents against retained public
single-step traces for 1/3/4/5/9-store prefixes ending in each observable exit. It
checks local budget refusal at the same boundaries. Ordinary and fallible host APIs
also cross two activation epochs around a callback that retains its snapshot and
replaces memory/registers. These cases join the existing 1000-cycle ARC group.
Measured memory gains and the arithmetic tradeoff are recorded in the interpreter
benchmark contract; this is scoped execution plumbing, not full JAM parity.


## Retained instruction validation, 2026-10-23

Cached genuine decoded results now retain their owner's sealed fallthrough fact.
Every admitted nonterminator advances sequentially, except scalar faults retaining
the already decoded causing PC. The evaluator can use that fact instead of another
program opcode lookup after each arithmetic/load/store/no-op/host instruction.
Other control successors retain the complete executable-location check, and control
mutation still validates both conditional targets before selecting one. Gas shortage,
capability refusal and local budgets retain their original ordering and payload rules.

The paired memo and validation facts form one invocation-scoped decoded-instruction
feature. Two colliding PCs and a literal three-way PC0/16/32 loop with distinct
mutations/control verify exact full-address tags and replacement under pressure.
Existing over-capacity traces, reused PCs in different programs, nested callbacks,
shared budgets and 1000 ownership cycles remain controls. Final Paper conditionals
preserve Panic for either chosen path when the other successor is absent; unpaid
execution still returns OutOfGas first. Timing evidence and remaining gaps are in
the interpreter comparison contract; no unchecked execution mode is introduced.


## Multiple priced blocks per invocation, 2026-10-23

Execution's private gas memo now retains the first successful block and three recent
successful prices, with no heap allocation or owner retention. Exact cached starts
reuse their established block membership; uncached interior PCs still resolve and
pay their whole containing block. Every cached hit checks/debits the current balance.
Only successful simulations under the invocation's fixed program/profile/cycle limit
enter the memo; failed prices never evict. New calls/limits start empty, and host
continuations retain only this invocation's memo. See the block-cache contract for
capacity, replacement, exact gas/limit/pressure tests and the benchmark evidence.
