# GP539 vector qualification

## Scope and authority

The maintainer authorized this vector upgrade on 2026-10-30. Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary authority.
The canonical `jam-conformance/jam-test-vectors` `gp-next` pin advances from
`23061ae1f9b51171c01387e7dde0f15794c98e24` to
`d7b73e396d2f872fcfca37cbbb7d7869675d34d6` (Regen STF vectors for GP 539).
This is unreleased branch data, not a new published vector release.

## Integration

The upstream commit changes 519 paths; 108 of the 379 previously consumed source paths
change. Selected source hashes are refreshed from exact immutable Git bytes.
The account and report-policy references now preserve the published supervisor,
supervisor-creation-slot and supervisor-balance fields rather than synthesizing zeroes.
The live-transfer projection retains its 100-unit credit; its published starting balance
changes from 227738 to 229035. Historical 89-byte trace metadata remains explicitly
projected into the current 105-byte layout, with its original provenance.

The Safrole source bytes and derived Bandersnatch vectors are unchanged. Updating
`official_jam.commit` changes the crypto pin-file hash, so the six JAM input witnesses
and their dependent report/descriptor hashes are refreshed without changing signatures,
crypto commitments, state values or observations. Historical mixed-profile signed-trace
refusal evidence retains its original source revision.

## Completion checks and limits

Require exact source provenance, independent account/width/root/credit references,
native account/report-policy/credit consumers, and the full CI run on the top fuzzing
PR. This pin upgrade does not claim complete execution parity for every upstream
accumulation case. Eight new JSON scenarios (four per population), including junior
transfers and supervisor discard/control cases, now supply both transition phases to
the independent/native account metadata corpus, with literal field-offset checks and
nonzero supervisor identities (these cases retain zero creation slots and balances). This covers serialization, not full execution
of those scenarios; existing independently authored current-STF supervision coverage
is retained.
