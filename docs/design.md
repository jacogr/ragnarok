# Ragnarök design

**Language:** Nim 2.2.12, ARC. **Target:** native Linux. **State:** protocol foundation;
full JAM execution, state transitions and validator operation remain future work.

Protocol target: Gray Paper 0.8.0; the Bandersnatch draft-text/reference discrepancy remains an explicit
[parity gate](../spec/graypaper-0.8.0.md).

## Architecture

Codecs and consensus-facing types live in `src/`. Protocol logic remains native Nim. Private,
acyclic ARC owners retain immutable wire snapshots; borrowed paths use explicit lifetime contracts
and caller-owned storage. Default/failed tagged results carry no values or progress metadata.

`src/crypto/` composes domains and codecs around narrow maintained primitive ABIs. BoringSSL
provides Blake2b-256 and ordinary Ed25519; XKCP provides legacy Keccak-256. The release-designated ark-vrf 0.2.2
Bandersnatch Rust backend is isolated behind `native/bandersnatch/` and a typed Nim adapter.

`src/quic/` owns JAM identities, DER/framing checks, stream policy and lifetimes. A standard-selector
nonblocking UDP dispatcher drives the maintained LSQUIC/TLS bridge. No stream or connection creates
an OS thread. Optional RingVRF verification uses two workers and four total owned job slots.

All upstream sources are pinned submodules. Project-owned bridges contain primitive/transport
integration, not hidden JAM codecs, PVM or state logic. Native dependency sources remain pristine.

## Implemented foundation

- General naturals, fixed unsigned widths, bounded bytes/sequences, optional/work variants,
  preimage/ticket/guarantee extrinsics, work digests, complete reports and assurances.
- Checked borrowed operations, atomic failure behavior and immutable owner-bound extraction.
- Blake2b-256, Ed25519, Keccak-256, release-reference contextual VRF/RingVRF and report/assurance transcripts.
- Authenticated CE 143 peers, retained multi-peer listeners, IPv6 arbitration/reconnect,
  backpressure, cancellation, deadlines, peer-loss/admission recovery and bounded proof offload.
- Official/vector references, native fuzz/selftests and Linux correctness/lifecycle CI.

See [M1 codec progress](m1.md) for the remaining grouped codec increments.

## Outstanding work

PVM execution, complete state transitions, block import, consensus and availability processing,
full extrinsic/state coverage and production validator operation are not implemented. Current
network tests use bounded controlled topologies; general multi-target networking and independent
JAM-stack interoperability remain open. Full-ring capacity sizing and dependency/security audits
remain necessary. The exceptional-point Ed25519 acceptance policy requires an explicit normative
decision and focused independent tests before consensus-sensitive verification is finalized.

Work proceeds in maintainer-authorized bounded increments. The language decision and its full
evaluation are archived in the `language-selection` release; comparison code is outside the active tree.
