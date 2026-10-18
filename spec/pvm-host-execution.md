# Bounded host-aware PVM execution

## Source and scope

`executeWithHost` implements the iterative host-dispatch composition of GP 0.8.0
Appendix A, **Host Call Definition**, `Psi_H*`, from
`vendor/graypaper/text/pvm.tex` at commit
`07f041dabd073f9018b418e9ee72e79dd2185401`. It accepts an already captured machine,
caller-owned context and a synchronous, non-raising handler. Like the underlying
`execute`, it preserves the supplied charged flag; initialization of a fresh invocation
remains the caller's responsibility. This is the nonnegative-gas execution subset,
not complete JAM invocation or signed gas parity.

## Dispatch and budgets

The handler receives the normalized Host suspension and mutable context, and returns
an explicit `HostResponse`. Guest terminal/fault outcomes return unchanged without
calling it. A continuation is applied through `applyHostResponse` and starts another
guest segment. Host terminal outcomes return immediately with posterior state at the
causing PC; they are not normalized again as guest halts or panics.

One `ExecutionStepLimit` covers the entire invocation, including host instructions.
The internal guest loop consumes this shared remaining budget before each attempt.
It is never replenished by a callback. `HostCallLimit` independently bounds dispatch;
exhaustion returns `HostCallLimitExceeded` before invoking the next handler.
`GasCycleLimit` remains a per-block simulation limit. These local policies neither
charge nor replace guest gas. A host terminal response can complete on the last
allowed guest attempt; a continuation needs another attempt to execute its successor.
Zero instruction budget invokes no handler. A zero dispatch budget permits programs
that never request a host call. All budgets use nominal domains.

## Context, errors and ownership

The handler is non-null by the compiler's procedure type contract, has no closure
capture and cannot raise. Context is borrowed exclusively through `var` during each
synchronous callback; neither context nor callback is retained by the engine.
The caller must keep callback work itself bounded and avoid external effects when
transactional invocation is required. The limits count dispatches, not callback CPU
time, allocation, nested invocations or I/O.

Context changes and external effects already performed by callbacks remain visible
if a later instruction/dispatch limit or malformed response causes a local error.
The engine cannot roll back arbitrary caller-owned state. Callers needing atomic
application must stage their own context and commit only after successful execution.
Failed `StepResult` values still expose no machine or partial execution payload.
Invalid machine roots, gas-simulation limits and existing semantic gates propagate.

The loop retains one current immutable machine root and bounded transient results;
it does not recurse or retain execution history. Program and memory ownership remain
acyclic. Callback implementations own any context-specific resource lifetimes.

## Evidence and next boundary

Native tests cover exact and one-short instruction budgets across multiple calls,
independent dispatch exhaustion, callback ordering/register propagation, all host
terminal actions, invalid responses, invalid owners, guest panic/fault/out-of-gas
without dispatch, immutable source preservation and 1,000 complete ARC lifetimes.
The CI evidence validator checks the fresh numeric ARC observation. Isolated probes
reject failed-result extraction after instruction, dispatch and response errors;
a compiler probe rejects raw integers as host-call limits.

Standard initialization, execution with trusted host dispatch and output capture now
compose. Concrete JAM host functions, staged service context, signed gas accounting
and complete invocation policy remain open; the existing execution specification
gates remain unchanged. The next bounded chunk is a concrete host-context operation
with independent normative witnesses, rather than additional generic dispatch layers.
