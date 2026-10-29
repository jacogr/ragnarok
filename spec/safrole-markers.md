# Safrole epoch and winning-ticket markers

Target: Gray Paper **0.8.0**, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/safrole.tex` equations `epochmarker` and `winningticketsmarker` (section The Markers).
Vector revision remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`; no pins advance.

## State-derived immutable markers

`src/state/safrole/markers.nim` derives a complete expected pair from exact serialized parent and
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

## Read-only header context

`src/state/marker_state.nim` exposes `validateSafroleHeaderMarkers`. It accepts retained immutable
parent/staged full-state snapshots and an owned structurally decoded unsigned header. Parent
C(4)/C(6)/C(11) provide the original contest, entropy and slot; staged C(4)/C(11) provide posterior
pending keys and recorded target time. Staged time must equal the header slot. Missing chapters
return `MissingState`, default snapshots `Uninitialized`, malformed exact chapters `InvalidState`,
and a default header `InvalidHeader`. Both C(4) byte ceilings precede dynamic copies.

After derivation, comparison uses marker owners selected from the same retained header. No
write, store-root calculation or native cryptographic operation is performed. Every snapshot value,
root and historical owner survives success and refusal. The second native suite checks all 33
published pairs through decoded unsigned headers and authored missing/truncated/suffixed input,
slot, marker mismatch, resource and lifetime cases; refusing hash instrumentation observes zero
calls throughout validation. Source rotation/admission/time projections are supplied from vectors,
not claimed as transition execution by this component suite.

These complete-map snapshots are for full-node execution. They neither require a shared full/light
schema nor establish a complete root for a partial light-node map. Owned header marker primitives
remain reusable by future light-node tracking with its own verified context contract.

## Completed scope and next work

Marker derivation and contextual validation complete this PR's bounded scope. This branch was
stacked on #16; the dependency is now merged into master. [Safrole header entropy-VRF and author/sealing authentication](safrole-authentication.md) now
implements the next increment. Whole-Safrole coordination must still authenticate
stage lineage and publish canonical state only after all checks succeed. This validator alone
neither authenticates header signatures/VRF outputs nor executes a complete block transition.
