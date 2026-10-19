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

## Implemented contract

`recordAccumulationProvision` consumes one retained effects pair, a nominal target service, stable
borrowed bytes and independent local limits. It preflights the uint32 length domain and bounded
hash/scan work, distinguishes absent target accounts, then computes the blob hash and calls shared
`preimageRequested`. That query derives its own service/request key and reuses extrinsic admission's
exact account and complete request-history validation. Unknown targets and unrequested/nonempty
histories remain protocol refusals; corrupt metadata/history and backend failures are local reasons.

Duplicate equality compares the complete target/raw-byte pair. A duplicate needs no additional
record capacity and remains recognizable at an exact full-set budget. Retained-prefix budgets are
also checked when a caller supplies a tighter later policy. New record extent and aggregate
addition are proved before allocation/copying. Allocation exhaustion retains the project's fail-stop
policy. The invalid-length branch proves narrowing for actual buffers larger than uint32; native
unit tests do not allocate a multi-gigabyte blob merely to reach that branch.

`AccumulationProvision` privately retains its exact immutable byte owner and target.
`effectProvisionAt` checks its full-width nominal ordinal; `provisionInfo` copies fixed facts and
`copyProvisionBytes` returns independent storage. Contexts share an immutable provision-set owner:
yield/checkpoint retain membership without copying payloads, while an accepted provide constructs
a new bounded membership list sharing only immutable older payload owners. No node links back to
an earlier pair or set. Yield and incoming account credit survive provide; checkpoint snapshots
retain their original set after later regular additions.

The native suite covers source and extraction mutation, detached child lifetime, zero-byte blobs,
targets zero and uint32-max, exact/short count and byte caps, complete history alternatives,
wrong length, orphan requests, malformed target accounts, both hash failure points and a 96-step
fixed-membership model interleaving provide/yield/checkpoint. Request/byte/target primitives retain
their existing independent corpus coverage. Three new compiler probes protect private provision
ownership and nominal ordinal/target arguments; ten strict runtime probes cover defaults, actual
protocol/local refusals, invalid ordinals, byte extraction and canonical query results.

## Verification evidence

Local verification with pinned Nimony 0.6.3 on macOS passed `make check-inventory`,
`make format-check`, `make check-modules`, `make check-unit`, `make check-failures`,
`make check-guards` and `make check-python`. Observed results: 102 source modules, 115 native
suites, 41 independent corpora, 1,394 data-driven runtime misuse probes across 75 failure families,
891 compiler rejections, and 406 Python tests with three existing skips. The new suite's 1,000-cycle
ARC probe held occupied allocation at 31,408 bytes before and after. The existing effect/checkpoint
and published preimage-transition suites passed in the same aggregate run. Focused new runtime
probes also required the exact selected-success contract diagnostic, not merely a nonzero exit.

Reports are generated under `build/tests/`; the command transcript is
`build/accumulation-provisions/verification.log`. Linux CI verifies the published PR head separately.
No E2E networking behavior changed; that independent group was not rerun locally for this slice.

## Next bounded work

[Provide host dispatch](pvm-accumulation-provide.md) now captures these effects from
actual guest buffers with gas and memory ordering. Terminal normalization selects
the retained provision set; a readable 32-byte halt return with nonempty provisions
keeps the documented specification gate. Fulfilling selected requests and publishing
preimages/state after accumulation remain separate work.
