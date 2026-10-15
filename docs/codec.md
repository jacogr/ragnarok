# Codec APIs and ownership

Production modules live directly under `src/`. [Pinned normative contracts](../spec/codec.md)
and the other files under `spec/` define the exact wire rules, resource ceilings and failure precedence.

| Module | Scope |
| --- | --- |
| `natural.nim`, `fixed_unsigned.nim` | Canonical naturals and fixed unsigned widths 0..8 |
| `bounded.nim` | Bounded byte strings and homogeneous fixed-width sequences |
| `composite.nim` | Optional blobs, work-output variants and preimage extrinsics |
| `work_digest.nim`, `work_report.nim` | Complete nested work digests/reports |
| `tickets.nim`, `guarantees.nim` | Ticket records and immutable report guarantees |
| `work_package.nim` | Context, packed import references, input commitments, items and retained packages |
| `disputes.nim` | Ordered verdicts/judgments and culprit/fault evidence with immutable snapshots |
| `assurances.nim` | Ordered validator indices, fixed profile bitfields and signatures |
| `owned.nim`, `report_owned.nim` | Immutable ARC snapshots and owner-bound extraction |

Use nominal wrappers for protocol indices, hashes, widths and resource limits. General naturals
select `ok` before value/consumed fields; container/composite/owned APIs select their successful
error branch before accessing data or progress. Failure/default branches expose only a reason.
Nim variant field checks remain enabled in optimized builds.

Borrowed APIs require stable input/pools during the synchronous call. No detached span proves which
buffer it belongs to. For longer lifetimes, `decodeOwned*` snapshots copy and retain only the
validated prefix in private acyclic ARC storage. Metadata getters copy fixed fields/lengths;
`copyOwnedBlob` / `copyReportBlob` extract only through the matching owner. No public mutable wire
storage is exported. Last-owner destruction releases the snapshot automatically.

Encoder preflight validates all source fields, ordering, capacity, checked arithmetic and aliases
before committing any byte. Decoders consume one prefix; standalone consumers must separately
require full consumption. Assurances decode into fully owned fixed records supplied by the caller,
so no backing-buffer owner or release handle is needed for those fields. Tiny profile parameters
are 2 cores / 6 validators; full is 341 / 1023. Structural codec acceptance does not imply chain eligibility.

See `tests/test_codec.py`, `tests/test_work_report.py` and `tests/test_assurances.py` for independent
oracles, official vectors, boundary/fuzz inputs, alias probes and output atomicity checks.

[M1 progress and next coherent groups](m1.md) distinguish implemented codec families from remaining work.

[Disputes](../spec/disputes.md) document variable judgment counts, per-section ordering, the
published sample ordering discrepancy and the contextual checks left to state validation.

[Work-package inputs](../spec/work-package.md) cover standalone components, package-wide
count/dependency/footprint/gas limits and child owners that retain their parent snapshot.
