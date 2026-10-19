# Original-block preimage integration

Bind GP 0.8.0 `accumulation.tex` preimagesareordered/fnprovidable/fnprovide,
revision `07f041dabd073f9018b418e9ee72e79dd2185401`, to the completed recent-history
source. Preserve vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a` and the existing
preimage-transition contract, key namespaces and canonical ordering.

Accept only PublishedRecentHistory. Derive the original block's preimage component,
original admitted complete state and sealed header slot through the retained source
graph. Bound record count and complete component bytes before materializing its
owned frame; the existing admission kernel then bounds per-blob/aggregate copies
and hashes, requires strict numeric-service/raw-blob order and prior solicitation.
Retain its immutable AdmittedPreimages certificate. No caller-selected frame, prior
map or slot can replace this provenance.

Publish against the exact complete post-recent-history map. Reuse integratePreimages
on a private fork to recheck posterior requests and atomically install only the
still-relevant request/preimage values. Mutable publication requires exact snapshot
identity before any hashing and replaces the caller once only after success. Empty
or wholly disregarded input may retain the exact prior snapshot. Preserve all
coordinated account/statistics/queues/output/history entries and inherited store
limits. Prior admission counts include disregarded submissions; C(13) already
counts the original extrinsic and must not be incremented again.

Completion checks: genuine signed empty/active sources, empty blobs, multiple
services, actual accumulation-provided requests, literal values/timestamps and
independent complete-map roots; absent/malformed/duplicate/unordered prior requests;
exact/one-below capture/item/blob/total limits, hash rollback/retry, source identity,
foreign/stale callers, detached owners, repeated ARC release, guarded failures,
privacy and nominal-source rejection. Existing sixteen-vector preimage replay
remains the unchanged-kernel regression check.

This is scoped original-block preimage publication, not whole-block validity or a
partial light-state API. Next: source-bound authorization-pool coordination. M1
framing remains complete; full state serialization and block parity remain open.
Repository pins unchanged.

Observed local verification (macOS, pinned Nimony/ARC and native crypto):

- The selected `accumulation_statistics` suite passed all eight signed-source
  cases: empty, requested, already provided by real accumulation guests,
  unsolicited, duplicate, malformed, out-of-order and previously supplied.
  Exact capture/item/blob/aggregate ceilings, literal Available timestamps,
  complete-map roots/preservation, foreign/stale callers, early/later/root hash
  rollback/retry and detached publication ownership passed.
- The unchanged `preimage_transition` suite passed all sixteen pinned vectors
  and its existing posterior deletion/cancellation, malformed-state, store
  ceiling and rollback regressions. No kernel behavior or pins changed.
- The 1,000-cycle ARC observations retained 2,187,584 occupied bytes for
  `accumulation_statistics` and 10,048 for `preimage_transition`, unchanged
  before/after. The new preparation/publication release loops also passed.
- All 11 runtime extraction/reason guards, four privacy rejections and two
  nominal-source rejections passed with their intended diagnostics. The new
  module passed semantic compilation; changed Nim sources matched the pinned
  formatter. Verification inventory and all nine inventory tooling tests passed.
  These are local results; exact-head Linux CI remains separate evidence.
