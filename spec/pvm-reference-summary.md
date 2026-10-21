# Actions PVM comparison summaries

The maintainer selected the GitHub Actions run summary as the primary place to read
comparison tables, with raw downloadable measurements and environment details.
This increment applies that delivery pattern to the existing deterministic correctness
job. Performance measurements remain a later workload; no execution durations are
presented as comparative speed numbers.

The job always runs `make summary-pvm-reference`, including after setup or comparison
failure. The existing summary CLI calls a PVM-specific renderer over the fresh
`results.json`. Each declared comparison occupies one row with its PolkaVM and native
suite verdicts. Missing processes are explicitly Not run; nonzero exits are Fail.
The reference build, completed-pair count, recorded head, specification/source pins,
Rust pin and platform are shown alongside the table.

A successful status requires every declared pair, both process verdicts, a successful
reference build, complete ordered completion identities and no duplicate/unknown
stage records. Missing/failed stages cannot be hidden behind a successful top-level
status. Partial failures retain their observed rows and bounded error reason.
External prose is bounded and escaped before insertion into Markdown.

The job's artifact contains `summary.md`, `results.json` and diagnostic logs.
`--artifact` replaces the downloadable Markdown with precisely the newly rendered
section while the Actions output appends it to the job summary. Missing/malformed
reports write an explicit unusable-report section, replace any stale downloaded
success and fail the helper. The original comparison command's exit status remains
the authoritative job verdict.

Local tests cover complete and partial tables, forged success, missing/duplicate/
unknown/failed stages, malformed exit codes, missing report handling and exact
Actions/downloaded Markdown equality. Existing summary and workflow safeguards also
run because this extends their shared CLI. No production PVM behavior or upstream
pin changes. Linux execution is capability added by the preceding CI layer, not a
claimed remote result.

## Observed local evidence

A fresh complete Make comparison run passed all eleven declared pairs and produced
the Actions preview plus identical downloadable Markdown. The focused shared summary,
workflow and reference-runner checks pass (54 tests initially, 40 in the final selected
summary/workflow check), along with inventory. Native/Rust source and profiles are
unchanged from the preceding verified layer, so their formatting evidence is reused.
