# Assurance signing context

Pinned GP v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`reporting_assurance.tex` equation `assurancesig`, anchors/order preceding it, and Appendix C.1/C.2.
The existing source SHA pins in `spec/pins.json` cover these definitions.

The signing message is exactly the 46-byte owned value
`ASCII("$jam_available") || Blake2b-256(parent_hash32 || fixed_profile_bitfield)`.
The bitfield has `ceil(cores/8)` bytes, LSB-first, with no length or record-count prefix. The
validator index and signature are not included in the hash. Blake2b-256 is the 32-byte output
parameterization, not a truncation of Blake2b-512. A parent hash is a nominal domain distinct
from the assurance's anchor and from a cryptographic digest. Core counts are 1..341, with the
existing 43-byte native bitset storage and canonical padding rules.

Expose a message builder accepting parent, bits and core count, and a batch verifier accepting
owned assurance records, explicit codec configuration, expected parent and an ordered borrowed
array of existing Ed25519 public-key values. Neither operation mutates its inputs, retains a
pointer, allocates protocol storage or owns keys. Their success-only payloads are an owned signing
message and verified record count respectively; defaults/failures contain only their reason.
The count certifies this stateless context check, not successful state transition or availability.

The verifier checks in this precedence: valid configuration (2..341 cores, 6..3*cores validators in multiples of three);
exact key-set length matching the
configured validator count; count ceiling; each record's validator bounds, strict order, canonical
bitfield padding and expected parent equality, in record order; then each signature in order.
All structural/context checks finish before any signature verification. Empty records succeed
with zero count only after configuration and exact key-set checks. For each record, select the
public key by its validator index, build the normative message, import its fixed signature bytes
and call the existing provider verifier. Hash/import failure maps to backendfailure; rejected
signatures map to invalidsignature. No fallback accepts a rejected signature.

Reasons are uninitialized, invalidconfig, invalidkeyset, limitexceeded, invalidvalidator,
noncanonical, wrongparent, invalidsignature and backendfailure. Message construction checks only
core configuration and bitset padding before hashing; it cannot authorize an assurance by itself.

This bounded M2 composition slice does not implement pending-report eligibility,
availability thresholds, validator-set selection, block import, state mutation or new primitives.
The caller supplies the correct active validator set and post-judgement state remains external.
The existing exceptional-point Ed25519 provider-policy discrepancy remains an explicit unresolved
protocol gate. This round uses ordinary RFC8032-derived keys and independently generated OpenSSL
signatures; it does not claim universal provider equivalence or resolve that policy implicitly.

Acceptance compares every message byte with Python hashlib; uses independent OpenSSL signing
validated against a pinned RFC8032 known answer; tests tiny/full and byte-width boundaries;
empty/max records; wrong key-set length, validator/order/padding/parent errors; late structural
failure before an earlier invalid signature; wrong key, signature, domain and hashed framing;
and input immutability. Existing assurances and report suites are fresh-build baselines/rechecks.
Intentional nominal parent/anchor and message/signature compiler probes remain separate diagnostics.

## Nimony trial evidence

The pinned Nimony branch preserves this transcript, verification order, synchronous input borrows
and backend signature policy. Result status/payloads are private; read-only errors and a supported
success precondition protect both fixed result types. No input-derived protocol allocation or
retained input pointer is introduced.

The runner replays all 2,087 frozen requests and four independent oracle checks against the real
primitive bridge. A separate observer-linked suite checks source/extracted copies, complete
preflight before hashing, immediate/delayed backend refusal, ordinary invalid signatures and
recovery without input mutation. Public live occupancy returns 192 to 192 bytes after 1,000 warmed
scopes. Twenty-four isolated actual/default payload reads reject at their success contracts, and
seven private/read-only plus two nominal compiler probes reject at the intended boundaries.

Results are local macOS ARM64, checked ARC/Clang LTO; Linux and full M2/M3 parity remain separate.
Next is guarantee signing-message and complete-report signature composition. See the
[cumulative trial](../docs/nimony-trial.md); the exceptional-point policy remains unresolved.
