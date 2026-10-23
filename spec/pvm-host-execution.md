# Bounded host-aware PVM execution

## Source and scope

`executeWithHost` implements the iterative host-dispatch composition of GP 0.8.0
Appendix A, **Host Call Definition**, `Psi_H*`, from
`vendor/graypaper/text/pvm.tex` at commit
`07f041dabd073f9018b418e9ee72e79dd2185401`. It accepts an already captured machine,
caller-owned context and a synchronous, non-raising handler. Like the underlying
`execute`, it preserves the supplied charged flag; initialization of a fresh invocation
remains the caller's responsibility. Active execution requires nonnegative gas; [host gas accounting](pvm-host-gas.md)
now preserves negative terminal responses. This is not complete JAM invocation.

## Dispatch and budgets

The handler receives the normalized Host suspension and mutable context, and returns
an explicit `HostResponse`. A [fallible overload](pvm-host-failures.md) also accepts
`HostResult[Reason]` and preserves enum-valued local refusals in a guarded execution result.
Both forms share the same guest and dispatch-budget helper. Guest terminal/fault outcomes return unchanged without
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

The loop retains one invocation-owned CPU/program/memory cursor and publishes an
immutable machine for each actual callback or terminal observation. It does not
recurse or retain execution history. Program and memory ownership remain
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
compose. The gas host function and unknown-call fallback are implemented separately. Other JAM
host functions, staged service context, gas-used accounting and complete invocation policy remain open; the existing execution specification
gates remain unchanged. The next bounded chunk is a concrete host-context operation
with independent normative witnesses. [Host byte-range memory access](pvm-host-memory.md)
provides its bounded, atomic memory-copy boundary; it does not yet supply host selectors or charging.


## Private response continuation, 2026-10-23

Both host APIs initialize a private cursor from the owned source once. The shared
instruction loop uses its normal local CPU/memory values; on Host it also retains
the genuine causing state in the private cursor. Every callback still receives an
independent immutable machine, which its context may retain across later replies.
A successful Continue validates posterior state and advances that cursor directly,
without allocating an unobserved resumed-machine root between callbacks.

Public `applyHostResponse` keeps its suspension/causing-instruction/identifier
validation and returns an owned machine when requested. Its shared posterior-state
helper preserves the supported action domain, reserved-zero deficit, genuine memory
ownership and executable Continue successor requirements. Only the private loop can
seed a continuation; its program remains bound to the original invocation. Host
terminal replies retain posterior state and causing PC. Neither API exposes a new
unchecked mode, caller policy default or mutable CPU/memory backing view.

Guest attempts, dispatch allowances and callback effects follow the same shared
budgets as before. Typed refusals stop before response application. Invalid replies
remain local errors and prior context mutations persist. Nested invocations keep
independent cursors and caches. Ordinary execution retains its original loop-local
CPU form; initial attempts to share a separate by-reference loop regressed ordinary
guests and were rejected. One transition loop now selects a private validated source
only at segment entry, preserving ordinary execution and shared semantics.

New retained-root tests observe every CPU field and page byte after sequential
register/gas/memory replies. Ordinary success, a third-call typed refusal and final
instruction exhaustion preserve all earlier callback roots and original memory.
These groups join 1000-cycle ARC checks. Public response, host-failure, execution,
nested/cache, metered-host and fault/cross-page retry controls pass. A compiler guard
keeps the private response entry inaccessible; all-source Smoke compilation and
pinned formatting pass. Local results and existing M1 framing completion do not
establish full state serialization or complete STF/JAM parity. Measurement remains
in [the interpreter comparison](pvm-benchmark-comparison.md).
