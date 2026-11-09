# PVM host response application

## Scope and normative source

[`applyHostResponse`](../src/pvm/step.nim) implements the posterior-state transition
in GP Appendix A, **Host Call Definition**, `Psi_H*`. The original release source is
`vendor/graypaper/text/pvm.tex` at commit `07f041dabd073f9018b418e9ee72e79dd2185401`.
The [current pin](pins.json) adopts unsigned gas. The current
[host gas contract](pvm-host-gas.md) records the reserved-zero deficit and excluded
host Halt action, and retains the historical release decisions.

## Transition and ownership contract

The [response adapter](../src/pvm/step.nim) validates the causing suspension,
applies the supplied posterior fields and publishes an immutable result. It checks
structural consistency for a trusted caller. The bounded invocation loop and host
dispatch have their own [execution record](pvm-host-execution.md).

## Completion evidence and remaining work

Original release witnesses cover all then-supported actions, every posterior register, replaced
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
