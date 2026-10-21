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

## Implemented resolution and retained evidence

The crypto foundation introduced pinned `ed25519-zebra` 4.2.0 inside the existing Rust
library, sharing its SHA-2 0.10 closure. This upgrade activates that maintained ZIP215
verifier for `verify`, together with the new invalid null-validator key. Primitive
hashing/signing/wiping already use Rust; BoringSSL remains only for QUIC/TLS. No dependency
patch, handwritten group arithmetic, or alternate-verifier fallback is used. ark-vrf's
Ed25519 feature is an ECVRF suite and is not enabled as a signature implementation.

The original upstream Wycheproof fixture and hash are unchanged. Case 151 deliberately
sets the sign bit for R with x=0; it is labeled `invalid` under RFC8032 section 5.1.3.
ZIP215's decoding accepts this point encoding, so its expected result is explicitly
accepted under the current policy. Every other correctly sized case retains its original
label; wrong widths still fail typed import. The all-zero A/R, S=0 witness also changes
to acceptance under the cofactored equation. These differences follow normative rules,
not a blanket relaxation of invalid corpus labels.

Native cases retain RFC8032 positives and altered-message rejection, A of order four,
noncanonical identity A/R, invalid A/R, S=group order and failed equations. The primitive
ABI retains malformed-pointer/size, ownership, observer-failure and relocation checks.
The current Thin VRF gate remains separate: these signatures do not establish Thin parity.
