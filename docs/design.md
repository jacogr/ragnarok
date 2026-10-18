# Ragnarök design

**Language:** Nimony 0.6.3 (pinned nightly), ARC. **Target:** native Linux. **State:** protocol foundation;
full JAM execution, the complete state-transition pipeline and validator operation remain future work.

Protocol target: Gray Paper 0.8.0; the Bandersnatch draft-text/reference discrepancy remains an explicit
[parity gate](../spec/graypaper-0.8.0.md).

## Architecture

Codecs and consensus-facing types live in `src/codec/`. Protocol logic remains native Nim. Private,
acyclic ARC owners retain immutable wire snapshots; borrowed paths use explicit lifetime contracts
and caller-owned storage. Default/failed tagged results carry no values or progress metadata.

`src/state/` owns the in-memory serialized-state store: atomic write batches publish complete
immutable snapshots and recompute roots through the existing Merklization implementation.
See [the storage contract](../spec/state-store.md). Native replay verifies seven published pre/post mapping pairs; this is not state-transition
execution.

`src/state/authorization.nim` implements the first bounded non-PVM transition: authorization
pool advancement from validated guarantee projections and post-accumulation queues. Its store
adapter atomically replaces C(1), preserving C(2) and unrelated entries. See
[the transition contract](../spec/authorization-transition.md); whole-block execution remains open.

`src/state/history.nim` adds parent-state-root correction, accumulation-output Keccak trees,
belt/super-peak advancement and bounded recent-history updates through the C(3) store adapter.
See [the history transition contract](../spec/history-transition.md) for scheduling and the
clarified hash-token notation; these components do not execute accumulation.

`src/state/entropy.nim` advances the fixed entropy accumulator/history and timeslot, with one
rotation on epoch crossing and atomic C(6)/C(11) publication. See
[the transition contract](../spec/entropy-transition.md); VRF authentication and the rest of Safrole
remain separate stages.

`src/state/validators.nim` plans epoch roster rotation and complete offender-record nulling from
immutable snapshots. `src/state/validator_state.nim` recomputes the profile-bound pending ring root
and atomically publishes C(4)/C(8)/C(9), preserving schedules and accumulators.
[The contract](../spec/validator-rotation.md) defines pre-time-advancement ordering; complete Safrole
ticket/schedule/marker execution remains open.

`src/state/ticket_admission.nim` verifies Safrole RingVRF tickets, checks eligibility/order/
disjointness and selects the bounded posterior accumulator. [Its first-slice contract](../spec/ticket-admission.md)
returns an immutable C(4) candidate. `src/state/ticket_state.nim` atomically publishes it after
checking staged entropy/time inputs. `src/state/sealer_schedule.nim` selects the current schedule
from separate parent/staged C(4), posterior active keys and entropy, covering outside-in tickets
and fallback generation. `src/state/sealer_state.nim` retains the parent snapshot and atomically
publishes only C(4) after checking staged C(4)/C(6)/C(8)/C(11). The
[schedule contract](../spec/sealer-schedule.md) defines this substep's rollback boundary; header
marker derivation/comparison now lives in `src/state/safrole_markers.nim`. It binds parent
entropy/contest and posterior pending keys to immutable expected header fields. See
[the marker contract](../spec/safrole-markers.md). `src/state/marker_state.nim` checks decoded
unsigned headers against retained parent and staged snapshots without writes or hashing. Entropy-VRF,
seal authentication and complete block execution remain open.

`src/crypto/` composes domains and codecs around narrow maintained primitive ABIs. BoringSSL
provides Blake2b-256 and ordinary Ed25519; XKCP provides legacy Keccak-256. The release-designated ark-vrf 0.2.2
Bandersnatch Rust backend is isolated behind `native/bandersnatch/` and a typed Nim adapter.

`src/quic/` owns JAM identities, DER/framing checks, stream policy and lifetimes. A bounded POSIX
nonblocking UDP dispatcher drives the maintained LSQUIC/TLS bridge. No stream or connection creates
an OS thread. Optional RingVRF verification uses two workers and four total owned job slots.
`peer.nim` is the bounded CLI. The standalone `session.nim` module privately owns peer/stream
state, callbacks and retained mesh coordination; only lifecycle entry points are exported.

An optional `src/telemetry/` exporter sends JIP-3 registration, status and correlated outgoing connection
events, incoming handshake lifecycles and observed incoming/outgoing disconnections. Incoming TLS callbacks
borrow a fixed 64-slot correlation table and exporter through engine teardown; saturation only
loses observations. A separate 16-slot admitted-peer table retains copied identities until an
observed close; engine destruction does not fabricate disconnections. The exporter owns one nonblocking TCP socket
and a fixed send buffer, with no additional threads. Retained mesh role engines share one exporter
and event-ID sequence; status counts their single pinned remote peer once across duplicate connections.
An explicit JIP-4 file supplies network metadata; it does not initialize chain execution.
See [telemetry scope and limits](../spec/telemetry.md).

All upstream sources are pinned submodules. Project-owned bridges contain primitive/transport
integration, not hidden JAM codecs, PVM or state logic. Native dependency sources remain pristine.

## Full and light node modes

The client will support full and light operation selected by a command-line mode flag. Startup
will choose the corresponding mode-specific database; full and light data/schema requirements
must remain separate. In-memory backends may also differ, sharing only operations with matching
semantics. No database backend or mode flag is implemented by the current storage increment.

`src/state/store.nim` is a complete-map in-memory execution store. Light-node verified roots,
partial state and proofs require a separate appropriate contract; hashing partial data through
this complete-map calculator cannot establish the full state root. Codecs and Merklization
primitives remain shared, with mode selection at the application boundary.

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
policy has a merged upstream correction awaiting a compatible pinned upgrade. The [full-map root audit](../spec/state-roots.md) verifies fourteen
published maps and records the dictionary migration and accepted compact statistics gas.
[Typed composition](../spec/state-composition.md) now enforces exact component extents, common
profiles, parent budgets and duplicate rejection. The [width investigation](../spec/state-widths.md)
supports the implemented C(12) E4 service/E8 gas and C(13) E4-key migration. The maintainer accepts
compact C13 gas as used by the vectors, with no fallback. The
[request-namespace fix](../spec/state-clarifications.md) is merged upstream (#542), awaiting a
compatible release/vector upgrade; its [local witnesses](../spec/request-namespace.md) and pending
test remain against 0.8.0. Further implementation
scope is selected separately; the pending upgrade still qualifies full M1 state parity.
The bounded C.1/C.2 framing baseline is implemented within its documented schema scope. The
[M1 coverage audit](codec-coverage.md) distinguishes framing from those remaining state and
validation responsibilities. Current network tests use bounded controlled topologies; general
multi-target networking and independent JAM-stack interoperability remain open. Full-ring capacity
sizing and dependency/security audits remain necessary. The exceptional-point Ed25519 acceptance policy requires an explicit normative
decision and focused independent tests before consensus-sensitive verification is finalized.

Work proceeds in maintainer-authorized bounded increments. The language decision and its full
evaluation are archived in the `language-selection` release; comparison code is outside the active tree.
