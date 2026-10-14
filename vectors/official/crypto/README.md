# Public primitive fixtures

`rfc8032.json` transcribes all five ordinary Ed25519 vectors in
[RFC 8032 section 7.1](https://www.rfc-editor.org/rfc/rfc8032#section-7.1):
32-byte seed, public key, raw message and 64-byte signature. The original RFC is
subject to the [IETF Trust terms](https://trustee.ietf.org/license-info).

The unmodified 151-case Wycheproof file and Apache-2.0 license now live in
`vendor/wycheproof`. Both fixture and license hashes remain checked by the runner;
[crypto-pins.json](../../../spec/crypto-pins.json) records the revision/path.
No duplicate upstream corpus is committed here.

Blake2b-256 cases use independent Python hashlib configured for a 32-byte digest.
Keccak uses a test-only integer oracle of the Keccak-f round equations and legacy
padding; published empty/abc digests anchor it. Neither oracle is production
code or uses the native adapters under test. Boundary/random cases supplement,
rather than replace, independent published vectors.
