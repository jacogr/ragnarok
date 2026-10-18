# Accumulation yield and checkpoint effects

## Scope and authority

Implement the state-context parts of Gray Paper 0.8.0 `pvm_invocations.tex`, revision
`07f041dabd073f9018b418e9ee72e79dd2185401` (SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`):
`implications`, `accinvocation` initializer `I`, checkpoint (`Omega_C`, call 18), and yield
(`Omega_Taurus`, call 26).

Start only from successfully prepared accumulation contexts. A validated yield commitment replaces
regular-context yield; checkpoint copies the complete currently supported regular context into the
exceptional dimension. Both begin at the same initial I. Preserve the credited account map, input
provenance, next service ID and initial queue/staging/privilege owners. Copies and old checkpoints
remain immutable; an all-zero hash is a present yield, distinct from absence.

These are state-effect operations for the host layer, not guest host-call implementations. Gas
charging, r7 changes, reading 32 guest bytes and panic on inaccessible memory remain the PVM layer's
responsibility. Accept no arbitrary replacement account map or forged initial context. No checkpoint
is applied implicitly on yield. This slice adds no execution/termination verdict, outgoing transfers,
provisions, persistent publication or full accumulation STF claim.

PVM machine initialization is already implemented separately in open PR #130. This state slice
avoids duplicating that work and supplies the context mutations needed by future host dispatch.

## Completion tests

Native tests will check absent/zero/nonzero/replaced yield, checkpoint before/after yield, repeated
checkpoints, divergent old/new copies and a deterministic transition history against an independent
fixed-value model. Verify both dimensions retain the same credited source account/input/chapter
identities, avoid hashing/writes, survive source release, and release acyclic owners across 1,000
cycles. Typed default/invalid-dimension/absent-yield failures, private storage, nominal commitment
arguments and strict selected-result extraction require compiler/runtime probes.

## Next bounded work

Connect checkpoint/yield state effects to the PVM accumulation dispatcher after its general host
path lands, then select regular/exceptional outcomes from actual terminal execution results.
