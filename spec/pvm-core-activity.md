# Per-block core activity

Use GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, statistics.tex
Cores and Services, and pinned vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Derive R(c) and bundle bytes from incoming guarantees, DA load from newly
available reports (bundle bytes plus 4104 * ceil(65 * segments / 64)), and
popularity from every original assurance bit. Failed refinement contributes
its usage; authorization and accumulation gas do not. Rebuild all profile core
rows, including zeros, without retaining old per-block values.

A pure projection borrows stable report owners and raw assurance records; it
certifies no signatures, uniqueness or admission. An opaque preparation derives
all three families and the core profile from one genuine AdmittedReports owner,
retains that exact source, and exposes copied rows through guarded accessors.
Bound counts, incoming digests and core-bit work before output allocation.
Preparation also bounds assurance encoded bytes before materializing votes. Validate raw padding/profile/owners, prove every uint64 sum,
and return typed local CounterOverflow without partial output or state writes.

Completion tests cover independent source families, padding boundaries, literal
DA ceilings, failed refinement, zero rows, exact/short/full-width limits,
overflow, guarded/private results, copied/source lifetime and 1,000 hash-free ARC
cycles. Preserve codecs and pins. Validator epoch counters and complete C(13)
publication remain separate work. M1 framing is complete; full state
serialization and block parity remain open.

## Local verification (2026-10-19)

The selected report_admission suite passed under the pinned Nimony compiler,
checked ARC/Clang LTO and prepared native libraries. Signed incoming-only,
incoming-plus-available and available-only sources produced exact independent
core tuples. Each source preparation completed 1,000 hash-free ARC cycles
without retained growth. The enclosing suite retained fresh 1,000-cycle evidence:
293,232 occupied bytes before and after. Detached owners retain the original
admission graph; copied rows cannot mutate private metrics.

Pure witnesses compare all eight fields, failed-refinement usage, all-zero rows,
DA rounding at 0/1/63/64/65/65535 segments and maximal uint32 bundle length.
The maximal single-report DA term is 4,568,125,431 bytes. Tests cover two-core
and 341-core padding, invalid owners/core profiles/indices, independent short
limits, full-width ceilings and uint64 counter/gas overflow. Pure raw inputs
remain explicitly unverified; source preparation accepts only AdmittedReports.

Five strict extraction guards, three privacy rejections, one nominal source
rejection and the new module's semantic compilation passed. Source-owned
inventory and its nine tooling tests passed. Changed Nim sources passed pinned
formatter idempotency; whitespace and local feature links were checked. Logs
are retained under ignored build/pvm-core-activity*. These are local macOS
checks, separate from exact-head Linux CI. No runtime, codec or dependency pin
changed.

Next bounded work: validator epoch counters, followed by complete C(13)
assembly/publication. M1 framing remains complete; full state serialization and
block parity remain open.
