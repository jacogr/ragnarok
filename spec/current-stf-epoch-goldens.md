# Whole-map STF goldens for epoch transitions and ticket admission

Scope: three authored complete-state chains, twenty-two actual candidate transitions under the
tiny profile (two cores, six validators, twelve-slot epochs, ticket cutoff10, at most three tickets
per block). Pins remain Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, Draft35 Thin
v1/ark-vrf 0.6.0 and JAM vectors `23061ae1f9b51171c01387e7dde0f15794c98e24`.

## Complete original inputs and independent expectations

`tests/fixtures/current-stf-epoch.json` freezes one original complete parent, fourteen attributed
RingVRF inputs, a staging-ring commitment and independent successor roots/checkpoint hashes.
The parent is authored before child signing through public test constructors; it contains all
sixteen globals, current 105-byte service metadata and explicit storage/preimage/request namespaces.
It uses six distinct public fixture scalars 1..6, distinct Ed25519 identities and different active,
pending, staging and previous roster orders. These distinguish role swaps and ordinal mistakes.
Existing parent fixtures, published traces and historical sources remain unchanged.

The independent reference `tests/current_stf_epoch_oracle.py` calculates:

- mathematical ticket O/output under `jam_ticket_seal || eta2 || E1(attempt)`, strict score order,
  disjointness from the old contest, the ceil(2*epoch/population) attempt bound and top-epoch union;
- one contest reset on epoch crossing while admitting new tickets against the rotated pending
  ring and historical entropy; newly submitted tickets remain in the new contest;
- outside-in winner permutation and its cutoff marker, with complete id/attempt tuples;
- ticket schedule selection only for an adjacent crossing from a saturated parent in the tail;
  skipped-tail, incomplete-contest and multi-epoch-skip paths select hashed fallback keys;
- pending←staging, active←old pending, previous←old active, preserving full336-byte records and
  the unchanged original staging chapter;
- exact epoch markers from old eta0/eta1 and new pending key pairs, independently signed Thin
  seal/entropy credentials and the author index in the posterior active roster;
- one historical entropy rotation and one statistics rotation on each crossing, including a
  jump over an empty epoch, with submitted ticket counts credited to the actual author;
- every other complete-map chapter, including queue-indexed authorizer pools, corrected recent
  history, actual variable-length sealed-header hashes, MMR carries and unchanged service entries.

All expected headers, body bytes and complete successor checkpoints exist before the registered
native build/run. A later reference parent always comes from the previously **calculated** map;
native successor observations never feed the reference. The shared chapter equations preserve
the prior thirty empty-body/guest-effect goldens byte-for-byte.

### Ring proof boundary

The fourteen fixed membership proofs and two ring commitments are native input witnesses,
generated explicitly with the qualified ark-vrf v1 backend and the unchanged public SRS. The
normal corpus never regenerates them. The first twelve witness scalars1..6 with attempts0/1 in
the initial pending ring; the last two witness scalar1/attempt2 and scalar2/attempt3 in the
staging ring. Their output points and scores are independently reproduced mathematically.
The native candidate must verify every actual Ring proof in its exact roster/entropy domain.
This reference does not independently implement or audit the Ring/KZG membership equations.

## Chain coverage

| Chain | Slots | Distinguishing behavior |
| --- | --- | --- |
| Saturated tail | 2,3,4,5,10,11,12,13,36,37 | Twelve admitted scores, winner marker at10, ticket sealing at12/13, new contest admission, then multi-epoch fallback |
| Skipped tail | 2,3,4,5,12,13 | Full contest cannot select ticket sealing when the parent skipped the tail |
| Incomplete tail | 2,3,10,11,12,13 | Six-score contest produces no winner marker and selects fallback at crossing |

Together these admit 36 tickets across sixteen nonempty ticket extrinsics and include four
epoch-crossing blocks, one of which skips an epoch. The two ticket-sealed blocks use the selected
ticket's scalar/attempt and the exact
posterior active ordinal. Multi-epoch skipping rotates history/statistics once from the original
parent, without inventing intermediate empty-block transitions.

`tests/native/current_stf_epoch_driver.nim` independently constructs the original map and child
inputs, runs each actual `prepareCurrentCandidate`, qualifies all current globals and supplied
services, installs the result, and preserves retained original snapshots. The registered
`current_stf_epoch_corpus` uses the normal checked ARC/Clang non-LTO builder, production libraries,
fixed fixture hashes, request hashes and full expected/observed byte comparison.

Ten correctly sealed native negative controls select exact nested Safrole reasons and preserve
the original complete map: invalid attempt, malformed membership proof, reversed score order,
duplicate ticket, a ticket at the cutoff, an old-ring proof after rotation, three missing epoch
markers and a missing required winner marker. Positive candidates follow those refusals on the
same original chain; failure never becomes an accepted empty prefix.

Observed locally on macOS ARM64 checked ARC/Clang release: the registered native corpus passed
all twenty-two transitions and ten exact refusal controls. All twenty-four affected Python
reference/harness checks and verification inventory passed. The refactored shared equations
reproduced the exact passing output hashes for the prior thirty whole-map transitions, whose
native sources, dependencies and build profile are unchanged. Pinned formatting is checked with
this review unit; exact-head Linux CI is separate.

The equations follow pinned `safrole.tex`, `header.tex`, `statistics.tex`, `authorization.tex`,
`recent_history.tex`, `merklization.tex` and empty-work accumulation. These cases have no offenders,
reports, assurance/dispute extrinsics or guest execution. Resized populations, contested/offender
rotation, top-contest eviction and broader admission/host behavior need further whole-map cases.
General JAM STF parity and the separately recorded published signed-trace limitations remain open.
Production code, pins and the `AmbiguousPrivileges` guard are unchanged.
