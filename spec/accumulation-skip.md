# Non-executing accumulation outcomes

## Authorized bounded scope

Implement the first `Psi_A` alternative in GP 0.8.0 `pvm_invocations.tex`, equation
`accinvocation`, revision `07f041dabd073f9018b418e9ee72e79dd2185401` (SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`). Reuse the
[service code resolution](accumulation-service.md) certificate. Missing code, an invalid envelope
(which supplies no code), or code exceeding the protocol limit returns unchanged execution state,
zero gas usage, no deferred transfers/provisions and absent yield.

This initial-round slice accepts only the transfer-free contexts already certified by service
preparation. Ready code, including a valid empty blob, requires execution and cannot become a
successful skipped outcome. Missing/corrupt accounts, backend failure and local resource exhaustion
remain preparation failures, not protocol skip outcomes. Do not initialize `I`, probe service IDs,
read posterior entropy, invoke the PVM or publish state for this alternative.

Standard PVM initialization exists in the separately open #83. Machine-entry integration follows
that dependency; this slice avoids duplicating or merging another native stack's implementation.

## Completion tests

Replay independent code-envelope witnesses through resolution and then assert skip versus execution
selection, exact zero/empty effects and unchanged whole-state root/entries. Cover missing preimages,
valid empty code, exact/over protocol limits and local refusal; preserve all account fields and
unrelated service values. A genuinely signed block must retain the exact source service/round.
Check ownership after source replacement, absence of hashing during outcome construction, default
and failed result contracts, private/nominal compiler guards and repeated ARC release.

## Next bounded work

Integrate standard accumulation machine entry once the PVM initializer lands. Actual execution,
checkpoint/host effects, transfer credit, later rounds and atomic publication remain separate.
