# Account last-accumulation timestamps

## Scope and authority

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex immediately after `accumulationstatisticsdef`: transform only
accounts present in the actual post-accumulation map, setting last-accumulation
to the authenticated child slot iff their service is a key in the nonzero
statistics mapping. Missing/deleted accounts remain absent. Preserve all other
metadata fields, service entries and unrelated complete-map chapters.

Provide a pure bounded projection from a stable complete snapshot, canonical
numeric sorted unique service identities and an explicit AccountSlot. It returns
independent caller-owned write descriptors and copied observations, not an
execution or block certificate. Bound service traversal/native descriptors and
aggregate existing metadata bytes before copying. Require exact canonical
version-zero metadata; skip missing records and avoid already-current writes.
Default state, duplicate/unsorted identities, malformed selected records and
short policies refuse without partial output. Unselected metadata is untouched.

The opaque prepared owner accepts only genuine PreparedAccumulationStatistics.
Derive its complete finalized state and authenticated slot through the retained
original admission graph, never a caller-supplied map, timestamp or projection.
Apply the derived writes on a private fork under inherited store ceilings;
retain the exact statistics source, complete successor and copied observations.
Failures retain only selected reasons. Zero writes preserve state identity and
perform no hashing. This phase does not write C(13), merge C(15), or publish a
caller store; later coordination must combine those independently bound phases.

Completion witnesses cover genuine report/transfer/allowance and skipped-code
activity, zero-tuple omission, literal metadata octets and independently authored
full-map roots, missing/already-current records, untouched fields/chapters,
malformed/trailing/version records, exact/short/full-width limits, backend
rollback, source/copy/detached ownership, default/refusal/privacy/nominal guards
and 1,000 ARC cycles. Preserve dependency pins and existing statistics semantics.
M1 framing remains complete; full state serialization/block parity remain open.

## Local verification (2026-10-19)

Passed the selected native accumulation_statistics and accumulation_reentry_cycle
suites using the pinned compiler, checked ARC/Clang LTO and prepared native
crypto/Bandersnatch dependencies. Fresh suite ARC evidence retained equal occupied
memory before/after 1,000 cycles: 1,136,624 and 920,480 bytes respectively. Every
new genuine timestamp witness additionally performs 1,000 preparation/private-map
update cycles with no retained growth.

Signed report, allowance-only, skipped-code, empty-activity, transfer-only and
zero-gas recipient histories update exactly the authored service identities to
child slot 2. Literal E4 octets replace only offsets 81..84; independently patched
full-map roots match, including preserved C(16), account balances, other metadata
and unrelated entries. Empty activity retains the exact prior state owner and
performs no hashing. A detached account owner retains its original statistics
graph after all caller statistics/finalization handles are released.

Pure projection cases cover missing identities without recreation, already-current
records, ignored unselected malformed metadata, default maps, duplicate/unsorted
identities, empty/truncated/trailing/unsupported-version records, exact/short/zero
metadata and service ceilings, full-width policies and the maximum AccountSlot.
Projection bytes are caller-owned and cannot mutate the source. Already-current
projections produce no writes; applying that empty list preserves identity with
hashing disabled. Backend refusals at zero and two successful hash calls expose
only StateFailure and leave all retained source state unchanged.

Seven strict runtime result/nested-reason guards, three private-owner/result
compiler rejections, and two nominal rejections passed. Neither a pure projection
nor a finalization alone can substitute for PreparedAccumulationStatistics. The
new production module passed semantic compilation. Nine inventory tooling tests,
source-owned inventory, pinned changed-source formatting, local feature links and
whitespace checks passed. One initial semantic check corrected the nested metadata
failure constructor to select its literal variant tag, preserving the pinned
compiler's guarded-result requirements. No PVM runtime, codec, vendor source, gitlink
or dependency pin changed. Logs/results remain under ignored
`build/pvm-accumulation-timestamps*`; these are local macOS checks, distinct from
exact-head Linux CI.

[Service activity coordination](pvm-service-activity.md) now combines refinement,
provision and accumulation metrics from one original block. Core/validator activity
and final C(13) assembly remain subsequent work, before combining the independently
bound account/history/statistics phases for block publication. M1 framing remains complete; full state serialization and
whole-block parity remain open.
