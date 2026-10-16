# Parked M1 question and accepted encoding policy

Pinned Gray Paper: v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`.
Pinned reference vectors: v0.8.0 `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
This is a local record, not an upstream ruling or a submitted issue.

## Status

The **request-namespace question remains parked** for Gray Paper 0.8.1/0.8.2 review. Preserve its
witnesses, pending test, full request-length domain and duplicate-key rejection. It is not active
implementation work.

The maintainer has **accepted vector-compatible compact encoding for C13 statistics gas**.
It is no longer a pending implementation/parity decision. The general policy is: when published
vectors encode a field compactly, use that compact representation and document any specification
text discrepancy. Use one representation, with **no alternate-format fallback**.

During the next authorized specification upgrade, check whether the request domain/solicit rules
or T key prefixes resolve the parked question, and record the result before changing behavior.
The statistics wording discrepancy can also be checked then without reopening the accepted
compact profile or blocking current work on an upstream textual correction.

## Request namespace versus fresh solicit

T uses `E4(length) || hash` for requests and the same prefixes at lengths 0xfffffffe/0xffffffff
for preimages/storage. The [namespace review](request-namespace.md) gives two tiny, funded local
account witnesses, with exact deposit arithmetic, consistent preimage invariants and fresh-solicit
OK predicates. Their mappings have conflicting values under identical T keys. Checked native
composition rejects both; no huge supplied blob or hash collision is needed. Full PVM execution
and genesis reachability have not been demonstrated.

**Question:** Which normative rule excludes these combinations or disambiguates their serialization?
Should the request domain/solicit rule reserve lengths, should an additional valid-state cross-map
constraint apply, or should T's namespaces change? A statement that the blob would be too large
alone does not exclude these witnesses: only a hash is read, the requested blob is absent, and the
charged footprint/deposit fits the defined uint64 domains.

Current behavior: retain the full E4 domain, preserve the exact formulas, reject duplicate mapping
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

M1's remaining state-parity question is the parked request namespace. Further implementation
scope is chosen separately with the maintainer; this does not claim PVM, transitions or validator
completeness, or that upstream has changed its text.
