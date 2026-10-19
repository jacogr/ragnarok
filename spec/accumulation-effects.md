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

PVM machine initialization is covered separately by
[PR #130](https://github.com/jacogr/ragnarok/pull/130). This state slice
avoids duplicating that work and supplies the context mutations needed by future host dispatch.

## Completion tests

Native tests will check absent/zero/nonzero/replaced yield, checkpoint before/after yield, repeated
checkpoints, divergent old/new copies and a deterministic transition history against an independent
fixed-value model. Verify both dimensions retain the same credited source account/input/chapter
identities, avoid hashing/writes, survive source release, and release acyclic owners across 1,000
cycles. Typed default/invalid-dimension/absent-yield failures, private storage, nominal commitment
arguments and strict selected-result extraction require compiler/runtime probes.

## Implemented ownership and API contract

`src/state/accumulation_effects.nim` constructs `AccumulationEffects` only through
`prepareAccumulationEffects(PreparedAccumulationContexts)`. Both dimensions initially retain one
immutable `AccumulationEffectContext`. `recordAccumulationYield` creates a new regular version and
retains the old exceptional snapshot; `checkpointAccumulationEffects` gives the new pair the same
current regular child in both positions. Neither operation changes the caller's pair or any earlier
retained context. There are no back-references to parent pairs, so histories remain acyclic.

`effectContext` validates the dimension before extraction. `effectInfo` reports current yield
presence, copied service/next-ID facts and the current provision count (outgoing transfers remain empty). `effectYield` returns a copied
`OutputCommitment` only when present; missing yield is a typed `YieldAbsent` reason with no hash
payload. An all-zero commitment remains present. Private variant storage also omits the hash when
absent. `effectsSource` retains original preparation; `effectInitialContext` explicitly exposes
initial account/chapter/bootstrap backing, whose initial yield facts are not the current effect
version's yield. Callers read current yield through `effectInfo`/`effectYield`.

Yield/checkpoint/extraction use retained immutable owners, without hashing, state writes,
input traversal, new identifier search or additional transfer credit.
[Requested provisions](accumulation-provisions.md) now add bounded hash/validation/capture work;
yield/checkpoint share their immutable set owner. The retained
source accounts include pre-invocation credit even in the exceptional dimension. Current state
mutations support yield, checkpoint and requested provision capture. Future account/queue/transfer
operations must extend this private current-context representation before claiming those effects.

Native `test_accumulation_effects.nim` uses real public-API service/input/bootstrap/context
preparation over a complete authored map. It checks all 32 hash bytes, zero/nonzero/replaced values,
explicit/repeated checkpoints, both dimensions against a 256-step scalar model, source release,
unchanged roots/roles/credited balance/input provenance and a refused hash provider. A shared native
test helper also supplies the initialized absent-yield runtime rejection case. Six compiler probes
protect private pairs/contexts/result tags/payloads and nominal hash/dimension arguments. Ten strict
runtime probes require the selected-success diagnostic. No upstream programs, vectors or sources
are copied; these are direct implication-equation witnesses, not complete host-call or STF runs.

## Local verification

Affected verification used
`make check-inventory format-check check-modules check-unit check-failures check-guards check-python`.
All 102 source modules, 114 native suites, 41 corpora and runtime probes passed. The initial compiler
run correctly refused two privacy fixtures for an earlier constant-construction error; binding the
owners before private-field access made those fixtures require the intended privacy diagnostic.
A constant-invalid runtime fixture was also changed to dynamic result selection. Production
behavior did not change after the native unit run. Final inventory/format/compiler/Python checks
passed: all 888 compiler rejections and 406 Python tests, with three existing skips. All ten final
runtime effect probes were additionally rerun against the final fixture.

The ARC witness retained 59,808 occupied bytes before and after 1,000 cycles. Evidence is under
`build/accumulation-effects/verification.log`, `final-guards-tooling.log`, `probes/` and
`build/tests/{modules,runtime,failures,guards}/results.json`. The first log retains its guard-fixture
failure; the final tooling log records the corrected complete guard and Python verdicts. E2E
networking behavior is unchanged and was not rerun locally. Linux CI verifies the pushed head.

## Next bounded work

Checkpoint/yield host handling now uses these state effects through the
[PVM accumulation dispatcher](pvm-accumulation-dispatch.md), retaining both dimensions
with actual terminal execution results. Next, select and normalize regular/exceptional
outcomes; terminal state publication remains separate.
