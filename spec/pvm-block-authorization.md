# Source-bound authorization pools

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`authorization.tex` pool-update equation, `notation.tex` leftmost subtraction/newest
suffix and C(1)/C(2), with vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Reuse the existing authorization transition without changing representations.

Preparation accepts only PublishedBlockPreimages. Derive the original admission,
verified incoming guarantees, core profile and authenticated child-header slot
through its retained completed graph. Decode exact original C(1) and exact
posterior C(2) from the complete post-preimage map, bounding stored bytes before
copying and guarantee descriptors before allocation. Match the configured core
profile. Reuse advanceAuthorization to remove only the oldest matching used
hash, append posterior queue[slot mod 80], and retain the newest eight. No caller
may substitute maps, loose uses, queue snapshots or a slot. Preparation does no
hashing or state writes and retains canonical C(1) in an immutable owner.

Private publication changes only C(1) on the exact retained complete map under
inherited store limits. Mutable publication checks exact snapshot identity before
hashing and replaces the caller only after complete Merklization. Default,
foreign/stale callers, codec/policy failures and hash refusals cannot publish
partial data. Preserve C(2), preimage results, history, accounts and C(13–16).

Completion tests cover genuine signed empty/one/two-guarantee sources, duplicate
and full pools, a real privileged assign exposing the existing batch gate, literal C(1)
bytes and independent complete-map roots; exact/one-below work/capture limits,
profile mismatch, source ownership, copied observations/entries, foreign/stale
callers, hash rollback/retry, ARC release, guarded result reasons and nominal /
privacy rejection. Existing six-vector authorization replay and failure suite
remain regression checks. No pins or authorization-kernel behavior change.

This is a scoped pool publication, not full block validity or a partial light-state
API. At this layer's original revision, a genuine assign execution changed its
selected private C(2), but accumulation batch publication rejected that broader
effect as UnsupportedAccountEffects. The original gate probe required the exact
changed queue and this refusal; no completed owner or silently unchanged successor
was fabricated. This layer reads posterior C(2) from its retained complete source
and now consumes updated queues under the explicit quotas in
[selected assign publication](pvm-assign-publication.md). The signed-source tests
there exercise the changed posterior queue through C(1) publication. Broader
manager/validator mutations remain gated. Next: selected manager privilege
publication and precedence. M1 framing remains complete; full
state serialization and block parity remain open.

Observed local verification at the original layer revision (macOS, pinned
Nimony/ARC and native crypto):

- The selected `accumulation_statistics` suite passed all five signed-source
  pool cases, literal whole C(1) bytes, complete-map roots/preservation,
  exact/one-below capture/hash-count/guarantee limits, profile mismatch,
  copied-value isolation, foreign/stale caller checks and hash rollback/retry.
  The actual assign gate probe passed: its private queue has the exact expected
  slot-two bytes and complete batch publication refuses UnsupportedAccountEffects.
- `authorization_transition` replayed all six pinned vectors;
  `authorization_transition_failure` passed its policy/backend/rollback checks.
  Affected shared-fixture consumers `report_admission` and
  `accumulation_execution` passed with their unchanged default contracts.
- All 1,000-cycle ARC observations were unchanged: 2,347,904 occupied bytes for
  `accumulation_statistics`, 192 for `authorization_transition_failure`,
  292,752 for `report_admission` and 1,065,504 for `accumulation_execution`.
  The new per-source preparation/publication release loops also passed.
- All 13 runtime extraction/reason guards, four privacy rejections and two
  nominal-source rejections passed with their intended diagnostics. The new
  module passed semantic compilation, changed Nim sources matched the pinned
  formatter, and verification inventory plus all nine inventory tooling tests
  passed. Full exact-head Linux CI remains separate evidence.
