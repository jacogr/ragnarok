# Current Gray Paper Thin VRF qualification

## Authority and scope

The adopted Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/bandersnatch.tex`, requires Thin signatures and Pedersen RingVRF. Its
`biblio.bib` entry `hosseini2024bandersnatch` explicitly says **Draft 35,
fetched 21 August 2026**. The moving `main/specification.pdf` URL is therefore
resolved using that draft, rather than today's upstream main.

Exact source identities inspected on 24 October 2026:

- [Draft 35](https://github.com/davxy/bandersnatch-vrf-spec/tree/122f52fb63c6e8eb887aa7416f869aba5075519b),
  tag `draft-35`, commit `122f52fb63c6e8eb887aa7416f869aba5075519b`.
- Its Appendix C identifies vector generator `ark-vrf 0.5.3`; its example
  Cargo manifest independently names `0.5.3`.
- [Generator source](https://github.com/davxy/ark-vrf/tree/9ec593e98b69395e97680330e75b5235b48121f4),
  tag `v0.5.3`, commit `9ec593e98b69395e97680330e75b5235b48121f4`.
- Maintained migration candidate [ark-vrf 0.6.0](https://github.com/davxy/ark-vrf/tree/dfb696dfb92425009af80dbbb403e647f6c9e3e4),
  commit `dfb696dfb92425009af80dbbb403e647f6c9e3e4`. Its `bandersnatch` suite
  explicitly preserves the above v1 profile, while adding canonical decoders,
  private point/proof fields and safer constructors. Choosing it is conditional
  on reproducing the Draft 35 vectors, SRS and consumer checks below.

This qualification does not advance either production gitlink. The existing
`bandersnatch-pins.json` describes the historical executable profile until the
migration lands. The old draft-29 challenge discrepancy is distinct from the
current requirement and cannot establish or prevent Thin compatibility.

## Exact target profile

Draft 35 sections 1.4–1.6, 3, 4, 5 and Appendix A define:

- Suite: the 27 ASCII bytes `Bandersnatch-SHA512-ELL2-v1`, twisted Edwards
  Bandersnatch, cofactor 4, SHA-512 HashTranscript, 128-bit challenge strength.
- Point: canonical 32-byte little-endian y with high-bit x sign. Arkworks' sign
  is x greater than half the field modulus, not x parity. Reject y outside the
  field, non-subgroup encodings and alternate encodings. Scalars are canonical
  32-byte little-endian integers below the scalar order. The bridge imports
  scalars, not seeds; reject zero secrets and identity public/input/output points.
  Thin R and Pedersen R/O_k may be the identity (Draft 35 sections 3.2 and 4.2).
- Input: Elligator2 random oracle on raw context bytes; two mapped field
  elements, addition and cofactor clearing. DST is suite bytes followed by `60`.
  The executable v1 profile uses **48 zero prefix bytes**, not the RFC's 128.
- Transcript: SHA-512 over absorbed bytes; squeeze hashes the finalized 64-byte
  seed followed by an eight-byte little-endian counter starting at zero.
  Streaming preserves the unused portion of each 64-byte output block.
- Scheme tags: Tiny `00`, Thin `01`, Pedersen `02`; nonce expansion `10`,
  nonce `11`, Pedersen blinding `12`, output `20`, delinearization `30`,
  challenge `40`, batch `50`, hash-to-curve `60` (all hexadecimal bytes).
- Ordinary proof transcript: suite, `01`, u64le pair count, ordered compressed
  input/output pairs, u64le additional-data length, raw additional data. Prepend
  `(G,Y)` to the application's `(I,O)` pair, so a JAM signature has count two.
  Delinearization forks with `30`: first coefficient one, subsequent coefficients
  from 16-byte squeezes. Challenge forks with `40` and compressed R, then
  squeezes 16 bytes. It is not serialized in Thin.
- Nonce: fork the complete scheme transcript; append `10` and canonical secret,
  squeeze 64 bytes; append `11` and those 64 bytes to a second transcript fork,
  squeeze 48 bytes and reduce little-endian modulo the scalar order. AD therefore
  separates nonces. Pedersen first binds its key commitment and derives its
  blinding with the separate `12` tag; preserve the upstream procedure.
- Thin wire: `O(32) || R(32) || s(32)`, with `R=k*I_m`, `s=k+c*x`.
  Ring wire: `O(32) || PedersenProof(160) || RingProof(592)` = 784 bytes.
  Its Pedersen components are key commitment, R, O_k, s, s_b in that order.
- Output: squeeze `suite || 20 || compressed(O)` for the chosen output length;
  JAM uses its first 32 bytes. AD affects the proof and nonce but not O or its hash.
- Ring: ordered members, v1 blinding/accumulator/padding constants from sections
  4–5, KZG over BLS12-381, ark-transcript label `ring-proof`. SRS is the public
  Zcash Powers of Tau-derived asset; domain size and ring capacity remain explicit.
  A 144-byte commitment does not identify its SRS or domain.

## Compatibility matrix against the production 0.2.2 adapter

| Concern | Historical adapter | Draft 35 target / required action |
| --- | --- | --- |
| Suite | `Bandersnatch_SHA-512_ELL2` | Different v1 suite ID; incompatible transcripts |
| Secret/public wire | Scalar and Edwards compressed, 32 bytes | Preserve ABI/import semantics; enforce canonical/subgroup decode |
| Ordinary proof | O, 32-byte c, 32-byte s | O, 32-byte R, 32-byte s; same width, incompatible semantics |
| Challenge | Historical 32 bytes | Internal 16 bytes, no challenge field in Thin wire |
| Transcript | IETF release-reference hash procedures | New pair count, delinearization, AD length and scheme tags |
| Input point | Historical suite/DST | Recompute with v1 DST and exact 48-byte expansion prefix |
| Nonce | 0.2.2 AD-bound RFC8032 helper | New transcript-bound expansion; test distinct AD and scheme separation |
| Output | Historical RFC9381 helper | New `20` transcript; change all known output expectations |
| Ring proof | 784-byte historical Pedersen/Ring | Same width; transcript, bases and dependency closure must be requalified |
| Padding/root | Historical padding point and bases | New specified point; regenerate expected roots from independent sources |
| Setup/SRS | Public SRS, explicit domain, 1..1023 capacity | Compare actual asset bytes and constructors; no seed-generated replacement |
| ABI ownership/errors | Opaque owners, reason-only failures, commit on success | Preserve handles/statuses/widths and all-or-nothing writes |
| Consumers | Safrole tickets, seal/entropy contextual signatures | Run actual vector/consumer paths; do not infer parity from widths |
| Old vectors | Draft-29 signatures and historical JAM tickets pass | Retain historical evidence; test/refuse cross-profile replay explicitly |

## Independent evidence and migration completion checks

`tests/test_bandersnatch_thin_reference.py` implements test-only affine Edwards
arithmetic and the Draft 35 SHA-512 transcript independently of Rust/arkworks.
Its attributed Appendix C.2 vector-one regression reconstructs Y, O, R, s,
the verification equation and output bytes; AD mutation and noncanonical
scalar/point encodings fail. It accepts supplied H, and therefore makes no
claim to independently validate the hash-to-curve algorithm or ring proofs.

The same independent equations were run against **all seven** exact Draft 35
Thin JSON vectors during qualification: all fields above reproduced. The
currently built 0.2.2 C ABI rejects vector one with status 4 (equation failure)
and leaves a sentinel output unchanged. This is direct evidence of incompatibility.

The migration must additionally reproduce all seven Thin and seven Ring
vectors through the safe production-feature ABI, including native hash-to-curve,
output derivation, ordered commitments, wrong context/AD/domain, malformed
canonical encodings, setup boundaries and actual Safrole/contextual consumers.
No deterministic/non-ZK `test-vectors` feature may enter that build. Update the
lock, source-tree/fixture/SRS hashes and relevant instruction contracts together;
keep upstream pristine. Compile and run checked ARC/Clang consumers and format
through Make. Only passing exact-source tests can promote the candidate pin.

## Text discrepancy and bounded claims

Draft 35 Appendix A.2 cites RFC9380 without naming the 48-byte deviation.
Upstream [Draft 36](https://github.com/davxy/bandersnatch-vrf-spec/blob/c32f7a9f38667ba2cda3c4e44bba78dc0a73224e/specification.md#2-hash-to-curve)
explicitly documents the v1 deviation and says RFC-prefix implementations do
not reproduce its constants or vectors. That later text is clarification evidence,
not authority to change the adopted Gray Paper target. Ark-vrf 0.6.0 exposes
RFC padding separately as `bandersnatch_v2`; do not select it for this migration.
Following the published Draft 35 vector profile resolves an executable target;
literal RFC equivalence remains a specifically recorded text discrepancy.
Passing these vectors is neither an independent cryptographic audit nor full
current-pin JAM STF parity. The current stage-vector and complete-state work
continues after this primitive migration; historical trace metadata alone does
not block independently authored current-schema end-to-end validation.
