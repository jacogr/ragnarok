# Whole-map STF goldens for verdicts and faults

The [guarantee/assurance extension](current-stf-guarantee-assurance-goldens.md) adds complete-map
report admission, availability, replacement, timeout and unresolved ready-ring cases. These
verdict/fault fixtures and expected outputs remain unchanged.

Scope: three authored complete-state chains, twelve actual candidate transitions and twenty
structurally valid, correctly sealed negative controls. Pins remain Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, Draft35 Thin v1/ark-vrf0.6.0 and vectors
`23061ae1f9b51171c01387e7dde0f15794c98e24`. Authority is `judgments.tex` epoch-selected
quorums, verdict thresholds, opposing evidence, missing-fault rule, `removenonpositive`,
`offendersdef` and `judgmentmarker`, with the pinned Safrole, availability and statistics rules.
No production protocol implementation or dependency pin changes in this increment.

## Inputs and independent reference

`tests/fixtures/current-stf-verdicts.json` references the exact earlier population fixture hash,
freezes two authored retained C10 assignment records and three disputed report hashes, and contains independently calculated
successor roots/full-checkpoint hashes and the ordered negative-control reasons. The original
three-core map is reconstructed independently, including full336-byte records, six active and
nine previous/pending validators, distinct keys/metadata and current105-byte service records.
The native fixture constructor now lives in its existing support module, shared by both drivers;
the earlier population fixture and its expected outputs remain unchanged.

Retained assignments are explicit original-state inputs with independently encoded reports and
OpenSSL-signed guarantee credentials. They are not a claimed predecessor guarantee-admission
trace. Their active core0/1 positions, distinct package hashes, complete reports, slots, credentials and registration times remain
observable in every map. Empty assurance extrinsics make no report newly available.

OpenSSL is checked against the pinned RFC8032 case and deterministically signs public seeds11..19.
Each judgment/fault signs raw report hashes under exact ASCII `jam_valid` or `jam_invalid`;
culprits sign `jam_guarantee`. Native dalek verifies the actual signatures. No native disputes
result supplies the reference classifications, marker, assignments or successor entries.

`tests/current_stf_verdict_oracle.py` independently calculates:

- parent-selected active/previous rosters, exact two-thirds-plus-one quorum, ordered high
  validator ordinals and the good/bad/wonky thresholds of all, zero and one-third positives;
- opposing fault eligibility from the original active/previous union minus prior offenders,
  required fault evidence for every new good verdict, and same-block/delayed evidence;
- exact culprit-then-fault marker order, retaining repeated keys across sections while C5
  stores only the sorted set union; evidence sections remain separately ordered and unique;
- cancellation of bad/wonky retained assignments, preservation of good assignments and exact
  five-slot expiry, without manufacturing an available report or accumulation output;
- all complete successor entries through mathematical Thin/header/entropy, C5/C10, roster
  filtering/rotation, statistics, authorization, history/MMR and unchanged service namespaces.

Every expected block and map exists before native build/run. Later parents come exclusively from
previously calculated maps. Existing qualified ring roots are input witnesses: these cases filter
the same staging member as the earlier population corpus. No new Ring/KZG audit is claimed.

## Chain coverage

| Chain | Slots | Distinguishing behavior |
| --- | --- | --- |
| Mixed sections and cancellation | 2,3,6,11,12,13 | Current-six good/bad/wonky verdicts, culprit plus faults with one repeated marker key, previous-only fault key, delayed fault, bad cancellation, good retention/expiry, deferred null filtering |
| Parent epoch quorums | 12,13,14,24,25 | Five-vote verdict before growth to nine, current-nine versus previous-six quorums, wonky thresholds3 versus2, delayed opposing evidence, seven-vote verdict before shrink to six |
| Wonky cancellation | 2 | Same valid original assignments, with core0 judged wonky and core1 judged good; only core0 is cancelled |

Only two cores can retain assignments under six active validators, even though the configured
core ceiling is three. The third branch isolates wonky cancellation on an active core, preserving
the good assignment byte-for-byte. An inactive-core assignment is not silently accepted.

The first chain proves that an unknown-to-current but previous-roster key can provide fault
evidence. The second uses the highest selected judge index (5 or8), distinct roster orders, and
verdicts on the same blocks that change the active population. Punished identities are excluded
from new offense evidence; judgments still use the specified original epoch roster.

Twenty native negative controls select exact disputes reasons: `InvalidQuorum`, `InvalidEpoch`,
`InvalidSignature`, `InvalidSplit`, `MissingFault`, `InvalidEvidence`, `InvalidMarker`,
`AlreadyJudged`, `InvalidKey`. They include short/wrong population quorums, future epochs,
damaged signatures/wrong roster keys, wrong fault domain, faults against wonky reports, missing
positive evidence, deduplicated/incomplete markers, replayed verdicts and repeated prior offenders.
Every refused input preserves the canonical complete checkpoint and selected head. No refusal
is installed. Each accepted successor additionally passes current profile/global/namespace
qualification before installation; the original snapshot remains unchanged.

## Verification and remaining scope

`current_stf_verdict_corpus` is source-owned in `tools/corpus_state.py`, uses fixture hash
contracts, normal checked ARC/Clang shared native caches and exact full-output comparison.
The Python invariants run through normal unittest discovery; no duplicate runner is introduced.
Required local checks: the new registered corpus, the earlier population corpus after constructor
extraction, independent earlier golden-output hashes, affected reference/harness tests, pinned
formatting and verification inventory. Production compilation/units retain their earlier passing
evidence because production sources and native dependencies are unchanged.

Observed locally on macOS ARM64, pinned checked ARC/Clang release without LTO (the maintained
native corpus profile): all twelve new transitions and twenty exact refusal controls passed
complete output comparison. The earlier six-transition population corpus passed after constructor
extraction with unchanged output SHA-256
`94f385dc2b80c18b3050bb3b954efac4e8f72cb86ccf0ce1531f2782e1322473`.
All68 earlier expected output wires/maps retain their saved passing SHA-256 values. All52 scoped
Python reference/harness tests, pinned formatting and verification inventory passed. Existing
upstream/earlier fixture bytes and qualified native-library bytes remain unchanged.

These cases do not establish general external trace parity, nonempty assurance/guarantee
extrinsic interactions, all resource-limit combinations, or guest-driven staging changes.
Historical upstream bytes, mixed-profile external limitations and `AmbiguousPrivileges` remain
unchanged. Exact-head Linux CI is separate evidence from local macOS ARM64 verification.
