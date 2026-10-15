# Ragnarok JAM implementation language decision

Independent architecture assessment • 15 October 2026

Reviewed revision d4462defced3cf08914e9e5f4f1919a56bccbe9f

## Recommendation

Choose Nim and conclude the three-language evaluation. Proceed with the full independent JAM implementation using ARC and checked optimized builds, retaining the demonstrated LTO configuration for the report paths. Confidence is moderately high for this engineering decision; this is not a prediction that Nim will win every future workload.

The evidence now supports a decision: competitive measured protocol performance, fewer manual ownership obligations, working unpatched native networking integration, and encouraging implementation ergonomics. Odin remains a credible alternative with stronger explicit allocation control and excellent performance. Mojo has demonstrated feasibility, but the current implementation offers no decisive advantage over the other two.

## Performance is sufficiently resolved for selection

The complete-report experiments exercise bounded nested protocol structures, including capture, canonical re-emission and owner retirement. They are more relevant to the decision than isolated byte-copy and integer-sequence tests. Recorded macOS medians below are microseconds per operation; lower is better.

| Operation | Nim checked LTO | Odin | Mojo |
| --- | --- | --- | --- |
| Four-digest report decode | 0.426 | 0.409 | 2.108 |
| Four-digest report encode | 0.621 | 0.398 | 1.850 |
| Four-digest report owned cycle | 0.703 | 0.745 | 2.538 |
| Maximum-payload report encode | 2.214 | 1.694 | 6.200 |
| Maximum-payload report owned cycle | 3.788 | 4.306 | 7.739 |
| Maximum-lookup report encode | 0.440 | 0.173 | 1.374 |

These are authored workload shapes, not a measured traffic distribution. The largest Nim borrowed-encode disadvantage in this corpus is approximately 0.52 microseconds per report. Odin’s integer-sequence advantage remains real, but no longer supports a broad objection that Nim entails unacceptable codec overhead.

The faster Nim and Mojo combined crypto pipeline substantially reflects BoringSSL versus Odin’s current provider. Switching Odin to BoringSSL could change that ranking. No language-selection credit is assigned to that provider difference.

[Evidence — report results and methodology, lines 42–93](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/results/work-report.md#L42-L93)

## Ownership is the strongest reason to choose Nim

Verified fact: Nim’s opaque OwnedReport automatically retains private immutable storage when copied. Capture validates the complete report before retaining bytes. This removes particular retain and release obligations from callers.

Odin requires one release owner, an allocator that outlives the object, and aliases that stop being used before release. Its allocation-failure cleanup is clear and useful. Mojo’s current report API also uses a copyable opaque pointer with explicit release, so it does not obtain an automatic lifetime advantage over Odin at this boundary.

Engineering inference: automatic retention becomes increasingly valuable as reports move through queues, caches, validation, cancellation and asynchronous operations. This supports the selection without claiming that ARC eliminates foreign-pointer hazards, races, cycles or state-machine mistakes.

[Nim report ownership, lines 4–43](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/nim/src/report_owned.nim#L4-L43)

[Odin report ownership and allocation cleanup, lines 4–78](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/odin/codec/report_owned.odin#L4-L78)

[Mojo report ownership, lines 17–48](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/mojo/codec/report_owned.mojo#L17-L48)

## Implementation experience supports the choice

Three prospectively recorded rounds cover complete reports, assurances and assurance signing contexts. Each language occupied each implementation-order position once.

| Recorded metric | Nim | Odin | Mojo |
| --- | --- | --- | --- |
| Compiler repair cycles | 1 | 6 | 7 |
| New implementation LOC | 552 | 715 | 753 |
| Confirmed native defects after compilation | 0 observed | 0 observed | 0 observed |

The results support a limited observation of lower compiler-repair friction in this workflow. Shared agent context and sequential learning remain confounders. Compiler rejection can also be useful protection; neither repair counts nor physical LOC establish reliability or a development-speed ratio.

The latest assurance-context implementation was straightforward in both Nim and Odin: fixed owned fields, explicit configuration checks, parent binding, and complete structural preflight before signature verification. All three candidates passed the recorded checks; there is no measured defect-rate winner.

[Recorded implementation rounds and limitations, lines 200–233](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/results/ai-ergonomics.md#L200-L233)

[Nim assurance context, lines 73–125](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/nim/crypto/assurance_context.nim#L73-L125)

[Odin assurance context, lines 70–116](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/odin/crypto/assurance_context.odin#L70-L116)

## Remaining risks and decision implications

| Issue | Implication for selection |
| --- | --- |
| Ed25519 acceptance policy and backend choice | Does not delay selection. Resolve before consensus-critical deployment; all candidates can use the chosen provider. |
| Crypto audit and historical Bandersnatch provenance | Shared security work, not a demonstrated language discriminator. |
| Networking scale and independent-peer interoperability | Feasibility is established. Production scale and impaired-network qualification remain necessary. |
| Nim allocation exhaustion is fail-stop | Could change the decision if recoverable allocation failure is a hard requirement. Odin’s strongest architectural counterargument. |
| PVM, storage and state-transition performance | Unmeasured. Profile during implementation; no need to extend the language evaluation indefinitely. |
| Shared specification or oracle errors | Retain independent validation. Three agreeing implementations can share the same misunderstanding. |

The corrected tiny-profile labeling illustrates the shared-oracle risk. Official standalone report fixtures also have empty dependency collections. Authored boundary cases extend coverage but do not become independent published vectors.

[Published report fixture coverage, lines 38–40](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/results/work-report.md#L38-L40)

[Assurances evidence and tiny-profile correction](https://github.com/jacogr/ragnarok/blob/d4462defced3cf08914e9e5f4f1919a56bccbe9f/results/assurances.md)

## Verification and limits of this review

Reviewed current code, ownership APIs, assurance signing contexts, benchmark harness and implementation journals. Independently reran four assurance-oracle tests and twelve measurement-integrity tests; all passed. Inspected the benchmark source manifest: report implementations remain matched to the recorded benchmark, while four recorded supporting files have subsequently changed. The full native suites and timing experiments were not rerun. No repository source changes were made.

At the time of review, the completed 27f215d Linux run passed complete-report builds, correctness checks, benchmark execution, assurances and networking suites. The current revision’s run was still in progress. Successful benchmark execution is not treated as evidence of particular Linux timing ratios.

[Completed Linux run for 27f215d](https://github.com/jacogr/ragnarok/actions/runs/38714676313)

[Linux run for reviewed revision d4462de](https://github.com/jacogr/ragnarok/actions/runs/38720815259)

## Decision and conditions for reconsideration

Select Nim. Keep independent fixtures and comparative implementations as references, but stop requiring three implementations of each new feature. Reopen the decision for a concrete blocker, a hard requirement for recoverable allocation failure, or a measured full-client performance requirement that Nim cannot meet economically. A further microbenchmark lead alone is not sufficient reason to restart the selection process.
