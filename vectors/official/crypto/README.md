# Public primitive fixtures

`rfc8032.json` transcribes all five ordinary Ed25519 vectors in
[RFC 8032 section 7.1](https://www.rfc-editor.org/rfc/rfc8032#section-7.1):
32-byte seed, public key, raw message and 64-byte signature. The original RFC is
subject to the [IETF Trust terms](https://trustee.ietf.org/license-info).

`ed25519-wycheproof.json` is the unmodified 151-case file from the commit/path in
[crypto-pins.json](../../../spec/crypto-pins.json), with the upstream Apache-2.0
license in `LICENSE-wycheproof`. Both fixture SHA-256 values and the license hash
are checked by the runner. Test seeds/messages are public fixtures.

Blake2b-256 cases use independent Python hashlib configured for a 32-byte digest.
Keccak uses a test-only integer oracle of the Keccak-f round equations and legacy
padding; published empty/abc digests anchor it. Neither oracle is production
code or uses the native adapters under test. Boundary/random cases supplement,
rather than replace, independent published vectors.
