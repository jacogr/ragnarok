# Accumulation invocation bootstrap

## Authorized bounded scope

Implement GP 0.8.0 `pvm_invocations.tex`, `accinvocation`/initializer `I` and
`newserviceindex`, at revision `07f041dabd073f9018b418e9ee72e79dd2185401` (source SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`). Build on
[service-code contexts](accumulation-service.md) with immutable invocation arguments and the
initial collision-checked service identifier. Full mutable implications/checkpoint contexts,
PVM execution and state publication remain separate. [Service preparation](accumulation-credit.md)
now retains incoming credit before this bootstrap; arguments count transfers plus operands.

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

## Implementation and failure contract

`src/state/accumulation/invocation.nim` exposes compact argument construction, deterministic initial
ID derivation, bounded public-ID probing and immutable pure/block-bound bootstrap handles. The
pure adapter accepts a ready `PreparedAccumulationService` and explicit posterior entropy. The
block adapter retrieves C(6) from that service's genuine completed block stage, requires its exact
128-byte extent and selects entropy word zero. Parent entropy and history words are not substitutes.
The original service context already binds the account, code, candidate slot and input sequence.

Argument construction takes nominal `AccumulationArgumentCount` and allocates at most 19 octets,
independent of the represented count. The hash seed needs at most 42 bytes. Compact slot/service
widths are at most five bytes each; entropy is 32 raw bytes. Seed derivation uses no domain token,
outer count, fixed-width integer substitution or terminator.

The public-ID interval is `[65536, 4294967040)`. Each occupied metadata key advances by one modulo
that interval. Low Registrar-only indices and the final 256 indices are refused as probe starts.
The local `ServiceProbeLimit` includes the final absence check. Exhaustion returns a typed refusal,
not a reserved ID or a successful partial search. A full cycle bounds even an enormous supplied
ceiling, and all candidate arithmetic fits uint64 before narrowing. Lookup membership counts a
present account key without decoding it; orphan storage/preimage keys do not establish an account.
This operation does not reserve the ID or prevent a future cross-service allocation collision.

Missing/default owners, unavailable code, malformed/missing posterior entropy, backend failure and
local lookup exhaustion expose reasons alone. Private acyclic owners retain the exact service and
its immutable map/input provenance; argument extraction returns independent copies and entropy is
copied by value. No PVM machine, host-call dispatcher, mutable implications or execution outcome is
created. In particular, this bootstrap is not presented as a complete validated partial-state or
regular/exceptional context. Their initial typed state bindings remain the next slice.

## Verification evidence

The native suite replays 384 deterministic independent reference cases covering compact scalar
boundaries, arbitrary entropy, full-width input counts, occupied prefixes and exact/one-below probe
limits. Python uses `hashlib.blake2b(digest_size=32)`, unbounded arithmetic and the independent
compact encoder. Tests compare complete argument bytes, seed-derived IDs and probe verdicts.
Literal witnesses distinguish compact encoding from accidental E4 padding.

Native cases cover public-interval wraparound, reserved starts, default state, orphan preimages,
provider refusal, unavailable code, mutation of extracted arguments/entropy and retained child
operands. A genuinely signed block has different parent/posterior entropy and proves that the
bound path selects the latter with the actual candidate slot. A 1,000-cycle success/exhaustion loop
requires unchanged live ARC occupancy. Compiler and strict runtime probes protect nominal domains,
private ownership and success-only extraction.

These are independently authored bootstrap witnesses, not published full accumulation STF outputs.
Pinned Gray Paper/vector revisions and native dependencies are unchanged.

## Next bounded work

Bind the complete initial partial-state components for regular and exceptional accumulation contexts
(accounts, authorization queue, validator staging and privilege roles), retaining this bootstrap.
Checkpoint mutation, actual PVM dispatch, later rounds and atomic publication remain
separate work requiring genuine execution outcomes.
