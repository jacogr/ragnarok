# Bandersnatch public fixtures

`ietf.json` and `ring.json` are unmodified published assets of the historical
[Bandersnatch specification](https://github.com/davxy/bandersnatch-vrf-spec/tree/38cf32d33d9d860feccd1f56b3bf6633c05669b0).
Their seven cases each share provenance with the reference ark-vrf backend;
this is explicitly not an independent implementation oracle. The reference
implementation is MIT licensed; its license is retained in `LICENSE-ark-vrf`.

`jam-tiny.json`, `jam-full.json` and `jam-padding.json` retain only cryptographic
inputs and expected scores/roots from independently generated official
[GP v0.7.1 JAM vectors](https://github.com/w3f/jamtestvectors/tree/1dc503af37ae8ecc7b6e24a393f6102801c0c80c).
The source paths, original-file SHA-256 and reduced-file SHA-256 are in
[bandersnatch-pins.json](../../../spec/bandersnatch-pins.json). The runner fetches
complete original cases into ignored build storage and verifies each reduced
object against the original fields. Reducing full STF fixtures avoids committing
megabytes of unrelated pre/post-state metadata. This round runs primitive checks,
not the complete Safrole state-transition suite.

The ticket context is `jam_ticket_seal || eta[2] || attempt_byte`; additional
data is empty. The expected 32-byte output is taken from the official posterior
ticket accumulator. The padding-root case uses posterior pending-key encodings
and the posterior ring root. All private scalars in published vectors are public
test material, not production keys.
