# Local and derived vectors

[Project overview](../README.md) · [Testing guide](../docs/testing.md) ·
[Pinned references](../spec/README.md)

This directory contains small project-authored boundary fixtures and retained public or derived
cryptographic vectors. Complete upstream corpora remain in pinned
[`vendor/`](../vendor/README.md) submodules.

| Path | Contents |
| --- | --- |
| [`assurance-context.json`](assurance-context.json) | Assurance signing-context corpus count and expected hashes |
| [`bounded-containers.json`](bounded-containers.json) | Bounded-container fixtures |
| [`fixed-unsigned-boundaries.json`](fixed-unsigned-boundaries.json) | Fixed-width unsigned integer boundaries |
| [`natural-boundaries.json`](natural-boundaries.json) | General natural-number boundaries |
| [`official/bandersnatch/`](official/bandersnatch/README.md) | Reduced JAM ticket and padding-root fixtures with source provenance |
| [`official/crypto/`](official/crypto/README.md) | RFC 8032 Ed25519 vectors and primitive-reference notes |
| [`official/LICENSE`](official/LICENSE) | License retained with the official fixture collection |

The nested READMEs explain derivation, upstream provenance and licensing; JSON pins in
[`spec/`](../spec/README.md) record source identities and hashes. Original published inputs stay
unchanged, and derived cases are checked against their recorded sources.

Other committed runtime inputs and expected replies live in
[`tests/fixtures/`](../tests/fixtures/README.md). Generated corpora and reports stay under `build/`.
