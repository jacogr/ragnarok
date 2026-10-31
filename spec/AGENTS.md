# Protocol interpretations and feature records

Read this file for protocol behavior, domain bytes or specification/vector upgrades, even when
only editing implementation code. Preserve these established interpretations.

The Gray Paper is the primary PVM specification. Implement independently; pinned PolkaVM is
the accepted implementation cross-check for fixture compatibility, not a porting target. Record
contradictions, ambiguities and missing definitions in the [discrepancy register](graypaper-discrepancies.md),
with exact pins, minimal witnesses, observed/reference results and fixture coverage. Keep approved
exceptions scoped, including [memory ordering](pvm-polkavm-memory-order.md); do not infer
unrelated behavior or pin changes. Preserve independent JAM/vector and host-function contracts.

For encoding-width discrepancies, the maintainer directs following the published vectors: if the
vectors encode a field compactly, use that compact encoding and document the text discrepancy.
Use exactly one representation, with no alternate-format fallback. This accepts C13 statistics gas
as canonical JAM compact naturals (1–9 bytes); it is not a pending implementation/parity gate.
Fixed encodings used by the vectors remain fixed.

GP token notation's dollar sign is not a token byte: signing domains use ASCII `jam_available` and
`jam_guarantee`; general-tree domains use ASCII `node` and `peak`. Preserve exact token bytes with
no fallback, count prefix or terminator. See [the credential-backed audit](signing-domains.md).
Other specifications, including JAMNP-S identity names, require their own independently checked
interpretation; do not globally strip dollar characters from unrelated strings.

Never guess protocol semantics. Document ambiguity and add a focused failing/pending test. Cite
pinned revisions and sections in protocol changes. `spec/` records interpretations and hashes;
`vendor/` gitlinks pin upstream source identities.

- The maintainer authorized the unreleased Gray Paper upgrade on2026-10-21.
  The target `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` includes PR542:
  current request lengths are strictly below2^32−2, excluding the two reserved
  namespace prefixes. Preserve historical M1 evidence as release-era evidence;
  current production uses the bounded domain with one canonical encoding.
  Open #564 format changes remain outside this target.

- On 2026-10-31 the maintainer authorized the credential-encoding source clarification at
  `3861aed15d7d016a3a416e14e61fc67dddf6daec`. This supersedes the current source pin
  above while retaining its protocol rules; see [qualification](graypaper-credential-encoding.md).


Feature contracts record applicable scope, pinned references, completion tests, interpretation,
observed evidence, limitations and next bounded work. Passing local tests is not proof of complete
JAM parity. Keep routine progress out of the shared design pages.
