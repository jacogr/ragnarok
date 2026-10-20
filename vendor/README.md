# Pinned upstream sources

[Project overview](../README.md) · [Dependency policy](../docs/dependencies.md) ·
[Feature contracts and pins](../spec/README.md)

Each directory below is a Git submodule pinned by the parent repository to an exact upstream
commit. [`../.gitmodules`](../.gitmodules) records repository URLs; JSON files in
[`spec/`](../spec/README.md) record the identities and hashes used by individual features.

| Submodule | Role |
| --- | --- |
| [`ark-vrf/`](ark-vrf/) | Bandersnatch IETF VRF/RingVRF reference backend |
| [`bandersnatch-vrf-spec/`](bandersnatch-vrf-spec/) | Historical suite specification, vectors and SRS |
| [`boringssl/`](boringssl/) | TLS and Blake2b-256/Ed25519 primitives |
| [`graypaper/`](graypaper/) | Pinned JAM protocol specification |
| [`jam-np/`](jam-np/) | JAMNP-S networking specification |
| [`jamtart/`](jamtart/) | Collector used by telemetry interoperability checks |
| [`jamtestvectors/`](jamtestvectors/) | Published JAM codec and Safrole vectors |
| [`lsquic/`](lsquic/) | QUIC transport and its recorded nested dependencies |
| [`polkavm/`](polkavm/) | Test-only PVM cross-check source |
| [`wycheproof/`](wycheproof/) | Independent adversarial Ed25519 corpus |
| [`xkcp/`](xkcp/) | Legacy Keccak-256 implementation and recorded build-tool sources |

Use `make setup` to provision pinned sources and tools. Setup validates recorded revisions and
refuses local upstream edits or unexpected commits. Upstream sources and their licenses stay
intact; project-owned adapters live in [`native/`](../native/README.md), while local and derived
fixtures live in [`vectors/`](../vectors/README.md).

A deliberate dependency upgrade must update the gitlink and associated pins/hashes together,
then run the affected checks. Generated dependency builds belong under ignored `build/`.
