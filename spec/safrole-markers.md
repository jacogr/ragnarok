# Safrole epoch and winning-ticket markers

Target: Gray Paper **0.8.0**, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/safrole.tex` equations `epochmarker` and `winningticketsmarker` (section The Markers).
Vector revision remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`; no pins advance.

## State-derived immutable markers

`src/state/safrole_markers.nim` derives a complete expected pair from exact serialized parent and
staged posterior C(4), retained parent entropy, advancing parent/target slots, chain epoch/tail
parameters and independent finite chapter/marker ceilings. Chapter parsing is exact; neither
contest is sorted or repaired. Defaults and failures carry no partial markers. Success owns both
marker encodings through private immutable codec owners. Extracted owners outlive caller inputs.

- Every epoch crossing, including skipped epochs, requires an epoch marker. Its entropies are
  **parent eta[0] and eta[1]**, not the updated accumulator/history. Validator pairs come from
  **posterior pending** records, preserving count, order, null keys and repeats. This differs from
  fallback schedules, which use posterior active keys and posterior eta[2].
- Within an epoch, the epoch marker must be absent.
- A winner marker exists exactly when the epoch is unchanged, the parent slot is before the tail,
  target is at/after its start, and the **parent** accumulator is saturated to one epoch of tickets.
  Its sequence is outside-in Z, preserving every identifier and original E1 attempt. Newly admitted
  staged tickets cannot create eligibility or change this sequence.
- An epoch crossing never emits a winner marker, even when it crosses the deadline. A parent already
  in the tail does not emit it again. Unsaturated contests require absence.
- Individual exact output extents must fit `maxMarkerBytes` before allocating output sequences.
  Chapter ceilings are checked before dynamic copies. The native epoch/marker extent is proved
  before multiplication/narrowing. Allocation failure retains the client's fail-stop policy.

`validateSafroleMarkers` compares initialized marker owners, including exact presence, both
entropies, count, every key pair and every full winning ticket. It returns a typed epoch/winner
mismatch. A default expected pair or actual owner never stands for initialized absence. This
performs no hashing, state writes, VRF authentication or seal verification.

## Evidence and reproduction

The `safrole_markers` Hastur profile compares complete marker bytes for all **33 accepted** pinned
Safrole cases (15 tiny, 18 full). `tests/safrole_marker_fixtures.py` transports the supplied output
fields through independent encoding equations and validates every source blob hash. It contains no
marker eligibility, entropy selection or ticket permutation algorithm. Published coverage includes
presence/absence, roster padding/resizing, deadline crossings and skipped epochs. Native corruption
checks bind both entropy roles, Bandersnatch/Ed25519 keys, ticket identifiers and attempts; exact and
one-short output budgets, invalid slots, suffixes and scoped 1,000-cycle ARC retirement are checked.
Four compiler privacy probes and two runtime extraction probes protect results and marker owners.

Run `make check-modules check-unit check-failures check-guards check-python`. Prepared fixture
hashes, native ARC evidence and reports live under ignored `build/tests/`. These are component
projections, not complete Safrole execution or seal authentication.

## Remaining work in this PR

Add read-only validation of structurally decoded unsigned-header markers against retained parent
and staged working-map snapshots. Check required chapter/time handoff, immutable history and all
published marker projections, then round out authored eligibility/ownership boundary cases.
This branch needs PR #16. Complete Safrole coordination, entropy-VRF and seal authentication remain
separate increments; full/light execution must not share a misleading partial-map root contract.
