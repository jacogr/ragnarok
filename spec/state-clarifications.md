# Parked M1 specification clarification questions

Pinned Gray Paper: v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`.
Pinned reference vectors: v0.8.0 `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
This is a local review packet, not an upstream ruling or a submitted issue.

## Status: parked by the maintainer

Revisit both questions when reviewing Gray Paper **0.8.1/0.8.2**. They remain unresolved parity
gates, but are not active work. Preserve the current codecs, duplicate-key rejection, evidence and
pending tests; no interim workaround or inferred protocol restriction is planned.

During that version review:

- Check request key prefixes, the blob-length domain, solicit rules and account invariants against
  the two existing small-payload witnesses.
- Check statistics gas definitions and T's width note against the release-matched raw vectors.
- Record whether each question is resolved, unchanged or replaced before changing implementation
  behavior or closing a pending test. Upgrade pins only within an authorized specification migration.

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

## Statistics gas width versus published wire

T's general note requires fixed-length non-discriminator state numbers; gas has a uint64 domain.
However, all sixteen later raw C13 values in the [width evidence](state-widths.md) reconstruct
with natural gas. E8 gas candidates fail exact reconstruction. For example,
`traces/fuzzy/00000025.json` pre-state's matching candidate has first-core gas 182161, occupying
three natural bytes rather than eight. The E4 service-key migration is already verified separately.

**Question:** Should T explicitly except these statistics gas fields from the fixed-width note,
or should the reference raw state values use E8 for core/refinement/accumulation gas? Any other
intended encoding needs an explicit definition and matching raw vectors.

Current behavior: retain the published natural statistics-gas framing with an explicit pending
normative/reference gate. No gas-width fallback, vector rewriting or full M1 parity claim.

Next review trigger: evaluating Gray Paper 0.8.1/0.8.2, or an explicit maintainer request.
No further clarification increment is scheduled against the current 0.8.0 pin.
Codec families and selected whole-state mappings otherwise have the recorded implementation tests;
this does not claim PVM, state-transition or production-validator completeness.
