# Full-profile fuzz execution

Authority remains GP`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`.
Every AppendixB parameter comes from the pinned definitions, including341 cores,
600 slots, canonical deposits/gas/rotation and the500-slot ticket tail. The seed
contains1023 full validator records per roster and the complete600-slot rings.

Two independently authored sparse/saturated authorization-pool chains calculate
all341 pool rows, complete queue contents, entropy, clock, history/MMR, output
log and1023-row statistics. Full checkpoint bytes and roots are calculated before
native execution; unchanged service namespaces remain in every complete map.
A pinned ark-vrf1023-member KZG commitment is explicitly attributed as a seed
input witness. No native STF output supplies an expected state or signature.
Original tiny references, fixtures, protocol pins and toolchains remain unchanged.

The finite test policy declares full geometry before state decoding. GP checks
remain in the actual backend. Shared test wire helpers take explicit limits;
the real target receives `JAM_FUZZ_SPEC=full` and full configured Parameters.
Unmodified upstream minifuzz receives its own explicit `--spec full` selection.
Strict complete-message/map comparisons, mismatch controls and owned process
cleanup apply equally to tiny and full profiles.

Observed verification:18 native full-profile imports,35 existing Tiny guest
imports, and actual upstream/full-target replay of2 sessions/18 imports/44 exact
exchanges passed. The real mismatch control, backend unit suite, focused Python
checks, formatting, semantic compilation and inventory passed. Nonempty
full-profile admission and guest effects follow in the next bounded layer.

## Nonempty reports and guest effects

The next independent full-profile corpus uses1023 distinct Bandersnatch points
and deterministic distinct Ed25519 public keys. The fallback schedule is derived
from the actual seed entropy; each selected author signs with its own known
scalar. An attributed pinned-crypto ring commitment is seed input only.

At core340, two assigned guarantors admit a real nonempty work report. Its
43-byte availability bitfield is signed by683 distinct validators, satisfying
the strict full-population quorum. A684-vote sibling precedes original-last
replay; the independently calculated sibling differs only in header history
and vote statistics. Three chains cover storage creation/yield, panic rollback,
and checkpoint-then-panic retention, including gas, account footprints, package
history, MMR and the complete state map. All original fixtures remain unchanged.
The same source-owned corpus also supplies actual upstream minifuzz sessions
under the full canonical host profile.

Observed nonempty validation:12 full guest/sibling imports and18 unchanged full
baseline imports passed with checked ARC/Clang LTO. Actual upstream minifuzz
passed3 sessions,12 imports and39 exact exchanges, including the real mismatch
control. Focused Python and inventory checks passed. Runtime/native sources
remain identical to the preceding verified full-profile layer.
