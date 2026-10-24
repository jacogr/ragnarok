# Fixed opcode execution classes

## Scope and invariants

The existing interpreter repeatedly tests register/memory/control opcode sets while choosing its
private evaluator. A fresh checked diagnostic profile after the dynamic-target cache ranks that
loop prominently; ARM64 inspection identifies the repeated register-opcode bitmap lookup among
its hot locations. Sampling identifies a candidate cost, rather than a deterministic counter.

A private256-byte constant now classifies each opcode as register, memory, host, control or
unsupported. One bounded byte lookup selects the existing checked handler. This table is fixed
metadata for the instruction set, independent of captured programs. It creates no decoded program
representation, preparation pass, owner reference, allocation, new caller policy or public API.

Every evaluator retains its capability boundary before gas pricing and affordability. Register-only
stepping cannot authorize control, memory or host instructions; the broader entry points preserve
their existing hierarchy. Unsupported instructions remain local refusals, including at zero gas.
All handlers, gas debits, instruction/address checks, host transitions and memory preflight remain
unchanged. The table covers all256 byte values, while capture still rejects reserved opcodes.

Gray Paper/PVM pins and the independently tested arithmetic/memory/control semantics are unchanged.
Checked ARC/Clang ThinLTO builds, source preservation and complete outcome validation remain
mandatory. No bounds/assertion checks are disabled to obtain the measurement.

## Verification plan and evidence

The stepping suite checks every valid opcode through all four public capability scopes under
both dynamic and complete-plan pricing. A supported zero-gas instruction must stop OutOfGas;
an unsupported scope must refuse before pricing, with the source CPU unchanged. Existing frozen
register/control traces, independent arithmetic/dependent-register corpus, cache collision/nesting
and host memory replacement/fault-retry suites retain their actual state/ownership assertions.

Before/after binaries replay the maintained indirect, memory-fill and sieve guests at limits1000
and100000 in all three pricing modes, reversing order and retaining cold/preparation observations.
Every invocation checks complete expected CPU, mapped bytes/permissions and retained input state.
Each paired comparison retains936 validated invocations. Small synthetic guests are an additional
control against changing the interpreter for one workload alone.

Raw build identities, samples and selected suite logs remain under
`build/pvm11/opcode-classification/` and `build/pvm11/scalar-copy/opcode-class-*-paired.json`.
A direct-range classification experiment regressed the representative workloads and was reverted.
Local Apple M1 Max results establish neither Linux performance nor whole-JAM throughput. M1 framing
is complete within its documented scope; full state serialization and whole-JAM/STF equivalence
remain open. Fuzzing remains paused pending maintainer Daybreak access.

## Observed local completion

All139 valid opcodes pass1112 capability/pricing cases, alongside the selected stepping,
execution-cache, arithmetic, dependent-register and host memory reentry suites. Pinned formatting
passes; their selected ARC lifetime observations remain balanced. Reserved opcodes remain capture
failures and never reach this private table.

The final formatted production source matches the retained checked binary. Three representative
paired comparisons agree on the indirect/memory-fill improvement and the smaller lazy-sieve
regression. Final large-workload CPU medians in milliseconds are:

| Guest | Policy | Parent | Classified | Change |
| --- | --- | ---: | ---: | ---: |
| Indirect calls | Dynamic | 29.654 | 27.466 | -7.4% |
| Indirect calls | Complete | 29.023 | 27.882 | -3.9% |
| Indirect calls | Lazy | 28.799 | 27.600 | -4.2% |
| Memory fill | Dynamic | 13.619 | 12.964 | -4.8% |
| Memory fill | Complete | 12.428 | 11.863 | -4.6% |
| Memory fill | Lazy | 13.437 | 12.861 | -4.3% |
| Sieve | Dynamic | 17.033 | 16.648 | -2.3% |
| Sieve | Complete | 11.743 | 11.670 | -0.6% |
| Sieve | Lazy | 12.366 | 12.695 | +2.7% |

The lazy-sieve tradeoff repeats at about3%, so no universal speedup is claimed. The separate
11-guest synthetic comparison retains1716 fully validated invocations across both process orders
and all three policies. Substantial rows are approximately neutral or improve: dynamic arithmetic
is1.5% slower, while memory/host/mixed-bit/sparse/alternating-block cases generally improve.
The one-instruction planned arithmetic median changes0.125 to0.166 microseconds; these tiny elapsed
measurements approach timer granularity and remain visible in the raw report. Synthetic timings
use the established elapsed-time driver, rather than the real-guest process-CPU metric.

Final records are `build/pvm11/scalar-copy/opcode-class-verified-paired.json` and
`build/pvm11/opcode-classification/synthetic/results.json`; the earlier two comparisons remain
available. This bounded tradeoff preserves the existing short-call behavior and improves both
maintained indirect and sustained memory workloads without source-specific preparation.
