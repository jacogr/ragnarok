# Complete common-input accumulation batches

## Scope and authority

Extend the common-source batch merger with complete prepared-input coverage: exactly one actual
execution or certified non-executing outcome for every service. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f` (`accone`, `accpar`,
`fnprovide`) and pvm_invocations.tex SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb` (`accinvocation`).
Pins, encoding interpretations and the parked request-domain question do not change.

Only `SkippedAccumulation` certified by the existing service code gate can supply the zero-gas,
empty-effects alternative. Require exact shared input/prior owners and the candidate slot for
skips too. Incoming transfer credit survives code unavailability and must merge with executed
services before terminal provision fulfillment, under the same atomic publication and stale-plan
rules. Coverage counts and descriptor arithmetic are checked before allocation; uniqueness and
provenance are checked before union hashing. Preserve the existing explicit-subset constructor.

This is complete coverage of the supplied input owner, not an admitted round or block certificate.
Aggregate/service-indexed gas accounting, mutable account effects, transfers emitted by guests,
privilege updates and later rounds remain subsequent work. The selected-account mutation gate and
halt-return/provisions ambiguity gate remain unchanged. M1 framing is complete; full serialization
and accumulation/block parity are not claimed.

## Completion tests

Use genuine mixed execution/skip and all-skipped sources, including missing, malformed and oversized
code. Verify independent literal balances, provision histories and complete-map roots. Check empty
inputs, omission, duplicates, defaults, foreign equal-content input/prior owners, wrong slots,
exact/short account ceilings, stale publication and both private-phase failures. Confirm skips do
not become terminal sources, caller order does not affect roots, no-credit all-skip work does not
hash, and retained plans release across 1,000 ARC cycles. Run the new suite and affected existing
batch/skip suites, source-owned guards, inventory/provenance and formatting checks.

## API and ownership

`prepareCompleteAccumulationBatch` returns the existing immutable `PreparedAccumulationBatch`.
It first requires the number of executions plus skips to equal the retained input service count,
using subtraction before addition. Each genuine source retains a service index in that exact
input owner; exact shared prior ownership and cross-array uniqueness therefore prove coverage
without a second membership table. Skipped slots are checked directly; executed slots retain the
terminal adapter's existing guarded failure reason. Invalid/default skips, count mismatches and
skip-slot mismatches expose only `InvalidSkip`, `IncompleteCoverage` and `InvalidSlot` respectively.
No caller-supplied service IDs, code statuses, gas observations or effect buffers certify a skip.

Descriptors are bounded by the prepared input owner and checked byte extents. Changed metadata
from both arrays consumes the existing account-write ceiling. Only genuine executions enter
terminal normalization/union preparation and the optional PVM account-effects gate. Both kinds of
credit enter the same private account-write phase; existing provision fulfillment and publication
then operate unchanged. All-skip/no-credit and empty-input plans preserve the exact prior without
hashing; an all-skip credited plan still gets normal stale-plan protection after publication.

`batchInfo` additionally reports `skipped` and `completeInputs`. The latter is also true for an
explicit executed subset that happens to cover every prepared service. `batchOutcomeAt` continues
to index only the execution array, in caller order. Skips cannot impersonate terminal sources.
Copied observations expose no mutable owner, metadata buffer or replacement publication source.

The next bounded state layer is actual service-indexed gas accounting and round binding, followed
by later-round scheduling. PVM read/write/info work remains in its own stack; selected mutable
account effects still require a subsequent bounded merger.

## Local verification

Passed `make unit SUITE=accumulation_complete_batch`, `accumulation_batch` and `accumulation_skip`.
All include checked optimized ARC execution. The new 1,000-cycle workload retained 542,096 occupied
bytes before/after; the existing consumers retained 1,027,632 and 93,440 bytes respectively.
Independent expected full maps cover mixed and all-skipped credits, all three code-gate reasons,
provision fulfillment into a skipped service, input permutations, empty inputs, unchanged no-credit
maps, detached source lifetimes and stale publication. Injected hash failures verify refusal before
credit publication and after the entire mixed credit phase, preserving exact prior identity.

Fifteen strict runtime extraction guards and seven privacy/nominal compiler rejections passed.
The new nominal fixture uses a typed execution array so its refusal specifically identifies the
service-as-skip argument. Python discovery passed 441 tests
with six skips; source inventory/provenance, pinned formatting and diff checks passed.

An isolated combined-tree check at PVM write PR #153 head
`f9c79ab1179dc4475d17b10808b68638c1e3bd20` passed both the original batch and new complete-input
suites, exercising the actual account-effects API. Selected storage writes remain refused; rolled-back
regular writes remain accepted. No PVM branch or harness implementation changed. Logs, source overlays
and diagnostic results are retained under `build/accumulation-complete-batch/` and the corresponding
`build/accumulation-complete-*.log` files. These are local macOS results; exact-head Linux CI is separate.
