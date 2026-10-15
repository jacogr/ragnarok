# Complete-report AI-assisted implementation observations

This is the authorized report/guarantee increment, not an artificial task created for metrics.
The [preregistered contract](plan.json) defines identical functionality and acceptance checks.
Raw compiler/baseline logs and reduction sources are retained in
[compiler-attempts.tar.gz](compiler-attempts.tar.gz), with a
[per-member hash index](compiler-attempts-index.json). From the repository root,
`tar -xzf results/work-report/compiler-attempts.tar.gz` restores the log paths named below.
The original completed journals remain standalone JSON files.

Each native candidate passed 18,197 shared report requests and 42 independent OpenSSL composition
checks, plus the existing three-language codec baseline. The direct attempts and source snapshots
are retained in [Nim](nim.json), [Odin](odin.json), and [Mojo](mojo.json) journals.

| Metric | Nim | Odin | Mojo |
| --- | ---: | ---: | ---: |
| Compiler repair iterations | 0 | 5 | 4 |
| Comparable time to passing tests | N/A | N/A | N/A |
| Confirmed native defects found after compilation | 0 observed | 0 observed | 0 observed |
| New implementation LOC | 338 | 480 | 513 |
| Additional human interventions after registration | 0 | 0 | 0 |
| Confirmed regression checks / passing baseline checks retested | 0 / 1 | 0 / 1 | 0 / 1 |

These are observed task counts, not historical estimates or evidence of zero latent defects.
[Machine-readable results](ergonomics.json) separate the unavailable comparable-time field from
real journal wall intervals. The [reviewed LOC manifest](loc-scope.json) and [snapshot](loc.json)
count only the three new codec/owner/guarantee modules in each language. Tests, drivers, benchmarks,
shared infrastructure, dependencies and reused primitives/digest codecs are excluded. Physical
brace/import/declaration layout affects LOC; it is not a ranking criterion.

The raw intervals to the final-source acceptance frontier were Nim **17.08 minutes**, Odin
**30.53 minutes**, and Mojo **24.18 minutes**. Shared oracle, metadata and benchmark preparation
fell within these interleaved clocks, and architecture analysis preceded registration. These
numbers are operational elapsed intervals, not comparable equivalent-task development times.
Order was Odin, Mojo, Nim for initial native implementation, then interleaved measurement work.
The same agent could inspect all previous code. Exact serving-model/reasoning metadata is N/A.
See the [shared setup limitations](shared-infrastructure.md); do not rank development speed here.

All observed Odin repair cycles concerned language/API usage: immutable type-switch values,
addressable local copies of immutable parameters, package declaration and strict unused-variable
checks. Its first failed attempt also lacked `-no-entry-point` for a library check; this mixed
infrastructure/language cycle is retained once. The diagnostic is in `odin-0002.log`.

Mojo had three language/API repair cycles (explicit copies, integer shift operand types, and a
read-only borrow annotation) and one compiler repair cycle. A nested decoded-result/work-output
mutation crashed the compiler at both -O0 and -O3. A local typed digest with the same semantics
resolved it using ordinary public APIs. `mojo-0003.log`, `mojo-0004.log`, the preserved
[crashing source](mojo-before-local-digest.mojo.txt), [entrypoint](mojo-compiler-entrypoint.mojo.txt),
and reduction sources retain the evidence. Intentional reductions/rejection probes are diagnostic
attempts and contribute no repair iterations. This required no compiler patch or private hook.

Every compiler rejected a segment root assigned to a package hash: Nim `nim-0011.log`, Odin
`odin-0015.log`, Mojo `mojo-0028.log`. This demonstrates a concrete domain-swap safeguard.
Mojo also rejected overlapping borrows caused by an overly broad mutable helper annotation
(`mojo-0022.log`); changing the read-only helper's convention resolved it without unsafe casts.
Do not describe that conservative rejection as an observed runtime aliasing bug.

A shared fixture-infrastructure error used `public_key` instead of the pinned RFC fixture's
`public` field. It was corrected during setup and is documented separately, not counted as three
native defects. A subsequent CI diagnostic wrapper wording mismatch is also recorded in the shared
setup note, outside the completed native cohort. No library/FFI defect or test-confirmed native regression was found in this task.
The one-check regression denominator is the entire existing shared codec suite, not the number
of assertions hidden inside it. Further increments are needed for meaningful defect-rate evidence.

Tool outputs, settings and check/formatter pins are retained in the journals and LOC snapshot:
Nim 2.2.12 ARC with checked Clang LTO; Odin dev-2026-10:84bc3fc21 with -o:speed/-vet/-strict-style;
Mojo 1.1.0 (8189361e) -O3; Apple clang 21.0.0; Python 3.14.2; macOS 27.0.1 arm64 / Apple M1 Max.
Compiler versions did not drift. The configuration-drift flag is true because the Linux workflow
was extended with this increment and explicit lld support; its before/after hashes are retained.
The [performance artifact](comparison.json.gz) records exact build flags and source/binary hashes.

Nim had the least observed compiler-repair friction in this task and provides automatic retained
report ownership through ARC. Odin and Mojo still place one-release-owner/borrowed-alias duties
on callers. Those ownership obligations support a provisional Nim architectural preference;
all three passed the same tests, so this task does not demonstrate lower defect rates for Nim.
Fewer repairs and fewer lines alone would not establish the most reliable AI-assisted language.
