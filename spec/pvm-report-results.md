# Ordered refinement report results

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`work_packages_and_reports.tex` computation of work-report, function I;
`reporting_assurance.tex` limitworkreportsize and definitions Cmaxreportvarsize;
vector pin `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: execute all original owned package items in order through their own bound
bootstrap/invocation. Derive each export offset from preceding declared export
counts, including failed items. The supplied authorization trace is explicit input,
not proof of authorization. Reject traces exceeding 49152 bytes before execution.
The shared protocol blob budget includes that trace and only preceding accepted
Success outputs. Oversize precedes BadExports; BadExports precedes preserving an
invocation work error. Every error substitutes exactly the declared number of zero
4104-byte segments. Error results consume no successful blob budget. Preserve gas.

Return private immutable acyclic owners retaining the original package/item and
normalized selection. Rejected raw output/exports are released before the next item.
Metadata is copied, bytes are copied, zero replacements are synthesized
on bounded indexed extraction. Never accept detached result/source tuples. Local
bootstrap, invocation or retention refusals fail the entire operation, without
publishing a partial prefix. Per-item execution policies and aggregate item/export/
blob retention caps are independent of protocol selection. Fixed package bounds
limit all loops; check full-width arithmetic before narrowing or allocation.

Completion tests: real multi-item guests; exact/over shared budget, precedence,
error-budget exclusion, BAD/BIG/panic/OOG replacements, declared-offset behavior
through failed items, package export boundary, zero declarations, late local
rollback, source lifetime/replay/copy isolation, default/index/output refusals,
optimized result/detail guards, compiler privacy/nominal rejection and fresh
1000-cycle ARC release. Regress the invocation normalizer; check inventory/format.

Local evidence: checked optimized native `pvm_report_results` and
`pvm_refinement_outcome` pass with fresh 1000-cycle ARC release, respectively
448096/448096 and 400192/400192 occupied bytes. Twelve optimized runtime
alternative/owner/index/output guards, six compiler privacy/nominal rejections,
19 inventory/provenance Python tests, verification inventory and pinned formatting
pass. These are local macOS results; exact-head Linux CI remains independent.

Next bounded work: construct item-to-digest C from these source-bound final items.
Deferred: item-to-digest C, authenticated authorization/input/freshness checks,
segment-root dictionary/availability/erasure report assembly and publication.
State retains block composition/publication; no state-transition contract changes.
M1 framing is complete; full state serialization and complete JAM parity remain open.
