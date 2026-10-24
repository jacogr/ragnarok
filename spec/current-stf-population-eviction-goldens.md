# Whole-map STF goldens for offenders, validator populations and contest eviction

The [verdict/fault extension](current-stf-verdict-fault-goldens.md) adds independently calculated
judgment classification, opposing evidence and assignment cancellation. These original cases,
fixtures and expected output hashes remain unchanged.

Scope: sixteen additional genuine current-candidate transitions with independently calculated
complete successor maps. Pins remain Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
Draft35 Thin v1/ark-vrf0.6.0 and vectors `23061ae1f9b51171c01387e7dde0f15794c98e24`.
Authority: `judgments.tex` culprit eligibility/signatures, `offendersdef` and `judgmentmarker`;
`safrole.tex` `valcount`, `nullvalkey`, `blacklistfilter`, rotation, contest, marker and seal
equations; current serialization, history, authorization and statistics equations.

## Reproduced population rejection and correction

A three-core original map has six active, nine pending, six staging and nine previous validators.
All four are valid GP populations: each sequence independently has a multiple of three between
six and three times the core count. A coherent ceiling-nine policy is necessary to decode them.
Before this change, the signed slot2 child fails with
`CurrentCandidateError.PrefixFailure → ApplicationCandidateError.ProfileMismatch` before
disputes execution. Candidate admission equates the decoder ceiling with the current active count.
The same equality exists at current publication and input/download admission boundaries.

Those four boundaries now require that the ceiling covers the selected head, is a multiple of
three and is at most three times its core count. Division avoids multiplying untrusted capacity.
Core and epoch equality, complete-state/view identity, full chain Parameters, actual author
membership and all existing contextual quorum checks remain enforced. A policy ceiling does not
change the contextual population. Explicitly narrower resource policies can still refuse chapters.
The legacy publication/input/download pipeline retains its existing profile contracts.

The population corpus exercises all four corrected boundaries. Candidate/input/download reject
ceilings3,8,12 at all six heads (54 exact profile refusals), while input/download accept9 at all
heads (12 admissions). All six candidates complete real current composition and publication.

## Complete original inputs and independent expected maps

`current-stf-population.json` freezes an authored complete original map, two native ring input
commitments (initial pending and filtered staging), and independent successor roots/checkpoint
hashes. Its oracle independently reconstructs every changed original chapter from the unchanged
epoch original: nine mathematical public scalars, OpenSSL-derived Ed25519 identities, distinct
nonzero BLS/metadata, three-core queues/pools/availability/privileges and deliberately different
current/previous counters. The reconstructed map must exactly equal the frozen original.

| Chain | Slots | Whole-map behavior |
| --- | --- | --- |
| Culprit and population | 2,11,12,13,24,25 | Signed culprit evidence, C5 union/header marker, delayed full null filtering, active6→9→6 and previous9→6→9, independent C13 dimensions/counters |
| Contest eviction | 2,3,4,5,6,7,10,11,12,13 | Twelve real initial admissions, one lower-score replacement, unchanged full contest across empty body, cutoff winners, new best ticket seals slot12 |

The culprit signs `jam_guarantee || bad_report_hash` for an already bad report. OpenSSL checks a
pinned RFC8032 case and independently produces the deterministic evidence bytes; native dalek
must validate them. Only C5 and the new-offender header marker change immediately. At slot12,
pending is filtered staging, active is the unfiltered original nine pending records, and previous
is the original six active records. At slot24 the filtered six-member pending roster becomes
active. Offender removal replaces the entire336-byte record with the specified null key, clearing
the deliberately nonzero BLS/metadata. Staging stays unchanged. Null fallback positions28,32,33
remain unsealable; a hostile scalar-one child at28 fails `AuthenticationFailure/InvalidAuthor`.

The eviction fixture references the exact earlier epoch fixture SHA-256 and adds only two fixed
pending-ring proofs: scalar1/attempt3, whose score is lower than all twelve current scores, and
scalar6/attempt3, whose score is higher than the old worst. Mathematical Thin independently
reproduces each O and output. The first replaces exactly scalar4/attempt1, preserves contest
size12 and becomes the first winner; the second fails `AdmissionFailure/NotRetained` at slot7.
Re-submitting the evicted ticket also fails `NotRetained`, rather than `Duplicate`.

Both references calculate every complete child wire and posterior checkpoint before the registered
native build/run. Each later parent comes from the previously calculated map. They calculate all
global entries, service metadata and supplied storage/preimage/request namespaces, including
history/MMR/header hashes, entropy, variable roster/statistics sizes and unchanged entries.
Native successor observations never become golden inputs. All original and upstream fixture
bytes remain unchanged. Shared equations retain the earlier52 authored expectations exactly.

Ring commitments and the two new Ring membership proofs are qualified native input witnesses,
generated only in explicit `--generate` modes using the unchanged public SRS. Capacity is nine
for the three-core chain and six for the two-core chain; invalid null Bandersnatch encodings map
to the already qualified ring padding at the public Nim boundary. C4 still stores the exact null
record. This work does not independently implement or audit Ring/KZG membership mathematics.

## Verification and limits

The source-owned `current_stf_population_corpus` and `current_stf_eviction_corpus` run through
the existing checked native builder and exact full-output comparator in `make check-unit`.
Normal execution replays frozen inputs. Fixture descriptors check input hashes; Python reference
tests run through ordinary discovery. Negative native controls additionally isolate missing
offender marker, bad culprit signature and repeated prior offender as
`InvalidMarker`, `InvalidSignature`, `InvalidKey`; each preserves the canonical complete map.

Reusable native construction lives in `tests/support/current_stf_epoch_context.nim`; each driver
owns its execution loop and entry point. The batch must pass using the normal shared checked
native profile cache, including epoch followed by eviction. No executable driver is imported as
a helper: the earlier arrangement passed isolation but retained the old main in the shared-cache
eviction build and failed before its first observation. The helper extraction leaves compiler,
cache policy, frozen inputs and expected map bytes unchanged.

Local checked ARC/Clang release verification and exact-head Linux CI are separate evidence.
Observed locally on macOS ARM64: all68 authored whole-map transitions passed exact output
comparison in the maintained shared-cache profile (checked non-LTO, as normal runtime corpora).
The earlier20 empty,10 effects and22 epoch outputs retain their saved SHA-256 values. All95
scoped Python reference/harness checks, seven affected native application/current-chain suites
(six with fresh1,000-cycle ARC evidence),408 production modules plus peer semantic checks, pinned
formatting and inventory passed. The new controls cover six protocol refusals and54 profile
refusals in addition to12 input/download admissions. No refused candidate is installed.

These authored cases extend the earlier empty-body, guest-effect and epoch/ticket goldens.
General external trace parity, whole-map verdict/fault cases, nonempty guarantee/assurance
interactions, and guest-driven changes to staging populations require further independent cases.
The documented mixed-profile historical credentials/metadata limitations and conflicting-allowance
`AmbiguousPrivileges` guard remain unchanged. No pin, upstream fixture or dependency is advanced.
