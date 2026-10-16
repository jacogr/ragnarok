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

- General naturals, fixed unsigned widths, strict Booleans, fixed/variable packed bitstrings,
  bounded bytes/sequences, canonical typed scalar sets/dictionaries, optional/work variants,
  preimage/ticket/guarantee/dispute extrinsics, work digests, complete reports, assurances,
  refinement contexts, work-package inputs, full/signing headers with epoch/winner markers,
  complete extrinsic/block composition, standalone availability specifications, deferred transfers
  and accumulation operands/input unions.
- State-key constructors, fixed trie node layouts and bounded roots over serialized key/value
  mappings; authorization pools/queues, entropy, staging/active/previous validator rosters and
  timeslot state serialization, plus chapter-4 pending validators, ring commitment, tagged sealer
  schedules and ticket accumulator; chapter-5 canonical report judgment and offender sets.
  Other state components, proofs and persistence remain future work.
- Checked borrowed operations, atomic failure behavior and immutable owner-bound extraction.
- Blake2b-256, Ed25519, Keccak-256, release-reference contextual VRF/RingVRF and report/assurance transcripts.
- Authenticated CE 143 peers, retained multi-peer listeners, IPv6 arbitration/reconnect,
  backpressure, cancellation, deadlines, peer-loss/admission recovery and bounded proof offload.
- Official/vector references, native fuzz/selftests and Linux correctness/lifecycle CI.

See [M1 codec progress](m1.md) for baseline coverage and the next scope boundary.

## Outstanding work

PVM execution, complete state transitions, block import, consensus and availability processing,
remaining state-component serialization, trie proofs/persistence and production validator operation
are not implemented. Root construction accepts already serialized state-key/value entries; state
chapters 1–2, 4–9 and 11 now have typed serializers. Next planned: chapter 3 recent history and
accumulation-output belt.
The bounded C.1/C.2 framing baseline is implemented within its documented schema scope. The
[M1 coverage audit](codec-coverage.md) distinguishes framing from those remaining state and
validation responsibilities. Current network tests use bounded controlled topologies; general
multi-target networking and independent JAM-stack interoperability remain open. Full-ring capacity
sizing and dependency/security audits remain necessary. The exceptional-point Ed25519 acceptance policy requires an explicit normative
decision and focused independent tests before consensus-sensitive verification is finalized.

Work proceeds in maintainer-authorized bounded increments. The language decision and its full
evaluation are archived in the `language-selection` release; comparison code is outside the active tree.
