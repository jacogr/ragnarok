# Typed local host failures

This increment extends the bounded host execution API with enum-valued callback refusals.
The protocol source remains Gray Paper 0.8.0, `text/pvm.tex`, Host Call Definition (`Psi_H*`),
at gitlink `07f041dabd073f9018b418e9ee72e79dd2185401`. Local resource refusals are execution
policy outside that protocol state machine; they must not be mapped to guest Panic or OutOfGas.
The guest continuation, terminal-PC and gas rules are unchanged.

A fallible handler returns `HostResult[Reason]`, where Reason is a caller-owned enum.
`hostSuccess[Reason](response)` selects posterior protocol state; `hostFailure(reason)` selects
only the exact local reason. No enum ordinal or name is treated specially, even zero or None.
A default result is unselected and becomes the engine's InvalidHostResponse error.
An explicitly selected response still passes through `applyHostResponse` validation.

The fallible `executeWithHost` overload returns `HostExecutionResult[Reason]`. Its alternatives
are completed guest execution, an existing StepError, or the caller's original reason. Status
and payloads are private, and accessors enforce the selected alternative. Neither local failure
publishes a machine, gas balance or partial progress. Default results expose no payload.
The response-only overload retains its original StepResult API.

Both callback forms use the same `nextHost` helper, which advances the guest instruction budget
and reserves dispatch credit before entering a callback. Limits never reset after continuation.
A refusal returns immediately, without applying a response or executing the guest successor.
Terminal host responses may finish on the last permitted instruction. Guest terminal/fault results
bypass the callback. Instruction and dispatch exhaustion remain distinct engine failures.

Callbacks remain synchronous, non-null, non-raising and non-closure. The loop retains neither
callback nor context. Enum reasons carry no owners; response memory and guest snapshots retain
acyclic immutable owners. Context mutations already made by callbacks survive every later error,
including an explicit refusal. Callers requiring atomic external effects must stage context.
Dispatch limits bound call count, not internal handler CPU, allocation or I/O.

The native suite integrates fetchTraceResponse: a copy-budget refusal propagates as the exact
FetchError.LimitExceeded, while permission Panic and gas underflow remain completed protocol
outcomes. It checks refusal after earlier writes, callback order, all enum reasons, default and
malformed replies, shared exact/short budgets, terminal PCs, untouched input roots, and guest
fault metadata. Isolated guard probes cover wrong-alternative/default extraction; compiler probes
cover private storage. Fresh 1,000-cycle ARC evidence covers completion and both immediate and
later callback refusals. The existing host execution/fetch/gas/response suites provide regression
coverage. This is independent implementation evidence, not full host-function parity.

[Optional entropy/trace capture](pvm-fetch-context.md) now supplies the context boundary and
resolves fetch absence using pinned notation. Remaining: complete invocation context selection,
additional selectors, staged service state, gas-used accounting and end-to-end invocation policy.
[Package blob capture](pvm-fetch-package.md) now provides validated package selectors.
Encoded refinement context and summaries are covered by [selectors 10–12](pvm-fetch-summaries.md).
Next bounded chunk: full encoded package fetch.
