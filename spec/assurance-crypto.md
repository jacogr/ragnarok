# Assurance signing context

Target GP `fad0ded4a433052397bf7234352a57fe491883f7`,
`reporting_assurance.tex` equation `assurancesig`, anchors/order preceding it, and Appendix C.1/C.2.
The existing source SHA pins in `spec/pins.json` cover these definitions.

The [assurance context module](../src/crypto/assurance_context.nim) owns the transcript,
input validation order and verification result contract.

The provider follows the existing [ZIP215 contract](crypto-zip215-upgrade.md). This encoding
upgrade preserves that primitive implementation and its pins. Ordinary RFC8032-derived keys and
independent OpenSSL signatures qualify these transcripts; exceptional-point coverage belongs to
the primitive qualification rather than being inferred from this ordinary-credential corpus.

Acceptance compares every message byte with Python hashlib; uses independent OpenSSL signing
validated against a pinned RFC8032 known answer; tests tiny/full and byte-width boundaries;
empty/max records; wrong key-set length, validator/order/padding/parent-bound signatures; late structural
failure before an earlier invalid signature; wrong key, signature, domain and hashed framing;
and input immutability. Existing assurances and report suites are fresh-build baselines/rechecks.
Nominal message/signature compiler probes remain separate diagnostics.

## Historical Nimony trial evidence

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

Results are local macOS ARM64, checked ARC/Clang LTO; Linux and full M3 parity remain separate.
Guarantee/report signing composition now also passes. Bandersnatch owner safety and original
contextual proof/JAM ticket/native-boundary/concurrency coverage now also pass locally. M3
UDP/readiness and linked transport lifecycle checks now pass locally.
Shared identity/DER/framing validation now also passes locally.
CE 143 integration results and retained digest ownership now also pass locally.
The peer executable and one-shot authenticated CE 143 matrix now also pass locally.
Retained CE 143 service and integrated digest lifecycles now also pass locally.
Retained IPv6 mesh/reconnect and peer-loss recovery now also pass locally.
Next: same-process endpoint soak and remaining admission/resilience coverage; Linux confirmation and documented
normative policy gates remain separate. See the [cumulative trial](../docs/nimony-trial.md); the
exceptional-point policy remains unresolved.

## Signing-token audit correction

The [credential-backed audit](signing-domains.md) corrects the historical dollar-prefixed
transcript to the 45-byte ASCII-domain message. It adds 1,035 unchanged upstream credentials
and preserves old-domain rejection; earlier local hashlib/OpenSSL fixtures shared the same
interpretation error and did not establish this interoperability property.
