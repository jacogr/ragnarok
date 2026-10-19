# Prepared accumulation fetch context

Scope: assemble fetch context from one PreparedAccumulationMachine and explicit configured
Parameters. Normative source: Gray Paper 0.8.0, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex accinvocation's F/Omega_Y
call and Omega_Y selectors 0–15; serialization.tex Appendix C.2.

machineFetchContext derives the original bootstrap and prepared service from the machine
wrapper. It accepts no independent service ordinal, input list, entropy or base fetch context.
Entropy is present, even when all zero, and comes from the bootstrap's posterior-entropy
selection. Parameters come from the explicit immutable configuration. Accumulation inputs
are always present, including the count-prefixed empty list for allowance-only services.
Package, authorizer trace, current work item, imports and extrinsics are absent.

A private input selection unifies serviceInputAt with the earlier explicit-plan adapter.
Both paths use the same preflight, record-policy checks, aggregate count/byte budgets,
conversion and canonical capture. The service path never exposes or accepts a second group
index. Temporary copies and final encodings retain the existing bounded acyclic ownership
contract; the returned fetch context survives release of all preparation handles.

Invalid machines and uninitialized parameters produce distinct typed local errors.
Resource and encoding failures retain the existing InvocationFetchResult contract, with no
partial context. Setup validates configuration before input conversion and performs no new
hashing, account lookup, guest instruction, host mutation or state publication.

Completion tests verify exact parameters, nonzero and zero entropy, ordered operand bytes,
service isolation, empty inputs, absent refinement-only values, full-width guest indices,
limits, source lifetime, real fetch host dispatch and repeated ARC release. Existing explicit
plan tests continue to cover transfer ordering and successful/error operand conversion.

This is derived from the machine's pure bootstrap; it does not add block authentication or
resolve the existing positive gas-domain gate. Complete accumulation dispatch, mutable
implications/checkpoints and normalized outcomes remain open. Next bounded chunk: route
implemented general host calls through an accumulation dispatcher with explicit refusal for
unimplemented known calls, without fabricating state-transition outcomes.
