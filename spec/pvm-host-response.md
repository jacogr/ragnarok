# PVM host response application

## Scope and normative source

`applyHostResponse` in `src/pvm/step.nim` implements the posterior-state transition
in GP 0.8.0 Appendix A, **Host Call Definition**, `Psi_H*`. The source is
`vendor/graypaper/text/pvm.tex` at pinned commit
`07f041dabd073f9018b418e9ee72e79dd2185401`.

This adapter accepts a trusted host's completed response to a recursive `execute`
Host suspension. It does not dispatch a host function, execute another guest step,
manage host context, or implement the complete `Psi_H` invocation loop. The existing
`MachineGas` credit and `GasDeficit` fields now retain exact negative terminal host
results; see [host gas accounting](pvm-host-gas.md). Guest block affordability rules
are unchanged.

## Transition and ownership contract

`HostResponse` carries an explicit `HostAction`, canonical gas credit/deficit, a copied register file
and immutable memory owner. `Continue` advances the causing PC by `1 + skip` and
returns `Continued`. `Halt`, `Panic` and `OutOfGas` return the selected guest exit at
the causing ecalli PC. All four actions retain the supplied posterior gas, registers
and memory, the suspended program, and the original block-charged flag. No extra
charge is applied and no supplied gas is clamped. Host termination therefore differs
from guest halt normalization in `execute`; a host halt can feed `captureOutput`.

A default response is invalid. Non-Host inputs, a mismatched causing address or a
mismatched ecalli identifier return `InvalidHostSuspension`. Invalid input machine
roots return `InvalidMachine`; missing response memory returns `InvalidHostResponse`. These local failures expose no success payload.

Private Host metadata retains both the decoded identifier and the causing address.
This rejects `stepOnce` outcomes with their following PC even when the next opcode
is an identical ecalli. The API performs structural consistency checks, not host
authorization: the caller is trusted and the existing public machine handle can be
replaced. It does not authenticate responses or prevent reuse of a suspension.

Every successful result owns a fresh immutable machine root with acyclic shared
program/memory children. Register mutation, replacing response memory, or extracting
and mutating output cannot change a prior result. No execution history is retained.

## Completion evidence and remaining work

Original native witnesses cover all actions, every posterior register, replaced
memory, zero and maximum unsigned gas, charged continuation without recharging,
host termination with output capture, variable immediate widths and skip lengths,
adjacent identical host calls, malformed roots and independent successor ownership.
The suite records 1,000 complete lifetimes through the normal ARC evidence validator.
Compiler probes enforce nominal gas/action types and private causing-PC metadata;
isolated runtime probes enforce failed-result and exit-metadata selection.

This composes initialization, bounded execution, host-response application and output
capture. A [bounded host dispatcher](pvm-host-execution.md) composes trusted handlers
and caller-owned context. Concrete host functions, complete invocation wrappers and
gas-used accounting remain separate work. [Gas and unknown-call responses](pvm-host-gas.md)
implement exact fixed-charge terminal deficits; existing PVM specification gates remain.
