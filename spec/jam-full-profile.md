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
