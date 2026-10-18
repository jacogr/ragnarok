# Accumulation preimage provision effects

## Scope and authority

Implement the state portion of Gray Paper 0.8.0 `pvm_invocations.tex`, `Omega_Aries` / provide
(call 27), and implication checkpointing at revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`.

Extend the immutable effects from [checkpoint/yield](accumulation-effects.md) with provisions
`(service, raw bytes)`. Accept only an existing valid target account and the exact canonical
outstanding request `(Blake2b(bytes), length)`. Reject duplicate target/raw-byte pairs. Retain the
validated bytes independently of caller storage, and let checkpoints retain the current provision
set along with yield. Preserve incoming credit and all original account/chapter/input provenance.
A successful provision changes only regular implications; it does not fulfill the request or write
the preimage immediately.

The caller supplies an explicit nominal target service and stable borrowed bytes. Guest r7's self
sentinel/range handling, gas charging, guest-memory validation and panic remain PVM responsibilities.
Protocol refusals map to WHO (unknown service) or HUH (not requested/already provided/invalid length);
local budgets, malformed state and cryptographic failures remain distinct typed local refusals.
No failure exposes a changed effects owner. No speculative restriction on request lengths beyond
the pinned uint32 domain is added; the maintainer's request-namespace question remains parked.

Independent item/per-blob/aggregate-byte ceilings bound retained data and copy work. Extraction must
be owner-bound, ordinal-checked and return independent byte copies. The existing canonical request
validator is shared with extrinsic admission rather than duplicated. Final provision union,
post-accumulation integration, guest dispatch and terminal normalization are outside this slice.

## Completion tests

Native tests will cover self/other/unknown targets, absent/nonempty/malformed request histories,
empty and nonempty blobs, duplicate versus distinct targets, caller/extraction mutation isolation,
exact/short count and byte budgets, hash/backend refusal, source retention, checkpoint divergence
and mixed yield/provision histories. Verify no account/root/request writes or repeated incoming
credit, strict default/refused/index result guards, private owner storage, nominal ordinal domains
and 1,000-cycle ARC release. Direct equation witnesses do not claim full host or accumulation STF.

## Next bounded work

Connect the retained state effects to accumulation host dispatch as its dependencies land, then
normalize actual terminal outcomes and integrate selected provision sets after accumulation.
