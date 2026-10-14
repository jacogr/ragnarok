# Primitive crypto contract

Baseline: Gray Paper v0.7.1, commit
`1c979cb59bb800f92ffff083a2701004dfc6cd33`,
[Cryptography](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/notation.tex#L155).
Toolchain/dependency/vector revisions are in [crypto-pins.json](crypto-pins.json).

| Operation | Contract |
| --- | --- |
| Blake2b-256 | Unkeyed raw-byte input, digest length configured as 32 bytes. Never truncate Blake2b-512. |
| Keccak-256 | Legacy Ethereum-style Keccak: rate 1088, capacity 512 bits, suffix 0x01, 32-byte digest. Never SHA3-256's 0x06 suffix. |
| Ed25519 key derivation | Exact 32-byte RFC 8032 seed to 32-byte encoded public key. All-zero seed is valid when explicitly imported. |
| Ed25519 signing | Ordinary deterministic Ed25519 over the exact raw message, 64-byte signature. No implicit domain, prehash, Ed25519ctx or Ed25519ph. |
| Ed25519 verification | Exact 32/64-byte encoded key/signature import, then backend verification. Wrong sizes fail import; correctly sized invalid encodings/signatures return false. |

Domain construction and codec serialization remain caller responsibilities in
Nim/Odin. Hashes, keys and signatures have distinct nominal types. Public-key
import proves width/ownership only; it does not assert subgroup membership.
Hash/key/signature values own bytes. Seed handles hide their private retained
copy and cannot silently substitute a default seed. Failed results carry only
a reason; defaults fail. Checked success selection remains enabled in release.

## Verification policy remains an explicit protocol question

[RFC 8032 section 5.1.7](https://www.rfc-editor.org/rfc/rfc8032#section-5.1.7)
allows a cofactored verification equation and a sufficient uncofactored check.
Odin core uses canonical A/R/S encodings, a cofactored equation and rejects
small-order A by default. Nim preserves pinned BoringSSL's verifier policy.
Neither wrapper tunes provider acceptance to make a corpus pass. Both pass all
151 pinned Wycheproof cases, including the corpus's edge encodings. Additional
explicit probes expose a difference outside that corpus: BoringSSL accepts
A=identity, R=identity, S=0 for both empty and `abc` messages; Odin rejects both
because its default rejects small-order A. The regression suite records each
provider's actual verdict. Both reject S equal to the group order and the tested
all-zero A/R, S=0 encoding. These probes are supplementary policy evidence, not
an exhaustive exceptional-point corpus.

A complete JAM integration still needs an explicit normative decision and
focused independent tests for every exceptional point/canonicality policy.
Do not advertise these backend verdicts as a finalized consensus verifier.
The pinned official JAM vector tree has no standalone primitive-crypto corpus;
RFC/Wycheproof tests are supplemental primitive evidence, not JAM state tests.

## Reproducibility and provenance

Odin's compiler revision pins core Blake2b, Ed25519 and legacy Keccak and their
internal dependencies. Nim reuses QUIC's pristine BoringSSL source revision;
this source has Blake2b-256 and Ed25519, but no legacy Keccak API. XKCP, maintained
by the Keccak team, supplies its portable 64-bit permutation/sponge. The bridge
selects parameters and marshals pointers only; no project production permutation
or signature implementation is introduced. The generated XKCP config header
selects KeccakP1600 outside upstream source storage. No dependency source patch
is applied. The new native dependency is needed only by Nim's Keccak backend.

Upstream licensing remains with the source trees (BoringSSL's component notices,
XKCP's component/SPDX notices, Odin's distribution license). Wycheproof's public
fixture is read unmodified from its pinned submodule under its Apache-2.0 license; RFC vectors originate
in RFC 8032 section 7.1 under the RFC's IETF Trust terms. Source identities and
fixture SHA-256 digests are pinned. The original Wycheproof license remains with its source submodule. Tests establish functionality; they do not establish an
audit of every selected module or a production suitability certification.
