# Gray-Paper-derived serialization qualification

## Authority and completion basis

Target: unreleased Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
Appendix C in `text/serialization.tex` and state mapping/commitment equations in
`text/merklization.tex`. Exact source digests remain in [pins.json](pins.json).
Original `davxy/jam-test-vectors` gp-next observations remain pinned at
`23061ae1f9b51171c01387e7dde0f15794c98e24`.

On 2026-10-25 the maintainer selected **independent derivation and verification
from the Gray Paper** as the completion basis. Another JAM client's emitted bytes,
reverse engineering and conversion of another client's output into expected vectors
are excluded. The expected bytes, fields, malformed-input reasons and roots below
come from project-owned independent test equations. Native output is the observation
being checked, never the source of an expected result. Hand-authored byte anchors
and exact fixture identities make field widths/order and expectation changes inspectable.

Keep the accepted C13 interpretation explicit: core/service statistics, including
gas, use canonical naturals; validator counters use E4 and service keys use E4.
C12 pairs use E4 service IDs and E8 gas. This is the maintainer-directed
vector-compatible interpretation, not a claim that the paper's blanket fixed-width
note changed. There is one representation and no alternate decoder fallback.

## Equation-to-check coverage

The following are existing source-owned corpus tasks; their native adapters and
independent expectations are reused unchanged. All checks preserve exact failure
verdicts, complete expected/actual comparison and runtime bounds/assertions in
optimized ARC/Clang builds. They are serialization checks, not valid-state/STF claims.

| Pinned equation family | Independent expectations | Native verification task |
| --- | --- | --- |
| C.1 trivial tuples, naturals and E0..E8 integers | `tests/test_codec.py` | `natural_corpus`, `fixed_corpus`; tuple order additionally covered by typed records below |
| C.1 byte/fixed-width sequences | `tests/bounded_checks.py` | `bounded_corpus` |
| C.1 optional/tagged values; C.2 work result O | `tests/composite_checks.py` | `composite_corpus` |
| C.1 Boolean and fixed/variable bitstrings | `tests/bits_oracle.py` | `bits_corpus` |
| C.1 canonical sets/dictionaries | `tests/collections_oracle.py` | `collection_corpus`; explicit scalar schemas, not arbitrary child-codec APIs |
| C.2 work digests | `tests/digest_checks.py` | `digest_corpus` |
| C.2 complete reports and field transcripts | `tests/report_oracle.py`, `tests/report_fixtures.py` | `report_corpus`, `report_signature_corpus` |
| C.2 assurance bitfields/credentials and context | `tests/assurances_oracle.py`, `tests/assurance_crypto_oracle.py` | `assurance_corpus`, `assurance_context_corpus` |
| C.2 guarantees | `tests/guarantees_checks.py` | `guarantee_corpus` |
| C.2 ticket extrinsics/records | `tests/tickets_oracle.py` | `ticket_corpus` |
| C.2 dispute verdict/judgment/culprit/fault records | `tests/disputes_oracle.py` | `dispute_corpus` |
| C.2 refinement context, import I/I#, work items/packages | `tests/package_oracle.py` | `package_corpus` |
| C.2 regular/unsigned headers and marker variants | `tests/header_oracle.py` | `header_corpus` |
| C.2 extrinsic and complete block tuple order | `tests/block_oracle.py` | `block_corpus` |
| C.2 avspec, defxfer, operandtuple/input union | `tests/c2_oracle.py` | `c2_corpus`; 154-byte current transfer and strict Boolean |
| C constructors and canonical trie-node encodings | `tests/state_layout_oracle.py` | `layout_corpus` |
| M over complete serialized mappings | `tests/state_trie_oracle.py` | `trie_corpus`; independent list partitions, duplicate refusal and bounded work |
| T C(1/2) pools/queues | `tests/state_authorization_oracle.py` | `authorization_corpus` |
| T C(3) history/dictionaries/belt | `tests/state_history_oracle.py` | `history_corpus` |
| T C(4) pending/ring/schedule/accumulator | `tests/state_consensus_oracle.py` | `consensus_corpus` |
| T C(5) judgment/offender sets | `tests/state_disputes_oracle.py` | `state_disputes_corpus` |
| T C(6/7/8/9/11) entropy/rosters/time | `tests/state_safrole_oracle.py` | `safrole_corpus` |
| T C(10) optional guarantees/registration slots | `tests/state_availability_oracle.py` | `availability_corpus` |
| T C(12) privileged roles and service/gas pairs | `tests/state_privileges_oracle.py` | `privileges_corpus` |
| T C(13) statistics, with the accepted width interpretation | `tests/state_statistics_oracle.py` | `statistics_corpus` |
| T C(14/15) ready/accumulated rings | `tests/state_workqueues_oracle.py` | `workqueues_corpus` |
| T C(16) ordered service/output tuples | `tests/state_outputs_oracle.py` | `outputs_corpus` |
| T C(255,service), current supervised metadata | `tests/state_accounts_oracle.py` | `accounts_corpus`; all current 105-byte fields |
| T raw storage/preimage namespaces and values | `tests/state_service_values_oracle.py` | `service_values_corpus` |
| T request key/history and current admissible lengths | `tests/state_requests_oracle.py` | `requests_corpus`, `request_namespace_corpus` |
| Whole T composition, width and original-root observations | `tests/state_composition_oracle.py`, `tests/state_widths_oracle.py`, `tests/state_roots_oracle.py` | `composition_corpus`, `state_widths_corpus`, `state_roots_corpus`; historical/derived observations keep their original labels |

The typed [whole-state encoder qualification](state-typed-serialization.md)
constructs all sixteen native chapters from logical fields before capture, compares
128 complete encoder outputs, and checks 8 complete maps across tiny/full/resized
profiles and both Safrole schedules. All service entries have typed logical sources.
Independent expectations include the current account fields, nested authored reports,
all request-history alternatives and distinct per-field fingerprints. The existing
[complete](state-complete-serialization-corpus.md),
[multi-service](state-multiservice-serialization-corpus.md) and
[refusal](state-serialization-refusal-corpus.md) families retain their separate scope.

Full checkpoints are a local observation envelope around every exact T key/value
and the independently calculated root. `RAGNAROK-FULL-V1` is not a Gray Paper wire
format; comparing that envelope does not introduce it as protocol serialization.

## Evidence

The focused current-source sweep ran all 37 tasks in the table on macOS ARM64 with
checked ARC/Clang ThinLTO. All passed. Native adapter requests and independent
expected/actual hashes are retained per task; original source and generated input
identities are recorded. The typed-source suite also passed on macOS ARM64 and
checked Linux amd64 under emulation, with 384 precise chapter refusal checks and
12 Python anchor/provider checks. Source inventory and pinned formatting passed.

The same 37 tasks passed on checked Linux amd64 under emulation with ARC/Clang
ThinLTO. Every recorded request count and request/expected/actual hash matched
macOS. All 7,545 frozen codec/crypto/test/tool and pin inputs matched the retained
Linux image `0ca53897de04df2ab8588edf49348527f67af39000d0419573766b6980428a5c`.
An additional 196 existing independent reference/anchor tests passed; the exact
pinned Gray Paper source-provenance check passed separately. These are focused
local covered-source results, not a claim that the wider whole corpus command or
remote CI passed. A successful finite corpus is strong scoped qualification,
not a formal proof over all possible states.

## Completion and exclusions

The documented M1 C.1/C.2 framing baseline remains complete. This work closes the
reviewed current-schema **spec-derived serialization qualification** within the
implemented schema/resource contracts and accepted width interpretation. It does
not claim universal mathematical proof or certification of a complete JAM client.

Original compatible gp-next samples corroborate the equations. Selected raw
published maps still carry 89-byte account metadata; zero-field projections and
authored current cases retain distinct provenance. Finding additional original
published current-schema complete maps is useful corroboration, not a blocker to
the maintainer-selected spec-derived qualification. No purported generator output
is needed to fill that corpus gap.

Cross-chapter valid-state relationships, signatures/VRF eligibility, full STF parity,
consensus/finality/root trust and physical power-loss durability remain separate
contracts. Generic collections expose their declared value-only scalar schemas;
this work does not add a general arbitrary-child-codec framework. Future source or
format changes require a fresh pin review and affected qualification, not fallback.

## Reproduction

`make unit SUITE=state_typed_serialization` runs the complete typed-source matrix.
`make check-corpus` owns all source-registered corpora, including the 37 serialization
tasks and additional independent feature corpora outside this focused report.
`make check-python`, `make check-inventory` and `make format-check` retain their
normal reference/tooling, registration and formatting roles. Selected tasks use
the same registered callables and strict builders as that supported Make path;
local focused evidence must not be labelled as the whole wider command passing.
