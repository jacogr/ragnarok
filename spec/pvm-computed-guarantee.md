# Source-bound computed guarantee transcript

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
reporting_assurance.tex guarantorsig and serialization.tex workreport.
Vector pin remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume one immutable ComputedWorkReport, hash its exact complete canonical
wire once through the existing guaranteeMessage primitive, and retain the original
report alongside the nominal GuaranteeMessage. The transcript is ASCII
`jam_guarantee || BLAKE2b-256(report)`, exactly 45 bytes. No slot, credential,
caller-provided report bytes, detached digest or substitute context is accepted.

Check the source before local policy. Before copying report bytes or invoking the
backend, require ByteLimit to cover the 45 retained transcript bytes and the full
temporary report-wire copy. The original source's retained allocation is shared
and excluded; fixed owner metadata and primitive stack scratch are excluded.
Prove the budget by subtraction before copying. Defaults and failures expose only
reasons. Backend failure retains no candidate owner. Fixed message extraction
copies; source extraction shares the original immutable provenance.

This is a signing transcript, not a signed guarantee or permission to sign. Root
and state authenticity, active roster equality, assignment, evaluation-slot
eligibility, availability distribution/assurance, credential collection and C10
publication remain separate gates. In particular the original import-root lookup
and claimed anchor roots are not authenticated by hashing the report.

Completion coverage: five independent full-report hash
witnesses from the existing literal report oracle; exact domain and no slot;
one hash per success, none for invalid source or refused policy; exact and one-byte
short budgets including maximum unsigned policy; backend refusal/recovery after
real source preparation; source retention, fixed-copy isolation, detached lifetime
and 1000-cycle ARC release; compiler privacy/source/policy nominal rejection;
optimized default/failure/accessor guards with a genuine known-answer control.

Next: [computed lookup correspondence](pvm-computed-links.md), then authenticated
state/anchor provenance before signing eligibility and guarantee publication. M1 framing is complete; full state serialization remains open.

Local evidence: `make unit SUITE=pvm_computed_guarantee` passes under checked
optimized ARC/Clang on macOS ARM64. Five independent full-wire/hash witnesses
cover empty, single, mixed error, page-boundary exports and nonempty original
context/trace/output/import lookup. The literal expected token plus those report
hashes match all 45 transcript bytes. One hash per accepted preparation, zero on
invalid source or short policy, primitive refusal/recovery, unchanged existing
transcripts after failure, exact/short/maximum policy, copied message/report wire
isolation and detached report lifetime pass. Fresh 1000-cycle ARC occupancy is
924032/924032 bytes for the isolated warmed workload.

Six strict optimized result/accessor rejection probes pass with an independently
validated complete report and transcript positive control. Five compiler guards
reject private owner/tag/payload access and nominal source/policy substitutions.
Formatted unit/driver semantic checks, inventory, 20 affected inventory/provenance
tests and pinned formatting pass. The prior independent report oracle evidence
is reused after verifying 234 protocol/oracle/build inputs byte-identical;
production report encoding and primitive composition are unchanged. Full logs,
source identity and reuse proof are in ignored `build/computed-guarantee-*` files.
Exact-head Linux CI remains separate; remote checks were not requested.
