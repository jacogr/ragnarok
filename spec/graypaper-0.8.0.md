# Gray Paper 0.8.0 migration and parity audit

Target: [v0.8.0](https://github.com/gavofyork/graypaper/releases/tag/v0.8.0), commit
`07f041dabd073f9018b418e9ee72e79dd2185401`. Previous target: v0.7.1,
`1c979cb59bb800f92ffff083a2701004dfc6cd33`. This audit compares those exact revisions,
including intervening changes; it does not rely only on the 0.8.0 release notes.

The maintainer authorized completing the migration while recording any Bandersnatch parity blocker.
The release-designated ark-vrf 0.2.2 reference is now integrated and tested; a narrower discrepancy
between the draft text and that reference remains explicit.
The target specification is updated, but this is not a claim of complete 0.8.0 client conformance.
PVM, state transitions, block eligibility/import and validator operation remain separate work.
Complete block wire composition is now covered by the later M1 increment described below.

## Implemented scope

| Area | 0.8.0 change and disposition | Verification |
| --- | --- | --- |
| General naturals, fixed unsigneds, byte/sequence framing | Applicable definitions unchanged. | Existing independent oracle, boundary, malformed and fuzz suites. |
| Optional/work variants, preimages, complete work digests | Applicable wire layouts unchanged. | Published v0.8.0 samples with unchanged bytes plus independent codec tests. |
| Assurance bitstrings | C.1.5 corrects the summation bound; our LSB-first packing already agrees. | Every bit and aligned/partial byte boundary, including padding rejection. |
| Complete work reports | C.2 adds E2 erasure shards, E4 anchor slot and lookup-anchor posterior state root. | Published frozen 0.8.0 JSON/binary pairs, independent field encoding/decoding and truncations. |
| Report ownership and atomic encoding | New fields retained in the owned header; preflight validates shard domain before writing. | Existing source-mutation, owner-bound extraction, overlap and late-failure checks. |
| Validator population | `valcount` permits 6..3*Ccorecount validators in multiples of three. | Codec and verifier share the configuration predicate; reduced full-chain populations and invalid domains tested. |
| Blake2b-256, legacy Keccak-256, Ed25519 primitive | Applicable definitions unchanged. | Existing RFC, published/adversarial vectors and ABI/lifetime checks. |
| Guarantee signing transcript | `$jam_guarantee` plus Blake2b-256 of complete canonical report bytes remains unchanged. | Independent OpenSSL credentials; mutations of each new header field invalidate signatures. |
| Assurance signing transcript | `$jam_available` plus Blake2b-256 of parent and fixed-width bitfield remains unchanged. | Independent hashlib/OpenSSL transcript, key, signature and context checks. |
| Bandersnatch VRF/RingVRF | Migrated to draft-29 release-designated ark-vrf 0.2.2, including nonce updates. Literal draft challenge length remains inconsistent. | Published draft-29/JAM 0.8.0 vectors, proof widths and nonce-separation regression; one pending text-consistency check. |
| QUIC/CE 143 transport | JAMNP-S remains independently pinned; ticket framing is unchanged by the reviewed GP delta. | Fresh native peer, lifecycle/selftests and retained work-digest integration. RingVRF offload is rerun with the release-reference backend. |

The assurance bitfield always has one bit per **configured chain core**, including inactive cores.
A smaller active validator set changes the index/key/count domain, not this wire width. The standalone
message builder remains a byte-framing helper; chain population checks occur in the batch verifier.
The report codec checks shard counts against the configured core ceiling. Equality to the active
validator population, core assignments and anchor history are state-dependent checks, not codec work.

## New report header

Offsets are zero-based; all hashes retain their supplied 32 identity bytes.

| Field | Offset | Size |
| --- | --- | --- |
| Package hash | 0 | 32 |
| Bundle length | 32 | 4 |
| Erasure root | 36 | 32 |
| Erasure shards (new) | 68 | 2 |
| Segment root | 70 | 32 |
| Segment count | 102 | 2 |
| Anchor hash | 104 | 32 |
| Anchor slot (new) | 136 | 4 |
| Anchor state root | 140 | 32 |
| Anchor accumulation root | 172 | 32 |
| Lookup-anchor hash | 204 | 32 |
| Lookup-anchor slot | 236 | 4 |
| Lookup-anchor state root (new) | 240 | 32 |
| Prerequisite count and remaining report | 272 | Variable |

The old fixed prefix was 234 bytes. The codec has one 0.8.0 layout and no heuristic version detection
or automatic insertion of missing fields. Stored 0.7.1 report bytes need an external, explicit
migration with real context; zero-filling missing consensus fields is not a supported operation.
New nominal types distinguish the two slot roles and the two state-root roles.

## Fixture provenance

The vector source is now [davxy/jam-test-vectors v0.8.0](https://github.com/davxy/jam-test-vectors/tree/d3c089c9a1d5352ad353626d7a2db8589f137b2a),
commit `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. The W3F repository still has the older snapshot;
we pin the active maintainer's published release explicitly. No inference is made about why the
repositories have not been synchronized.

The submodule retains the focused `codec` and `stf/safrole` sparse checkout. Existing primitive,
work-digest and assurance fixtures have identical bytes to the prior pin. Complete report JSON
and binaries now contain all three 0.8.0 fields. `test_spec.py` verifies the source checkout, every
consumed content hash and the literal new-field offsets; the separate mathematical report oracle
constructs the whole wire from named fields. The native adapter independently observes decoded
fields. Temporary authored migration fixtures were replaced with these published pairs.
The tiny sample retains core index 3, so it remains a structural fixture and is rejected under
the actual two-core tiny bound. It is not a chain-eligible report.

Reduced Safrole fixture inputs are regenerated from the exact published tiny/full source cases;
source/reduced hashes are both retained. Their updated tickets verify with the historical backend,
which demonstrates compatibility with those published cases, not resolution of the draft text.

The release [changelog](https://github.com/davxy/jam-test-vectors/blob/d3c089c9a1d5352ad353626d7a2db8589f137b2a/CHANGELOG.md)
explicitly records deviations involving `grow_heap`, `bless` and conditional-move gas costs.
Those PVM/accumulation features are not implemented here. They must not silently become normative
rules when those subsystems are implemented. The changelog itself is content-hash pinned.

## Bandersnatch reference migration and remaining discrepancy

The [draft-29 release](https://github.com/davxy/bandersnatch-vrf-spec/releases/tag/draft-29)
explicitly designates **ark-vrf 0.2.2**. Both gitlinks are upgraded to the exact release commits.
This reference keeps a 32-byte challenge, matching GP's 96-byte ordinary signature and 784-byte
RingVRF contracts, while updating ordinary/Pedersen nonce derivation to include additional data.
The maintained ABI needed only the public `scalar()` accessor. The locked ring dependency closure
advances w3f-ring-proof 0.0.2 to 0.0.6, w3f-pcs to 0.0.5 and w3f-plonk-common to 0.0.6.
The trusted SRS and its hash remain unchanged. All upstream source trees remain pristine.

Tests reproduce every published draft-29 ordinary signature, verify published ring proofs and
updated JAM 0.8.0 tickets, and exercise safe randomized proof generation. A Rust regression
requires different test-key nonces for one VRF input signed under different additional data.
The old backend reused them. Proof lengths are checked without padding or truncation.

The draft text section 2.1 says `cLen = 16`; the explicitly designated reference uses 32.
Its Appendix B also retains a stale-vector warning, but the pinned ordinary vectors reproduce
0.2.2 exactly. We implement the release-designated reference and record the contradiction rather
than claiming literal draft-text parity. `bandersnatch-pins.json` retains both challenge lengths;
`test_spec.py` reports one focused pending text-consistency check. Resolving that statement needs
upstream clarification. The pre-existing exceptional-point Ed25519 policy gate remains open too.
No passing suite establishes a full consensus or security audit.

## Changes outside existing implementation

Work-package input framing and structural resource limits are now implemented in the
[work-package codecs](work-package.md); execution, authorization and external-data resolution
remain separate work. The disputes framing/count rules are implemented in
[the disputes codec](disputes.md), with
context-dependent judgments and state effects still external. The source diff also changes
variable-validator Safrole/state encodings, guarantees stored in availability assignments,
preimage commitments in the block extrinsic
hash, authorizer identification, erasure coding, service statistics, accumulation, PVM gas/host
calls and refinement context exposure. Those complete subsystems are not implemented here.
The existing preimage codec is unchanged; it is distinct from the newly defined block commitment.
The report's opaque authorizer hash is preserved; deriving it from code hash and configuration
belongs to future authorization work. No obsolete implementation is retained for these systems,
and no new scaffolding is presented as parity. See `docs/design.md` for the remaining client work.

Standalone full/signing header and epoch/winner marker codecs now cover the 0.8.0 header wire
changes, including variable epoch validator counts. [Their contract](header.md) separates framing
from marker state eligibility, header/extrinsic hashing and signature verification.

Complete extrinsic/block wire composition is now implemented in [block_codec](block.md). Parent
preflight preserves each existing child policy and does not calculate or verify the header
extrinsic commitment. All published codec families have explicit fixture outcomes; the
[coverage audit](../docs/codec-coverage.md) records the scoped C.1/C.2 baseline and wider boundaries.
Later M1 increments also implement general Boolean/bitstring/typed collection APIs and
[standalone availability/accumulation records](c2-records.md); this is framing coverage, not
accumulation execution or state-serialization parity.

## Reproduction and observed validation

Use the [pinned project toolchain](../docs/development.md), ARC, checked Clang LTO and Rust 1.99.0.
Local verification runs on macOS ARM64; Linux x86-64 runs the same source/fixture checks in
`.github/workflows/linux.yml` after push.
Checked optimized report builds retain ARC/Clang LTO and all existing runtime guards.

```sh
make check
```

Observed migrated workloads: 18,430 report requests with 63 independent crypto composition checks;
20,706 assurance codec requests; 2,087 assurance context/signature checks; four report, three
assurance and two assurance-context nominal rejection probes. The source/provenance checks pass
with one explicitly pending Bandersnatch draft-text consistency test. No Linux result is inferred
from local execution. The full local lifecycle suites also pass: 40 soak sessions, 16 retained-service
waves, 128 IPv6 queries, 12 peer-death and 12 overload waves, and 288 integrated streams. The ten-wave
proof-offload suite passes after the ark-vrf upgrade, with two workers and four owned job slots,
so its result refers to the final release-reference backend.

## Subsequent state-wire parity gates

The [width investigation](state-widths.md) and T's general fixed-width note support the implemented
C12 E4-service/E8-gas dictionary and C13 E4 service-key migration. All 224 selected chapter captures
and fourteen full-state mappings now pass [typed composition](state-composition.md), including
unchanged bytes that previously produced shorter-prefix/noncanonical verdicts.

C13 statistics gas uses the published canonical JAM compact natural framing. The maintainer
accepts that vector-compatible representation, with no fallback. The difference from T's general
fixed-width note is documented rather than treated as a pending policy gate. Active known-answer
and exact-capture checks enforce that decision. Open upstream #564 supports this interpretation;
its additional validator-statistics format proposal is not adopted here.

The [request-history contract](state-requests.md) records the remaining cross-map question:
E4 lengths fffffffe/ffffffff reproduce preimage/storage key prefixes. Full stated domains remain
supported and duplicate keys reject. The fix is merged upstream as #542 but remains
[pending adoption with compatible release/vector pins](state-clarifications.md).
