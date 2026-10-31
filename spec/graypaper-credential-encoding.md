# Gray Paper credential-encoding pin

## Scope and source

The maintainer authorized this pin and documentation update on 2026-10-31.
The unreleased Gray Paper source advances from
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` to
`3861aed15d7d016a3a416e14e61fc67dddf6daec`.
The protocol version remains 0.8.0; this is not a newly published release.

The exact upstream delta touches only
[the header projection](https://github.com/gavofyork/graypaper/blob/3861aed15d7d016a3a416e14e61fc67dddf6daec/text/header.tex),
[Appendix C](https://github.com/gavofyork/graypaper/blob/3861aed15d7d016a3a416e14e61fc67dddf6daec/text/serialization.tex),
and [the shared macro](https://github.com/gavofyork/graypaper/blob/3861aed15d7d016a3a416e14e61fc67dddf6daec/preamble.tex).
The header now explicitly reuses the credential encoding from Appendix C:
a canonical natural credential count, followed by E2 little-endian validator
indices and unchanged 64-byte signatures.

## Compatibility and provenance

`src/crypto/extrinsic_commitment.nim` already uses those exact fields and widths.
This update changes no production code, wire bytes, signing domains, expected
commitments, validation rules or runtime checks. The existing commitment suite
provides the native consumer check.

Current crypto and vector-compatibility metadata follow the new Gray Paper pin.
The vector gitlink remains `d7b73e396d2f872fcfca37cbbb7d7869675d34d6`.
Historical feature records and authored fixtures retain their original Gray Paper
source identities; their byte-level expectations remain unchanged. The active
source audit records the new qualification revision, preserving every source hash
and classified root. Changing the Bandersnatch pin-file metadata requires fresh
pin-file digests in six JAM input witnesses and their dependent report/descriptor
hashes; those changes are provenance only.

## Completion checks

Require exact submodule/source hashes and synchronized current pin records,
fixture descriptor/provenance checks, reproduction of the active source audit,
and the existing checked native extrinsic-commitment suite. These checks qualify
this narrow source clarification; they do not establish complete client conformance.
