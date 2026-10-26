# Generated STF correctness qualification

## Target and authority

This target advances STF correctness independently of other clients: generate
reachable multi-block inputs, derive every expected successor from the pinned
Gray Paper, compare complete native maps, exercise single-condition invalid inputs,
and retain reproducible failures. It does not claim full JAM conformance from a
finite campaign. The [host/population assessment](current-stf-population-qualification.md)
remains the preceding bounded interaction audit.

Authority remains GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and recorded
gp-next `23061ae1f9b51171c01387e7dde0f15794c98e24`. No client-emitted posterior
supplies an expected map. Existing authored original inputs are reused; their
provenance is not upgraded to an independent genesis derivation. Original RingVRF
input witnesses retain their existing attribution; this is not another crypto
implementation or an external-client campaign.

## STF family audit and next gaps

This is a family-level audit of the existing contracts, followed by a rule-level
matrix for the selected reporting campaign. It is not an assertion that every GP
predicate or every legal state has been enumerated. “Existing evidence” means the
linked finite contract, not an unqualified subsystem pass.

| STF boundary | Existing independent evidence | Generated-campaign disposition |
| --- | --- | --- |
| Header ancestry, roots, seals, clock and markers | [Epoch goldens](current-stf-epoch-goldens.md), [current candidate](pvm-current-candidate.md), [trace import](current-stf-trace-import.md) | Generated valid signed children use real parent roots; broad malformed header/ancestry generation remains open. |
| Safrole contests, entropy, staging and promotions | [Epoch composition](current-stf-epoch-composition.md), [ticket reporting](current-stf-ticket-reporting.md), [designation](current-stf-rotation-designation.md) | Current campaign crosses growth/shrink boundaries with real Thin-derived entropy; randomized ticket contests and offender histories remain open. |
| Disputes, verdicts, offender exclusion and pending-report cancellation | [Verdict/fault goldens](current-stf-verdict-fault-goldens.md), [offender reporting](current-stf-offender-reporting.md), [full consensus](jam-full-consensus.md) | Existing finite evidence retained; independent generated disputes are a separate next target. |
| Guarantee admission, assignments, assurances and availability | [Population reporting](current-stf-population-reporting.md), [guarantee/assurance goldens](current-stf-guarantee-assurance-goldens.md) | First generated target; exact rule matrix below. |
| Authorization pools and queues | [Authorization transition](authorization-transition.md), [privileges](current-stf-rotation-privileges.md) | Full expected maps compare actual consumption/replenishment during generated reporting; randomized privileged queue mutation remains open. |
| Accumulation, guest effects, gas, queues and reentry | [Interaction inventory](current-stf-population-qualification.md), [late gas](current-stf-late-gas.md), [dependency waves](current-stf-population-waves.md) | Generated released reports execute the existing literal halt/panic/checkpoint programs. Dependency, gas-offer and transfer generation remain open. |
| Service namespaces, requests, provisions and lifecycle | [Preimage lifecycle](current-stf-rotation-preimages.md), [creation](current-stf-rotation-creation.md), [reactivation](current-stf-late-reactivation.md) | Compare complete namespaces in this campaign; generated lifecycle/provision operations remain open. |
| History, statistics, outputs and serialization | [Whole maps](current-stf-whole-map.md), [long histories](current-stf-late-histories.md), [serialization status](jam-serialization-status.md) | Every generated successor compares all entries and roots, plus separate participation/balance invariants; production-size limits and arbitrary histories remain open. |
| Checkpoint, trace and operator continuation | [Late restart](current-stf-late-restart.md), [trace](current-stf-late-trace.md), [operator](current-stf-late-command.md) | Existing trust-boundary evidence retained; generated histories currently use ordinary candidate installation, not a new restart/trace campaign. |

## Selected rules and evidence

Normative locations are `text/reporting_assurance.tex`, especially
`eq:xtassurances`, `eq:assurancesig`, `eq:availableworkreports`,
`eq:availassignmentspostassurancesdef`, `eq:priorassignments`,
`eq:guarantorsig`, `eq:reportcoresareunused`, `sec:contextualvalidity` and
`eq:reportcodesarecorrect`; `text/safrole.tex` key rotation;
`text/accumulation.tex` execution/statistics; and `text/pvm_invocations.tex`
`eq:accinvocation` regular/exceptional selection.

| Rule | Generated evidence | Remaining limitation |
| --- | --- | --- |
| G1 strict prior-active quorum | Sample zero, exact floor(2N/3), and one-above votes; compare actual released service operands. | Does not exhaust every voter subset or legal population count. |
| G2 assurance ordering and prior signer identity | Rotate voter subsets, sort wire indices, sign against the actual prior roster. | Duplicate/unsorted/out-of-domain index generation remains open; [reporting tests](../tests/test_current_stf_population_reporting_oracle.py) retain their exact prior evidence. |
| G3 assurance parent binding | Alter one parent anchor, then re-sign the changed assurance so signature failure cannot mask WrongParent. | Other ancestry faults remain under their existing contracts. |
| G4 assurance signatures | Corrupt one signature with the original anchor/bits/index unchanged. | This is not exhaustive malformed-signature or crypto testing. |
| G5 selected guarantee roster | Sample current and immediately previous credentials at epoch boundaries with genuine assigned keys. | Other credential ages and legal roster sizes remain open. |
| G6 current erasure width | Re-sign a report with the other supported width (six versus nine); require WrongErasureShards. | Full-scale erasure/coding qualification remains separate. |
| G7 guarantee signatures | Corrupt one credential signature while preserving the signed report and other credentials. | Further credential/order/assignment invalid classes remain open. |
| G8 replacement after release/resize/timeout | Generate guarantees only on independently calculated replaceable cores; compare complete C10 and actual release before clearing. | Invalid occupied-core probes and exhaustive exact-timeout combinations remain open. |
| G9 contextual anchors and account code | Construct current-code, recent-anchor reports from each current expected parent. | Generated wrong-code, duplicate-package and invalid-anchor classes remain open; historical references are not relabeled as generated passes. |
| G10 authorization and whole-state integration | Compare all complete keys/values, including authorizer consumption, history, statistics, guest effects and roots. | General privileged updates and unrelated STF families are outside this sampler. |
| G11 actual execution and rollback | Include all three existing literal guest exit profiles; verify actual released operand counts and preserved balances separately. | No generated arbitrary guest code, gas offers, dependencies or transfers. |
| G12 rejection atomicity | Submit every malformed block before the valid child in the same chain; the driver checks exact typed refusal and retained parent map/header. | Local policy/infrastructure failures never count as protocol-invalid passes. |

The distinguishing wrong-model checks require sampled witnesses against `>=`
quorum, posterior-roster quorum and prior-roster erasure width. An additional
mutated posterior removes actual service participation and must fail the separate
accounting invariant. These are scoped sensitivity checks, not a general mutation
score or proof that the independent reference is bug-free.

## Sampler, replay and reduction

[The independent generator](../tests/current_stf_generated_oracle.py) fixes
SHA-256(seed E4 || draw ordinal E4) and byte positions as its portable decision
sampler. Seeds are unsigned 32-bit integers. Twelve ordered windows cover slots
2..31, including11/12 and23/24. Each chain starts from the authored original map;
the first retained event establishes lookup history before report generation.
The fixed regression seeds are1,2,7,42,2026, selecting all three guest modes.

Decisions choose slot spacing, eligible guarantee cores/services, assurance masks,
zero/exact/above quorum, voter rotation and boundary credential age. Reports have
no dependencies and use existing fixed100000 gas offers. Native execution uses
the existing explicit `lateHistories` test policy; production/default policies
and protocol pins remain unchanged. This is a bounded three-core six→nine→six
campaign, not random arbitrary-state injection.

Expected successors recursively become reference parents. Neither observed native
maps nor advertised posteriors feed that computation. Frozen fixtures bind source
fixture hashes and each complete checkpoint/root; source-owned corpus registration
uses the existing checked driver, comparator, process budgets and provenance.
Normal verification remains `make check-python` and `make check-corpus`; Make
owns provisioning of the pinned sources and native build dependencies.

[The campaign tool](../tools/stf_generated_campaign.py) supports additional seeds
and saved-decision replay without another build path. Build the checked native
scenario binary through the registered `current_stf_generated_corpus` first, then:

```sh
python3 tools/stf_generated_campaign.py --seed 42 --output build/generated-seed42
python3 tools/stf_generated_campaign.py --seed 42 --output build/replayed-seed42 \
  --binary build/db5-reporting-scenarios/current-stf-reporting-scenarios-late-histories
python3 tools/stf_generated_campaign.py --case build/replayed-seed42/original/case.json \
  --output build/reduced-seed42 --minimize \
  --binary build/db5-reporting-scenarios/current-stf-reporting-scenarios-late-histories
```

The binary path above is a retained local build example, not a requirement that a
clean checkout contain that path. The fixture is the existing pinned
`tests/fixtures/state-report.bin`; `--fixture` accepts its explicitly provisioned
location. Saved posteriors are ignored. Every run writes independent requests,
expected complete output, decisions, hashes and (when executed) actual stdout,
stderr, exit status and comparison verdict. Generation-only manifests have
`passed: null`; they cannot claim native execution.

On an actual mismatch, `--minimize` deletes events, regenerates every trial from
the original state and retains original/trial/final artifacts. It preserves the
coarse comparator class (exit code and first differing record kinds), not a proved
identical root cause. Revisited singleton deletions establish deletion-1-minimality
among nonempty event histories for that predicate; this is not global minimality
of blocks, fields or instructions. Timeout/launch errors abort reduction instead
of becoming protocol refusal evidence. Fixed source, executable and deterministic
behavior are prerequisites; the final reduced run must reproduce its failure class.

## Completion and remaining work

Completion for this increment requires the G1–G12 matrix to have an explicit
evidence/gap disposition, the full frozen campaign to match native output,
independent invariant/sensitivity tests and reduction tests to pass, real saved
replay to pass, and inventory/format checks to pass. Execution results are recorded
below after verification. Failures must become focused regressions/fixes or explicit
specification ambiguities; expected answers must never be adjusted to match a client.

Next bounded work follows the explicit gaps: generated reporting validity classes
and exact admission boundaries, then generated disputes/offender histories and
accumulation dependencies/budgets/lifecycle. Each needs its own normative rules
and acceptance criteria. A finite seeded campaign, M1 framing completion and current
serialization qualification do not establish full STF/JAM or live interoperability.


## Observed verification (2026-10-26)

All60 signed transitions/five seeds and112 typed invalid-block refusals match on
checked macOS and Linux. Request, expected-output and actual-output SHA-256
identities match across hosts. Linux image
`sha256:336159a40b8ecc1c45153e17f3ef6796ea6d3950d9184d108810fa42835041d6`
(`ragnarok:db5-generated-final`) retains8,441 matching frozen source/native inputs.
Both runs use ARC/Clang release with bounds/assertions and the established
non-LTO corpus profile; each runtime keeps its180-second limit. The emulated
Linux compile alone retains the existing900-second ceiling.

Thirteen independent reference/tooling tests pass, including complete frozen
answers, participation/balance checks, wrong-model sensitivity, nonmonotone
reduction, complete output framing and honest timeout/generation-only verdicts.
Real seed replay and saved-decision replay pass. A separate sparse-history native
replay passes after removing a generator-only dependency-template assumption:
a late dependency-free report must still be constructible after old package pairs
leave history. The default campaign's frozen answers remain unchanged by that fix.

An explicitly injected wrong expected output exercises actual-driver reduction
from twelve events to one in seven trials. This is tooling self-test evidence;
it is not an observed STF bug or an independent conformance pass. No production
STF discrepancy was found in this bounded campaign, and no production fix is inferred.

Inventory, pinned formatting for4,822 Nim sources/Rust, changed-document links,
all ten named GP labels and whitespace checks pass. Exact-head PR Smoke remains
separate CI evidence. The selected generated gaps above remain open; passing this
campaign does not close full STF/JAM correctness.

Retained evidence: `build/current_stf_generated_corpus-linux-evidence.json`,
`build/current_stf_generated_corpus-linux-inputs.json`,
`build/db5-reporting-scenarios/current_stf_generated_corpus.json`,
`build/db5-generated-python-final.log`, `build/db5-generated-tool-tests-final.log`,
`build/db5-generated-real-replay/`, `build/db5-generated-saved-replay/`,
`build/db5-generated-sparse-final/` and `build/db5-generated-reduction-selftest/`.
