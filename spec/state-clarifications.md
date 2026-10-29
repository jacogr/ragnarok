# Namespace adoption and historical encoding review

## Current disposition (2026-10-25)

The unreleased upgrade already adopted #542: production admits request lengths through
2^32−3 and rejects both reserved prefixes. There is no pending namespace-policy skip or
compatible-release task. C12 E4/E8 and compact core/service C13 statistics retain the accepted
representation; proposed validator-counter changes are not part of the pinned target.
[The current serialization status](jam-serialization-status.md) supersedes the old backlog.

## Historical review of the release target

The review below records the 2026-10-17 snapshots. Its issue states and “next release”
instructions are historical observations, not current upstream status or production pins.

Pinned Gray Paper: v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`.
Pinned reference vectors: v0.8.0 `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Local implementation decisions and independently reviewed upstream evidence are distinguished below.
No issue or PR was posted as part of this review.

## Status

Reviewed **2026-10-17**, after testing/setup PR #2 merged. Production remains pinned to the
revisions above. Gray Paper main was reviewed at
[`e537514`](https://github.com/gavofyork/graypaper/commit/e5375148597a45a99d31c9aa6bce6c7bf3a48998);
vector tip at
[`39d0e35`](https://github.com/jam-conformance/jam-test-vectors/commit/39d0e35933305530fa1fe646bdedf221769398f1).
These are review snapshots, not new dependency pins.

| Item | Upstream evidence and status | Ragnarök disposition |
| --- | --- | --- |
| Request lengths overlapping storage/preimage markers | [Gray Paper #542](https://github.com/gavofyork/graypaper/pull/542), **merged**, commit [07aee1e](https://github.com/gavofyork/graypaper/commit/07aee1ef23b63f93d0e2f29e53560cbc7c8c767c), restricts request lengths to `l < 2^32 - 2` and updates the relevant host calls. | Our overlap finding is corroborated and the normative fix exists upstream. **Await a compatible pinned upgrade**, rather than further investigation of the same ambiguity. |
| C12 service/gas widths, C13 service keys and compact core/service statistics | [Gray Paper #564](https://github.com/gavofyork/graypaper/pull/564), **open**, explicitly writes C12 E4/E8 pairs and C13 E4 service keys and removes the blanket fixed-width note. [Vector issue #56](https://github.com/jam-conformance/jam-test-vectors/issues/56), **open**, discusses dictionary keys; its [maintainer reply](https://github.com/jam-conformance/jam-test-vectors/issues/56#issuecomment-2900104069) confirms compact service-statistics fields. | Supports our published-byte reconstruction and accepted compact gas policy. The proposal is not a merged normative correction. Keep one vector-compatible representation, **no fallback**. |
| Non-minimal natural encodings | [Gray Paper #551](https://github.com/gavofyork/graypaper/pull/551), **closed without merge**. The [maintainer clarification](https://github.com/gavofyork/graypaper/pull/551#issuecomment-5337499611) explains that inputs outside the encoder's range are outside the inverse decoder's domain. | Supports our existing strict rejection; no permissive decoder path or new specification gate. |
| Work-report field order | [Gray Paper #537](https://github.com/gavofyork/graypaper/pull/537), **merged**, commit [8ab3542](https://github.com/gavofyork/graypaper/commit/8ab35421ccd8d1723a6c4686e24cfb3db91bff07), aligns definitions/prose with the existing Appendix C wire order. | Corroborates following serialized bytes/Appendix C instead of the inconsistent tuple prose; no wire migration for this correction. |

**Important new-format boundary:** #564 also proposes changing current/previous validator
statistics from E4 fields to general naturals. That is distinct from confirming our existing
core/service compact fields. Preserve the pinned E4 validator records until a reviewed migration
has corresponding vectors; do not claim full #564 compatibility today.

## Next release checkpoint

The remaining request-namespace item is **resolved on upstream main, pending adoption here**.
Preserve full E4 request lengths, duplicate-key rejection, local witnesses and the skipped policy
test while targeting 0.8.0. At the next compatible release (previously anticipated as 0.8.1/0.8.2):

1. Review the release and vector revisions together, including #542 and #564's final disposition.
2. Apply the adopted request-domain bound and replace the pending policy test with active
   boundary checks: accept `2^32 - 3`, reject `2^32 - 2` and `2^32 - 1`. Reconcile the historical
   full-domain witnesses with that new target rather than deleting their evidence.
3. Check any adopted validator-statistics format change separately, with exact binary captures.

Do **not** advance both repositories merely because each has a current tip. The reviewed vector
[changelog](https://github.com/jam-conformance/jam-test-vectors/blob/39d0e35933305530fa1fe646bdedf221769398f1/CHANGELOG.md)
still distinguishes the 0.8.0 service rules from merged Gray Paper
[#539](https://github.com/gavofyork/graypaper/pull/539), while listing selected deviations for
unmerged proposals, including
[#563](https://github.com/gavofyork/graypaper/pull/563). This is not evidence of complete tip-to-tip
agreement. No codec, vector, compiler or dependency pin changes in this documentation update.

Other M1 proposals to review at that checkpoint are
[#560](https://github.com/gavofyork/graypaper/pull/560) (extrinsic-hash credential encoding), and
[issue #561](https://github.com/gavofyork/graypaper/issues/561) /
[PR #562](https://github.com/gavofyork/graypaper/pull/562) (removing the redundant assurance parent
hash). These remain **open**; proposals are not reasons to change the pinned codec prematurely.

## Request namespace versus fresh solicit

T uses `E4(length) || hash` for requests and the same prefixes at lengths 0xfffffffe/0xffffffff
for preimages/storage. The [namespace review](request-namespace.md) gives two tiny, funded local
account witnesses, with exact deposit arithmetic, consistent preimage invariants and fresh-solicit
OK predicates. Their mappings have conflicting values under identical T keys. Checked native
composition rejects both; no huge supplied blob or hash collision is needed. Full PVM execution
and genesis reachability have not been demonstrated.

**Historical question against 0.8.0:** Which normative rule excludes these combinations or disambiguates their serialization?
Should the request domain/solicit rule reserve lengths, should an additional valid-state cross-map
constraint apply, or should T's namespaces change? A statement that the blob would be too large
alone does not exclude these witnesses: only a hash is read, the requested blob is absent, and the
charged footprint/deposit fits the defined uint64 domains.

Pinned 0.8.0 behavior, pending adoption of #542: retain the full E4 domain, preserve the exact formulas, reject duplicate mapping
keys and keep the focused policy test pending. Do not choose one colliding value to overwrite.

## Accepted statistics gas policy; text discrepancy retained

T's general note describes fixed-length non-discriminator state numbers and gas has a uint64
domain. The pinned raw C13 values instead reconstruct with canonical JAM compact naturals
(1–9 bytes); E8 candidates fail complete reconstruction. For example,
`traces/fuzzy/00000025.json` pre-state's matching candidate has first-core gas 182161, occupying
three natural bytes. The [width evidence](state-widths.md) retains the exact sources and comparisons.

Maintainer decision: use the published compact encoding for core, refinement and accumulation
statistics gas. The existing decoder already implements that encoding; there is no E8 fallback.
Known compact byte checks and exact-entry rejection of a fixed-gas alternative now actively test
that policy. E4 service keys and E8 C12 gas remain fixed as shown by their respective vectors.

M1's remaining state-parity gate is adoption of the upstream request-domain fix with aligned pins. Further implementation
scope is chosen separately with the maintainer; this does not claim PVM, transitions or validator
completeness, or that the pinned 0.8.0 text has changed.

## History hash-token clarification and follow-up

During recent-history execution work, closed [#509](https://github.com/gavofyork/graypaper/issues/509)
and its [reply](https://github.com/gavofyork/graypaper/issues/509#issuecomment-3706909013) resolved
`$peak` as token notation: the bytes are ASCII `peak`, not a literal dollar-prefixed string.
The exact pinned history witness and output-tree interpretation are recorded in
[history-transition.md](history-transition.md). This is not a new dependency pin or a fallback.
Open [#549](https://github.com/gavofyork/graypaper/pull/549) proposes additional Merklization changes
and remains a future compatible-upgrade review item.

The [signing-domain audit](signing-domains.md) now resolves the two implemented Ed25519
transcripts with 1,035 external credentials: ASCII `jam_available` and `jam_guarantee` are the
only supported domains. This fixes implementation bytes, not the dependency revision or codec
format. The history module itself remains separate from signing-message construction.
