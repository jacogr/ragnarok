# C12/C13 width investigation and migration decision

Normative target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T and its following numeric-width note; C.1 dictionary/count serialization;
`text/accounts.tex` service IDs; `text/definitions.tex` gas; `text/statistics.tex` activity domains.
Published reference: `davxy/jam-test-vectors` v0.8.0
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Exact consumed blob hashes, including reference
schemas and inspected conversion declarations, are in [pins.json](pins.json). Upstream sources
were read as data, never installed, imported or executed. No dependency revision advances.

## Decision and current implementation

The investigation supports a concrete next migration:

| Field | Normative basis | New independent evidence | Decision |
| --- | --- | --- | --- |
| C12 always-accumulate service ID | T non-discriminator numbers use fixed widths; service IDs have a 32-bit domain. | Four nonempty STF Privileges fields uniquely match E4 IDs, including ID 1729. | Migrate natural keys to E4. |
| C12 always-accumulate gas | Same T note; gas has a 64-bit domain. | Those four fields uniquely match E8 gas, including gas 100000. | Migrate natural gas to E8. |
| C13 service dictionary ID | Same T note and 32-bit service-ID domain. | Thirteen nonempty raw entries match E4 keys; ten contain nonzero IDs, up to 3953987649. All diagnosed IDs identify existing full C(255,service) keys. | Migrate natural keys to E4. |
| C13 gas fields | The T note and 64-bit gas domain suggest E8. | All sixteen selected raw entries reconstruct with natural gas, while E8 alternatives fail complete reconstruction. | Keep an explicit normative/reference conflict; do not invent a fallback or silently switch gas. |

These are reasoning conclusions from the normative note plus cross-checks, not a newly published
upstream erratum. The earlier argument that a dictionary lies outside a local E4 override is
insufficient to disregard T's general fixed-width note for a bounded service-ID/gas domain.
C12 has no observed conflicting raw wire evidence. C13 gas does, so it remains separately gated.
The pinned ASN.1 schema confirms bounded service/gas domains but is not used as authority to assign
fixed widths to every statistic: several measures are bounded there but general naturals in the
paper. Integer domain annotations alone do not prove the encoded widths in a particular field.

**Production codecs are unchanged in this investigation increment.** C12 still uses natural
service/gas pairs and C13 still uses natural service keys/gas. Their migration is the next bounded
implementation group, with existing canonical order, byte/item policies and ownership preserved.
The pending C12 harness gate now explicitly tracks that implementation work. C13 gas and request
namespace admissibility remain unresolved even after the proposed migration.

## Nonempty C12 reference evidence

Previously selected raw T(12) dictionaries were empty. The bounded search additionally reads
pre/post states from eight trace snapshots:
`fuzzy/{00000025,00000050,00000100,00000150,00000200}.json`,
`fuzzy_light/00000200.json`, `storage/00000100.json` and `preimages/00000100.json`.
All sixteen new raw C12 dictionaries are also empty. This is a sampled search, not proof that
upstream never publishes a nonempty raw T(12) dictionary.

Nonempty evidence comes instead from
`stf/accumulate/{tiny,full}/always_accumulate-{1,2}.bin` and their paired JSON files. The pinned
`accumulate.py`/`accumulate.asn` declarations place input first, followed by the pre-state slot,
entropy, fixed ready/accumulated queues and Privileges. The four selected pre-state queues are
empty. An independent encoder reconstructs the **entire preceding prefix**, including any input
reports, and asserts exact prefix identity before comparing candidates at the resulting offset.
No byte-pattern search, guessed suffix or upstream generator locates the field.

| Fixture | Verified offset | Complete Privileges extent | Shared nonempty pair |
| --- | ---: | ---: | --- |
| tiny / always_accumulate-1 | 65 | 33 | service 1729, gas 100000 |
| tiny / always_accumulate-2 | 473 | 33 | service 1729, gas 100000 |
| full / always_accumulate-1 | 1241 | 1389 | service 1729, gas 100000 |
| full / always_accumulate-2 | 1649 | 1389 | service 1729, gas 100000 |

For each field, all four combinations of natural/E4 service and natural/E8 gas are compared with
the unchanged bytes at exactly that offset. **Only E4/E8 matches.** Natural counts and the fixed
role group are held constant. These four observations share one numeric pair; they do not supply
four distinct boundary cases. They are **STF Privileges fields, not standalone raw T(12) entries**.
Their agreement corroborates the T note; their outer STF framing is never substituted for T(state).

## Wider C13 raw evidence

The same eight snapshots supply sixteen original raw C(13) values. The diagnostic holds validator
count/E4 counter framing and ordinary natural measures constant, varying only service keys
(natural/E4) and gas at all core/refinement/accumulation positions (natural/E8).
Each candidate must parse canonically, preserve uint32 key domains and strictly increasing key
order, consume the **entire** value and re-emit every byte identically. Rejected candidates carry
only an error, never partial inferred fields.

All sixteen match E4 keys plus natural gas; thirteen have nonempty service dictionaries. For those
thirteen, that is the only complete matching candidate. The three empty dictionaries cannot
choose between key widths. Ten observations contain nonzero IDs; every diagnosed service ID maps
to an actual full metadata key in that same original state (55 key associations in total).
This extends the earlier key-zero-only evidence without claiming a distinct case for each repeated
service or certifying statistic update semantics. Twelve observations contain positive gas values.
E8 gas fails complete reconstruction in all sixteen selected values, including zero-gas cases.

## Reproduction and honest failure accounting

After native crypto construction:

```sh
python3 tests/test_state_widths_harness.py
python3 tests/test_state_widths.py
python3 tests/test_spec.py
python3 tools/format.py --check
```

Six literal harness checks anchor candidate byte identities, nonzero wide keys/gas, empty-map
indistinguishability, exact extents and key ordering. The reference evaluates **80 width candidates**
(16 binary-field alternatives and 64 raw-statistics alternatives). **37 checked native requests**
run the existing exact chapter capture API: one ownership selftest plus 36 published-value probes.
They agree with the independent current-layout oracle, with these actual whole-entry results:

| Input | Exact successes | TrailingBytes | NonCanonical |
| --- | ---: | ---: | ---: |
| Four nonempty binary Privileges fields | 0 | 4 | 0 |
| Sixteen empty raw T(12) entries | 16 | 0 | 0 |
| Sixteen raw T(13) entries | 3 | 5 | 8 |

Passing the audit means the evidence and current failures reproduce. It does **not** mean the
seventeen rejected whole-entry probes conform, and it does not close M1. Logs/results under
ignored `build/state-widths/` retain identities, SHA-256 hashes, candidates, offsets, decoded
candidate fields/metadata associations, native actual/expected verdicts, build flags and compiler/
Python/OS versions. The new exact blob hashes extend the existing vector pin; gitlinks/toolchains
remain unchanged. Linux CI runs and retains the same checks; local macOS arm64 results do not
claim Linux confirmation.

Next: implement **C12 E4/E8 pairs and C13 E4 dictionary keys** together, update framing/limits and
boundary/ownership tests, then re-run exact capture and whole-state composition. C13 gas and
request namespace policy remain separate unresolved gates. No new client milestone is claimed.
