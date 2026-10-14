# Bandersnatch public fixtures

The seven-case IETF and RingVRF published fixtures now live directly in
`vendor/bandersnatch-vrf-spec/assets/vectors/`. They share provenance with the
reference backend and are not independent implementation oracles. The original
backend's MIT license remains in `vendor/ark-vrf/LICENSE`.

`jam-tiny.json`, `jam-full.json` and `jam-padding.json` retain only cryptographic
inputs and expected scores/roots from independently generated official
[GP v0.7.1 JAM vectors](https://github.com/w3f/jamtestvectors/tree/1dc503af37ae8ecc7b6e24a393f6102801c0c80c).
The source paths, original-file SHA-256 and reduced-file SHA-256 are in
[bandersnatch-pins.json](../../../spec/bandersnatch-pins.json). The runner reads complete original cases from `vendor/jamtestvectors` and
verifies each reduced object against the original fields. Reducing full STF fixtures avoids committing
megabytes of unrelated pre/post-state metadata. This round runs primitive checks,
not the complete Safrole state-transition suite.

The ticket context is `jam_ticket_seal || eta[2] || attempt_byte`; additional
data is empty. The expected 32-byte output is taken from the official posterior
ticket accumulator. The padding-root case uses posterior pending-key encodings
and the posterior ring root. All private scalars in published vectors are public
test material, not production keys.
