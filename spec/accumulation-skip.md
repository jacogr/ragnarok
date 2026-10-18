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

Standard PVM initialization exists in the separately open [#83](https://github.com/jacogr/ragnarok/pull/83). Machine-entry integration follows
that dependency; this slice avoids duplicating or merging another native stack's implementation.

## Completion tests

Replay independent code-envelope witnesses through resolution and then assert skip versus execution
selection, exact zero/empty effects and unchanged whole-state root/entries. Cover missing preimages,
valid empty code, exact/over protocol limits and local refusal; preserve all account fields and
unrelated service values. A genuinely signed block must retain the exact source service/round.
Check ownership after source replacement, absence of hashing during outcome construction, default
and failed result contracts, private/nominal compiler guards and repeated ARC release.

## Implementation and failure contract

`src/state/accumulation_skip.nim` exposes `finishUninvokedAccumulation` for a successful
`PreparedAccumulationService`, and `finishBlockUninvokedAccumulation` for its genuine bound
counterpart. An exhaustive code-status selection completes only Missing, Malformed and Oversized.
Ready returns the typed `ExecutionRequired` refusal, including a valid empty program blob and code
exactly at its protocol size limit. Default service handles return `InvalidService`; no API accepts
a failed preparation result or a caller-supplied code-status flag as a substitute certificate.

The private immutable outcome retains the original service, input group and complete source map.
`skipInfo` copies the service/slot/code status and zero gas/transfer/provision counts with absent
yield. The initial-only type cannot hold nonempty effects. `skipState` retains the exact snapshot,
not a filtered account mapping or a recomputed partial root; `skipService` retains the resolved
source. The bound owner additionally retains its original `BlockAccumulationService` and exposes
a pure projection without accepting replacement state, code or profile buffers.

This alternative requires no bootstrap or `I`, posterior entropy lookup, service-ID probe, program
validation, host call, hashing or state publication. Account balances, storage, timestamps,
privilege roles and all other chapters remain unchanged. Complete source identity is preserved rather than newly
validating unrelated account/chapter payloads. Incoming transfers remain explicitly unsupported by
service preparation and independently refused by this adapter; unchanged state is correct for the
transfer-free initial round. Future transfer-aware execution must retain actual credited state,
not discard credit by reusing an unmodified parent.

Code-size eligibility inherits the explicit `ServiceCodeLimit` chain parameter used by service
preparation. The block certificate authenticates state/slot provenance, not that caller-supplied
chain constant; this outcome layer neither changes nor reinterprets the limit.

Source resolution still owns namespace/content hashing, canonical envelope interpretation,
preimage identity and resource preflight. A backend/resource/corruption refusal there cannot be
relabelled as an unavailable-code protocol outcome. Skipping performs constant additional work and
retains existing immutable owners; it introduces no untrusted-size allocation or arithmetic.

## Verification evidence

`tests/unit/state/test_accumulation_skip.nim` reuses all 408 independently authored service-envelope
witnesses with the same hash-pinned corpus and signed-report template. It distinguishes preparation
refusals, execution-required cases and complete non-executing outcomes, comparing the complete source
root, account bytes and zero/empty effects. No new Python protocol implementation or corpus fork is
introduced; the existing fixture provider supplies identical transport to both consumers.

Native literal cases cover missing preimages, malformed envelopes, valid empty code, exact/over
code-size limits, and zero/maximum offered gas. All account fields and unrelated service/opaque
entries survive, and mutations of copied metadata/bytes cannot change the result. Four genuinely
signed block cases cover all three skip reasons and Ready, with actual slot/operand provenance,
retained source/round, and unchanged state after publishing a separate replacement map.
A refused-hash provider proves outcome construction needs no hashing. Four privacy and one nominal
compiler probes protect owners/results and bound/pure API separation; eight strict runtime probes
protect default/refused extraction. A 1,000-cycle ARC loop covers every skip reason, execution
required and invalid-service refusal.

These are authored first-alternative `Psi_A` witnesses, not complete accumulation STF execution.
Authority pins, dependency sources and ready-code behavior remain unchanged.

Local affected verification passed:
`make check-inventory format-check check-modules check-unit check-failures check-guards check-python`.
The run passed 97 source modules, 110 native suites and all corpora/runtime/compiler checks, plus
404 Python tests with three existing skips. The new ARC loop retained 93,280 occupied bytes before
and after all 1,000 cycles. Reproducible reports are under
`build/tests/{modules,runtime,failures,guards}/results.json`; the complete local log is
`build/accumulation-skip/verification.log`. Linux CI checks the pushed head separately. E2E behavior
is unchanged, and that group was not rerun locally for this isolated state slice.

## Next bounded work

Integrate standard accumulation machine entry once the PVM initializer lands. Actual execution,
checkpoint/host effects, transfer credit, later rounds and atomic publication remain separate.
