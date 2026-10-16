# Ragnarök design

**Language:** Nim 2.2.12, ARC. **Target:** native Linux. **State:** protocol foundation;
full JAM execution, state transitions and validator operation remain future work.

Protocol target: Gray Paper 0.8.0; the Bandersnatch draft-text/reference discrepancy remains an explicit
[parity gate](../spec/graypaper-0.8.0.md).

## Architecture

Codecs and consensus-facing types live in `src/codec/`. Protocol logic remains native Nim. Private,
acyclic ARC owners retain immutable wire snapshots; borrowed paths use explicit lifetime contracts
and caller-owned storage. Default/failed tagged results carry no values or progress metadata.

`src/crypto/` composes domains and codecs around narrow maintained primitive ABIs. BoringSSL
provides Blake2b-256 and ordinary Ed25519; XKCP provides legacy Keccak-256. The release-designated ark-vrf 0.2.2
Bandersnatch Rust backend is isolated behind `native/bandersnatch/` and a typed Nim adapter.

`src/quic/` owns JAM identities, DER/framing checks, stream policy and lifetimes. A bounded POSIX
nonblocking UDP dispatcher drives the maintained LSQUIC/TLS bridge. No stream or connection creates
an OS thread. Optional RingVRF verification uses two workers and four total owned job slots.
`peer.nim` is the bounded CLI. The standalone `session.nim` module privately owns peer/stream
state, callbacks and retained mesh coordination; only lifecycle entry points are exported.

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
  schedules and ticket accumulator; chapter-5 canonical report judgment and offender sets;
  chapter-3 recent history, package dictionaries and optional accumulation-output belt peaks;
  chapter-10 fixed-core optional full guarantees and separate registration timestamps; chapter-12
  privileged-service roles, fixed core assigners and canonical always-accumulate service/gas dictionary.
  Chapter-13 activity statistics add E4 validator counters/service keys and natural core/service values;
  gas follows the accepted compact vector policy; the text discrepancy is documented. Chapter-12
  dictionary pairs now use E4/E8.
  Chapters 14/15 add fixed epoch rings of ordered ready reports/dependency sets and accumulated
  package sets, with retained report children and canonical hash ordering. Chapter 16 adds the
  ordered service/output-commitment sequence. C(255, service) metadata adds fixed version-zero
  account fields as independent values. Storage/preimage mappings add explicit key domains and raw
  values; opaque retained values need no original storage keys. Request histories add E4 length/hash
  keys and fixed tagged 0..3-slot values; top-length namespace admissibility remains a parity gate.
  Fourteen unmodified published full-state mappings reproduce their roots independently and natively;
  exact typed chapter captures now compose with typed service records or explicit opaque captures
  into immutable whole mappings; fourteen complete published mappings reproduce their roots.
  Numeric-width/domain resolution, proofs and persistence remain future work.
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
chapters 1–16 now have typed serializers; chapter 13 follows the
[accepted compact gas policy](../spec/state-statistics.md). Service-account metadata is implemented.
Storage/preimage and request-history keyed entries are implemented. Request-length namespace
policy also needs clarification. The [full-map root audit](../spec/state-roots.md) verifies fourteen
published maps and records the dictionary migration and accepted compact statistics gas.
[Typed composition](../spec/state-composition.md) now enforces exact component extents, common
profiles, parent budgets and duplicate rejection. The [width investigation](../spec/state-widths.md)
supports the implemented C(12) E4 service/E8 gas and C(13) E4-key migration. The maintainer accepts
compact C13 gas as used by the vectors, with no fallback. The
[request-namespace question](../spec/state-clarifications.md) remains parked for 0.8.1/0.8.2 review;
its [local witnesses](../spec/request-namespace.md) and pending test remain. Further implementation
scope is selected separately; the parked question still qualifies full M1 state parity.
The bounded C.1/C.2 framing baseline is implemented within its documented schema scope. The
[M1 coverage audit](codec-coverage.md) distinguishes framing from those remaining state and
validation responsibilities. Current network tests use bounded controlled topologies; general
multi-target networking and independent JAM-stack interoperability remain open. Full-ring capacity
sizing and dependency/security audits remain necessary. The exceptional-point Ed25519 acceptance policy requires an explicit normative
decision and focused independent tests before consensus-sensitive verification is finalized.

Work proceeds in maintainer-authorized bounded increments. The language decision and its full
evaluation are archived in the `language-selection` release; comparison code is outside the active tree.
