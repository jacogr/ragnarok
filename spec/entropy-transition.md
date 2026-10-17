# Entropy and timeslot progression

This bounded execution slice targets Gray Paper **0.8.0**, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/safrole.tex` sections Timekeeping and
Sealing and Entropy (`timeslotindex`, `entropycomposition` and the accumulator/rotation equations),
plus `text/header.tex` strict parent-slot ordering. Existing source SHA-256 pins cover both chapters.
No dependency revision changes. Fixed C(6)/C(11) serialization remains in
[state-safrole.md](state-safrole.md).

## Transition contract

`src/state/entropy.nim` provides `advanceEntropyTime` over copied fixed values:

- Reject a zero epoch length before division and require the target slot to exceed the prior slot.
- Hash exactly `old_eta[0] || supplied_entropy_vrf_output` with Blake2b-256 (64 input bytes).
  There is no domain prefix, slot/proof encoding, count framing or Blake2b-512 truncation.
- If `target div epochSlots > previous div epochSlots`, set posterior history to
  `[old_eta[0], old_eta[1], old_eta[2]]`. Otherwise preserve `[old_eta[1], old_eta[2], old_eta[3]]`.
  Rotation happens **once per accepted block crossing**, not once per skipped epoch. History uses
  the old accumulator, never the freshly hashed one.
- Return the new accumulator/history and target timeslot together in a checked success result.

`EntropyInput` distinguishes supplied VRF output from stored entropy words. Its public constructor
is not a proof of authentication. The caller must already authenticate the entropy VRF against
its proper author/context; raw proof bytes must not be substituted for the output hash. The
published Safrole schema supplies this same `Y(H_v)` boundary. Wall-clock admission, block seals,
validator rotations, ticket processing, epoch/winner markers and full Safrole execution are
outside this slice. No acceptance of a future block is implied by these deterministic equations.
The chain profile supplies explicit positive `EpochSlots` (tiny 12, full 600); the arithmetic API
does not infer a profile or narrow that uint64 length to the slot's uint32 width.

## Atomic working-state publication

`advanceEntropyTimeState` requires explicit C(6) entropy and C(11) time entries. It checks their
exact 128-/4-byte lengths **before copying** and decodes through the existing fixed codecs.
Missing, truncated or suffixed state is a typed failure, never silently padded or treated as genesis.
It computes privately, serializes both posterior entries and submits a single atomic two-write
store batch. A budget or hash failure changes neither entry nor the store head; retained snapshots
and unrelated values stay valid. The minimum successful write-payload budget is **132 aggregate
bytes**, in addition to a two-write allowance and the independent complete-map/node policies.

The pure transition has fixed-size stack/value storage and performs exactly one hash on valid
input; no input-dependent allocation, slot addition or repeated epoch loop is required. Unsigned
division/comparison avoids slot-wrap and epoch-multiplication overflow, including maximum values.
The adapter allocates only fixed chapter payloads before the store's separately bounded batch/root
work. Ownership is acyclic ARC; allocation failure remains fail-stop.
Default/failed result alternatives carry a reason only, without updated values or progress.
Private discriminators/payloads and checked success access protect both generic result families.

The adapter is for a private complete-map working store. A future block executor must coordinate
all Safrole and other subsystem changes and publish only after every block stage succeeds.
This two-chapter commit alone is not a complete block transition or full-state commitment fixture.

## Published and authored evidence

Twelve unchanged Safrole vector sources at
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` are pinned with exact Git-blob SHA-256 values:
for each tiny/full profile, `enact-epoch-change-with-no-tickets-{1,2,3,4}.json`,
`skip-epochs-1.json` and `skip-epoch-tail-1.json`. The family README and ASN schema are also pinned.
Ten sources succeed; two reject repeated slots (`bad_slot`) with unchanged posterior state.

These are **entropy/time projections**, not claims to execute the complete Safrole STF. The native
suite compares exact supplied pre/post entropy bytes and time values, verifies both store entries,
keeps unrelated state intact and preserves historical snapshots. The helper transports supplied
fields and source provenance; it contains no entropy-rotation reference implementation.
An independent hashlib literal checks the 64-byte accumulator/output hash without obtaining its
expected digest from the production implementation.

Authored boundaries exercise epoch lengths 1/12/600/maximum uint64; zero-epoch rejection; same,
previous, next, skipped and maximum uint32 slots; no slot wrap; old-versus-new accumulator rotation;
sequential block composition and fixed-output independence from source mutation. Store tests use
an exact 132-byte aggregate write budget. A one-write budget or 131-byte payload ceiling refuses
the entire batch. Missing chapters, both fixed truncations/suffixes and default handles fail before
hashing. Observer tests refuse the first entropy hash and the first/later private commitment hash,
then verify rollback, recovery and old-snapshot stability. After warmup, 1,000 scoped cycles require
identical live allocator occupancy; this is workload-specific evidence rather than a general audit.

Four isolated runtime probes require the intended `AssertionDefect` for default/actual failure
extraction. Three compiler probes reject payload access, retagging and stored entropy passed as
new VRF output. Run `make check-modules check-python check-unit check-guards`; fresh reports and
source/ARC manifests live under `build/tests/`. Networking behavior is unchanged.

Next suggested bounded Safrole slice: validator-set rotation and offender filtering at epoch
boundaries. Ticket scheduling, ring commitments, seals/VRF authentication and marker validation
remain subsequent work. Existing [M1 specification checkpoints](state-clarifications.md) are unchanged.
