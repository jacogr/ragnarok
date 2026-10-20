# Validator activity projection

## Scope and authority

Implement the validator component of GP 0.8.0 C(13), statistics.tex validator activity equations,
revision `07f041dabd073f9018b418e9ee72e79dd2185401`, SHA-256
`a8bee7c99853ed116fb7ed5e45e9977c7c323ad386e5a7e6c8cefba509f2d2a9`.
Retain the pinned [C(13) codec](state-statistics.md), including its fixed E4 validator counters.
This bounded layer implements a pure projection with explicit observations. It establishes no
signature, block, roster-transition or accumulation provenance and publishes no state entry.
The next layer must derive these observations from the exact authenticated block retained above
[last-accumulation timestamps](accumulation-times.md), then combine core/service activity before
writing C(13). No disconnected caller observations may become a certified block successor.

## Contract

Accept an initialized C(13) snapshot, initialized posterior active roster, explicit strictly advancing
parent/candidate times, nonzero epoch length, nominal author, ticket/preimage counts and preimage
byte sum, plus stable borrowed assurance indices and reporter Ed25519 keys. Assurance indices refer
to the parent active population; reporter membership refers to the posterior active roster. Repeated
assurance indices and reporter keys are existential, never repeated increments. Matching repeated
roster keys each receive one increment. Unknown reporter keys have no contribution.

First increment parent-current assurances; then either retain both epochs or rotate exactly once,
including skipped epochs. Rotation discards old previous, moves updated parent-current to previous,
and creates a zero current sized to posterior active. Without rotation the current population must
match posterior active. Finally add author blocks/tickets/preimages/bytes and per-validator reporter
membership to current. Check every E4 addition before it occurs; any overflow refuses the whole
projection, including an assurance overflow before rotation. Old-previous counters never increment.

Independent limits bound retained validator tuples, assurance observations, reporter observations
and posterior-validator/reporter comparisons. Check all extents and indices before scratch/result
allocation. Maxima are policy only, never allocation requests. No hashing, map mutation, C(13)
encoding or copying of stale core/service statistics occurs. Opaque acyclic ownership retains only
fixed projected validator rows; getters return copied observations/rows with full-width nominal
indices. Defaults/refusals carry reasons alone and guarded extraction remains enabled in release.

## Completion tests

Require literal same-epoch and rotating results with independent current/previous populations,
multiple skipped epochs, assurance-before-rotation, reporter key membership across changed rosters,
unknown/repeated reporters, repeated assurances and all six counter additions. Test exact/short/
full-width policies, invalid times/epoch/author/assurance positions, default owners, full-width row
ordinals, all six overflow boundaries and assurance overflow before rotation. Verify input and
extraction independence, source lifetime, hash-disabled operation and 1,000 ARC cycles. Add strict
runtime extraction and compiler privacy/nominal probes; run selected native suite, affected guard
runners, Python/inventory checks and pinned formatting.

## Remaining work

Bind validator observations to the authenticated accumulation candidate; calculate per-block core
and service activity and publish combined C(13). Remaining transfer/account/privilege coordination
and whole-block publication remain open. M1 framing is complete; full state serialization and
accumulation/block parity remain open.

## Local verification

`make unit SUITE=validator_projection` passes with literal six-field results for same-epoch retention,
first-boundary and multi-epoch rotation through the maximum E4 slot, growing/shrinking populations,
old-only assurer positions and posterior reporter identities. Empty observations still increment
one author block. Repeated assurances/reporters increment once; repeated matching roster keys each
receive one membership increment. All six counters accept their exact E4 endpoint and refuse a
one-unit overflow; explicit full-width byte increments refuse without wrapping. An old-current
assurance overflow refuses even during rotation.

Exact/short/full-width work limits, defaults, chronology, zero/full-width epoch lengths, population
mismatch, invalid author/assurer positions, forged epoch tags and full-width row ordinals pass their
boundary witnesses. Borrowed observations, scoped source owners and extracted fixed tuples cannot
alter retained output. With both hash backends disabled the suite makes zero backend calls.
Across 1,000 scoped rotating-success and policy-refusal cycles, occupied allocation stays at 3,312
bytes before and after.

All four runtime extraction guards and five compiler privacy/nominal guards pass using existing
source-discovered runners. `make check-python` passes 445 tests with seven skips; inventory discovers
113 failure families, 1,679 probes and 178 native suites. Pinned formatting/checking passes for
1,559 Nim files and the Rust crate. Existing C(13)/roster codecs, accumulation adapters, fixtures
and PVM code are unchanged; their prior evidence is reused. Logs are retained under ignored
`build/validator-projection/` and selected native/evidence directories. These are local macOS checks;
exact-head Linux CI remains separate. M1 framing is complete; full state serialization and
accumulation/block parity remain open.
