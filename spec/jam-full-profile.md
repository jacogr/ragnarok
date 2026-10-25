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

## Full epoch and population transitions

The next corpus applies the same nonempty report/guest execution before two
full600-slot boundaries. Ordinary and skipped-tail paths retain their guest
storage while independently rotating entropy, fallback selection, complete
validator records and statistics. A deliberately reversed1020-member staging
population makes delayed activation and index changes observable: at the first
crossing it becomes pending, and at the second it becomes active. The previous
active1023-member population and its statistics remain complete.

The pinned crypto backend supplies only an attributed seed KZG commitment for
the staged ring. Expected signatures, variable epoch-marker bytes, per-block package-ring
advancement, history/MMR and every posterior map are independently calculated under
the unchanged GP pin before native or upstream replay. The existing baseline
and nonempty full-profile fixture hashes must continue to match exactly.

Full epoch replay exposed the former65536-byte adapter input cap: a valid
1020-member epoch requires65547 unsigned bytes. The primitive budget is now
131072 bytes, covering the combined full marker envelope; protocol signatures,
canonical encodings, dependencies and GP validation remain unchanged. ABI tests
cover exact-limit success, changed AD and over-limit output preservation.

Observed full-epoch validation:15 new complete-map transitions and the30 existing
full-profile guest/baseline imports passed with checked ARC/Clang LTO. Actual
upstream minifuzz passed2 sessions,15 imports and38 exact exchanges, including
its real mismatch control. Four production-profile Rust adapter tests,41 focused
Python tests, fresh formatting, replay-driver semantics and inventory passed.

## Full checkpoint ancestry and long sessions

A new reference independently executes a guest, resumes its exact slot4
checkpoint/header with honest slot3 parent membership, admits another report
whose lookup root is proved by that supplied child header, then imports28
signed descendants. Every complete map and the initial seed query remain exact
after both C3 history and the24-record ancestry retention window have elapsed.
The seed remains separately retained by the existing backend contract.

Explicit test seed headers are decoded only after selecting their trusted host
profile, preserving high full-profile author indices. All earlier Tiny checkpoint
cases remain consumers of this shared path.

A separately signed report targets an honest initial slot2 hash/slot record,
whose child3 header was not supplied. The real target must initialize and expose
the exact seed map, then close locally when the missing root evidence is needed.
It must not fabricate a consensus Error. A later fresh upstream minifuzz session
must still execute every valid descendant. Both aggregate and per-profile
reports require the independently planned local-refusal count to match actual
completion; omitted or substituted evidence cannot satisfy CI completeness.

Observed checkpoint validation:28 new full descendants,35 existing Tiny
checkpoint imports and12 full guest imports passed with checked ARC/Clang LTO.
Actual upstream minifuzz passed1 session,28 imports and60 exact exchanges, with
the honest missing-child-evidence local closure and real mismatch control.
Forty-nine focused Python tests, scoped pinned formatting, fresh replay-driver
semantics and inventory passed.
