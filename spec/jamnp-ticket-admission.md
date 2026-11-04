# Finality-bound Safrole ticket admission (in progress)

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE131/132, and authorized
Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`, Safrole ticket proof and lottery rules.

Accept exactly one E4-framed payload of use-epoch(E4), attempt(E1) and RingVRF proof(784),
followed by FIN. The pinned network attempt domain is0/1; also enforce the GP attempt ceiling
for the actual pending population. A valid response is bare FIN. Both transport participants
must be authenticated validators; packet parsing and acknowledgment alone grant no GP authority.

Verification uses an explicitly finalized complete snapshot in the distribution epoch (one
before the advertised use epoch), with that epoch's effective connectivity and current local
clock/window. Never substitute best-head state or peer finality claims. Check the exact C4 root,
C6 entropy[2], `jam_ticket_seal` transcript, setup domain3*cores and full784-byte proof. Proxy
selection is the final four verified VRF-output bytes as big-endian u32 modulo next-population.
CE131 targets that next-roster proxy; CE132 comes from that proxy and targets a current validator.

Typed sealed results enter a bounded detached pending-ticket owner only after exact uncancelled
CPU collection and fresh epoch/live-stream checks. New epoch, finalized inclusion and context
replacement retire obsolete entries. Done/cancellation retain the existing exact Services lease
until collection or joined close; foreign tickets cannot release it. Native callbacks copy fixed
bytes only. Full/light state remains separate. No ticket acknowledgment mutates canonical C4 or
claims block inclusion. Timed proxy broadcasting and local production follow this admission layer.

Completion witnesses: real RingVRF positives, malformed/proof/context/attempt/epoch/role/proxy
failures; actual TLS bare-FIN admission; finalized versus unfinalized sources; duplicate/bounded
retention, stale epoch and peer closure before Done collection; exact shutdown/foreign lease and
ARC ownership. A small clock/worker/stream model must kill the removed collection guard and have
an independently replayed reachable witness; do not report a model-only counterexample as a bug.

Implementation boundaries:

- `ticket_packet` accepts exactly789 payload bytes; the fixed read route validates all four E4
  length octets while each native callback still copies at most104 bytes.
- `ticket_validation` captures detached C4/C6/C8/C9 facts from explicit full-state finality.
  Source reuse binds both selected block identity and posterior state root. Its stable context
  hash includes epoch geometry, ring, entropy and ordered rosters, excluding advancing inclusion.
- `TicketVerificationJob` binds a private real verifier capability. The existing capacity-one
  proof worker and Services RPC pause/collection lease own it. Ordinary proof-worker users do
  not acquire a RingVRF linkage requirement merely by importing the new typed operation.
- `PendingTicketPool` retains at most twice the actual next-roster population, with a fixed
  maximum2046 immutable proof owners. Finalized inclusion retires entries; failed verification
  exposes its genuine chapter, hash or RingVRF child cause without an accepted payload.

The focused `jamnp_ticket_collection` model abstracts one genuine proof and the existing worker
phases; it does not model the2046-entry capacity, cryptographic implementation, roster parsing,
locks or ticket namespace reuse. Its53-state safety base passes (about0.006s and2.61MiB peak RSS on the local host) and the expired-Done witness is
reachable. Removing host freshness, public-pool freshness, or observed stream liveness produces
six-state counterexamples (three guards killed out of three). Sequential and four-worker checks
agree. A separate `Fix=false` unprotected-design control also fails; it is not a claim about a
previously shipped defect. No new production bug is claimed from the model alone. Runtime
replays cover expiry after Done, finalized-included acknowledgment after expiry, public retention
with a fresh expired clock, and exact native stream cancellation before collection.
