# Protocol interpretations and feature records

Read this file for protocol behavior, domain bytes or specification/vector upgrades, even when
only editing implementation code. Preserve these established interpretations.

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

- The M1 request-namespace question is parked by the maintainer pending Gray Paper 0.8.1/0.8.2
  review. Upstream #542 now resolves the domain overlap, but adoption awaits compatible pins.
  Preserve its evidence, pending test and current 0.8.0 codec behavior. Follow
  [the upstream disposition](state-clarifications.md) during the specification/vector upgrade;
  do not invent interim restrictions or adopt open #564 format changes without matching evidence.

Feature contracts record applicable scope, pinned references, completion tests, interpretation,
observed evidence, limitations and next bounded work. Passing local tests is not proof of complete
JAM parity. Keep routine progress out of the shared design pages.
