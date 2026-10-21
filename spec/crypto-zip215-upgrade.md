# ZIP215 compatibility required by the unreleased Gray Paper pin

## Authority and implementation gap

Gray Paper commit `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` adds an explicit
ZIP215 requirement to `notation.tex`, Signing Schemes. The existing crypto
bridge uses `ED25519_verify` from BoringSSL commit
`88341070936d28e08f82db1326c73d67962cd043`. Its RFC8032 acceptance policy is
not equivalent to the newly required [ZIP215 policy](https://zips.z.cash/zip-0215).
This is an implementation upgrade requirement, not a Gray Paper discrepancy
or ambiguity. Do not report the current backend as ZIP215 compatible.

## Minimal fixed public witnesses

Use public key32 zero bytes, signature `01` followed by63 zero bytes, and any
of the messages empty, `00`, or ASCII `ragnarok`. In Edwards coordinates this
key has order4, signature R is the identity, and S=0. Thus all terms in ZIP215's
cofactor-multiplied verification equation are the identity for every message.
ZIP215 accepts all three witnesses. The pinned C bridge rejects all three.
The corresponding reduced challenge residues modulo4 are1,2,1.

The same loaded bridge successfully derived a public key, signed and verified
a message using a fixed public all-zero fixture seed, and rejected a flipped
signature byte. These controls distinguish a verification-policy mismatch from
incorrect ABI arguments or a broken backend load. Exact encodings, source pins
and backend SHA256 are retained in `build/graypaper-zip215-audit.json`.

## Required resolution before publication

Keep BoringSSL's maintained signing/hash operations and use a maintained ZIP215
verifier for the newly required verification policy, or leave this coordinated
pin upgrade unpublished. No dependency patch or handwritten group-arithmetic
replacement is proposed. The maintainer authorized a crypto foundation PR first, preferring reuse of the
existing ark-vrf native dependency closure, followed by the pin upgrade on top.
The pinned ark-vrf Ed25519 feature is an ECVRF suite, not ordinary Ed25519
signature verification; primitive reuse must preserve the required algorithm.

Verification must retain RFC8032 positives, malformed encodings and scalars,
cofactor/noncanonical ZIP215 witnesses, existing observer failures, cross-platform
build wiring and ownership contracts. Existing release-profile crypto successes
cannot establish current ZIP215 compliance. The current Thin VRF gate remains
separate and must not be hidden by this change.
