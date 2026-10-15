# Assurance signing contexts

[The pinned interpretation](../spec/assurance-crypto.md) implements GP v0.7.1 `assurancesig`
without changing primitive providers. These operations compose the existing assurances codec types,
Blake2b-256 and ordinary Ed25519 verification. [Results and cumulative metrics](../results/assurance-crypto.md)
retain equivalent tests and actual development evidence.

| API/domain | Nim | Odin | Mojo |
| --- | --- | --- | --- |
| Expected parent | `AssuranceParent` | `Assurance_Parent` | `AssuranceParent` |
| Owned 46-byte transcript | `AssuranceSigningMessage` | `Assurance_Signing_Message` | `AssuranceSigningMessage` |
| Build message | `assuranceMessage(parent, bits, cores)` | `assurance_message(parent, bits, cores)` | `assurance_message(parent, bits, cores)` |
| Verify batch | `verifyAssurances(values, config, parent, keys)` | `verify_assurances(values, config, parent, keys)` | `verify_assurances(values, config, parent, keys)` |

Production modules are `nim/crypto/assurance_context.nim`, `odin/crypto/assurance_context.odin`
and `mojo/crypto/assurance_context.mojo`. Public-key types and imports remain those of the existing
primitive APIs. The key array must contain exactly the configured number of validators, in index
order. The caller supplies the correct active set; a record's index chooses its key.

The transcript is `$jam_available || Blake2b-256(parent32 || fixed bitfield)`. It excludes the
validator index, record count and signature. Bitfield wire length is `ceil(cores/8)`, with no
length prefix; unused high bits and native storage bytes must be zero. Tiny is 2 cores and
6 validators; full is 341 cores and 1023 validators. The supported core range is 1..341.

All structural, order, padding and expected-parent checks finish before signature verification.
This gives deterministic context-error precedence even if an earlier signature is invalid.
Empty records produce a successful zero count only with valid configuration and an exact key set.
No inputs are mutated or retained; production protocol storage consists of fixed native values.
No new seed owners, allocators, foreign handles or release obligations are introduced.

Inspect the checked result before selecting its value. Nim uses `error == AssuranceContextError.None`.
Odin uses `codec.error_of(result) == .None` and `codec.success_of(result)`; failure reasons belong
to `Assurance_Context_Error`. Mojo uses the existing `CheckedResult` success alternative or
`Failure`. Default outcomes are failures. Only completed success supplies a message or
`VerifiedAssuranceCount` / `Verified_Assurance_Count`.

The verified count certifies the explicitly supplied parent/key context and signatures only.
Pending-report eligibility, availability threshold/state changes and active-set selection remain
external. The documented exceptional-point Ed25519 provider discrepancy remains unresolved; this
API preserves each backend's existing verdict and never falls back to accept a rejection.

Reproduce using the pinned native crypto library already built by `interoperability/test_crypto.py`:

```sh
python3 interoperability/test_assurance_crypto_harness.py
python3 interoperability/test_assurance_crypto.py
python3 interoperability/test_assurance_crypto_types.py
```

The test oracle uses Python hashlib and independently installed OpenSSL for ordinary signatures,
validated against a hash-pinned RFC8032 known answer. Production execution remains native.
Linux CI runs these checks after its existing crypto build; local evidence does not imply a remote pass.
