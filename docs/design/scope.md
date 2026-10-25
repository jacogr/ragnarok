# Implementation scope

[Design overview](../design.md). This records milestone scope; feature-specific progress belongs
in the relevant `spec/` contract.

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
  keys and fixed tagged 0..3-slot values; both reserved upper lengths reject under the adopted domain.
  Fourteen unmodified published full-state mappings reproduce their roots independently and natively;
  exact typed chapter captures now compose with typed service records or explicit opaque captures
  into immutable whole mappings; fourteen complete published mappings reproduce their roots.
  Independent current-pin whole-state parity and production-scale sizing remain separate;
  complete-map memory/disk persistence is implemented within its bounded contracts.
- Checked borrowed operations, atomic failure behavior and immutable owner-bound extraction.
- Blake2b-256, Ed25519, Keccak-256, release-reference contextual VRF/RingVRF and report/assurance transcripts.
- Authenticated CE 143 peers, retained multi-peer listeners, IPv6 arbitration/reconnect,
  backpressure, cancellation, deadlines, peer-loss/admission recovery and bounded proof offload.
- [Native PVM execution](../../spec/pvm-execution.md), supported refinement/accumulation hosts and
  [selected finalized successors](../../spec/pvm-state-successor.md), with explicit parity gates.
- Authenticated block admission and supported disputes/Safrole/assurance/report stages, bounded
  accumulation driving and [state-owned composition](../../spec/accumulation-completion.md).
- Complete-map memory and [durable disk state](../../spec/disk-state-store.md), exact-parent
  canonical/RPC publication, bounded local history/explicit finality recovery and independently
  [trusted checkpoint imports](../../spec/application-recovery.md).
- [Bounded successive child downloads](../../spec/application-download-progress.md) from explicit
  pinned loopback peers, with retained connections, managed execution, confirmed partial progress
  and durable restart. RPC exposes actual retained heads, roots, sealed headers and parents.
- Official/vector references, native fuzz/selftests and Linux correctness/lifecycle CI.

See [M1 codec progress](../m1.md) for baseline coverage and the next scope boundary.

## Outstanding work

Whole-block JAM/STF parity, complete admission/validation policy, consensus/fork choice,
production availability distribution/retrieval and
validator operation remain open. Native PVM execution, supported state transitions, bounded
signed-child import and durable complete-map publication are implemented foundations; their
feature contracts retain the precise limitations and independent evidence.

The reviewed T(state) serialization layouts are implemented, including current supervised
metadata and the adopted request bound. [Current serialization status](../../spec/jam-serialization-status.md)
records exact pins, current byte widths, whole-map qualification and the remaining
independent unmodified current-schema source/mapping/root evidence requirement.
Older namespace-upgrade paragraphs and skips are historical, not active backlog.
The bounded C.1/C.2 framing baseline is implemented within its documented schema scope. The
[M1 coverage audit](../codec-coverage.md) distinguishes framing from those remaining state and
validation responsibilities. Full/light startup and separate paged databases are implemented
within their [bounded application contract](../../spec/storage-paged-application.md).
Current network tests use bounded controlled topologies; production peer discovery,
non-loopback download bootstrap and independent JAM-stack interoperability remain open. Full-ring capacity
sizing and dependency/security audits remain necessary. ZIP215 verification was adopted
in the [current crypto upgrade](../../spec/crypto-zip215-upgrade.md); that qualified primitive
evidence remains separate from full-client consensus correctness.

Work proceeds in maintainer-authorized bounded increments. The language decision and its full
evaluation are archived in the `language-selection` release; comparison code is outside the active tree.
