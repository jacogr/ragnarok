# Accumulation invocation bootstrap

## Authorized bounded scope

Implement GP 0.8.0 `pvm_invocations.tex`, `accinvocation`/initializer `I` and
`newserviceindex`, at revision `07f041dabd073f9018b418e9ee72e79dd2185401` (source SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`). Build on
[service-code contexts](accumulation-service.md) with immutable invocation arguments and the
initial collision-checked service identifier. Full mutable implications/checkpoint contexts,
PVM execution, transfer credit and state publication remain separate.

General serialization in `serialization.tex` applies compact naturals to `E(t, s, len(inputs))`
and to the service/slot terms of `E(service, posterior_entropy, slot)`. Header-specific E4
encodings do not silently change these formulas. Use one encoding, with no fallback.

Derive the initial public identifier from the first four little-endian Blake2b-256 digest bytes,
reduce modulo `2^32 - 2^16 - 2^8`, and add `2^16`. Probe account metadata keys in cyclic public-ID
order until absent, under an explicit local lookup ceiling. Only C(255, service) membership counts
as account occupancy. Retain the exact state/input owner and distinguish local exhaustion, malformed
context and backend failure. The block adapter supplies authenticated slot and posterior entropy.

## Completion tests

Independent arbitrary-precision/Blake2b witnesses will compare complete argument bytes, seed-derived
IDs, occupied-prefix selection and wraparound. Native tests must cover exact/one-below probe ceilings,
default owners, reserved index ranges, backend failure, source lifetime and ARC release. A genuinely
signed block must demonstrate posterior rather than parent entropy binding. Compiler/runtime guards
must protect nominal positions, private result/owner storage and selected-success extraction.
