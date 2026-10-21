# Linux PVM reference verification

The independent `pvm-reference` job in the canonical CI workflow executes
`make check-pvm-reference` on native Ubuntu. It uses the
[source-owned comparison runner](pvm-reference-runner.md) without altering the
Gray Paper, PolkaVM, Nimony or Rust pins, guest expectations or production dependencies.

Master pushes and explicit full verification requests select the job. Unit/e2e/Docker
requests preserve their existing scopes. Opening PRs or pushing commits does not
request CI; maintainers retain the existing label/manual request mechanism. No
remote run is requested merely by introducing this job.

The job has its own inventory preflight, setup and process verdict. It does not depend
on another job's artifacts or success. The Make target provisions its own dependencies;
the workflow does not duplicate Cargo, source or compiler bootstrap steps. Reference
and paired native checks remain serial within the owned workspace.

An [always-run summary](pvm-reference-summary.md) shows each comparison directly in
the Actions run and writes a matching downloadable Markdown table. An always-run
artifact step retains that table, the current structured report, reference/native
logs and selected native fixture preparation metadata for seven days. It excludes
binaries, generated fixture bytes, dependency trees and keys. Failure before report
creation still exposes setup logs; an absent report is never claimed as a passing
comparison. Neither continue-on-error nor output-pipe status masking is used.

Local safeguards verify exact trigger scope, independent inventory preflight,
one invocation of the supported target and restricted failure-evidence collection.
The preceding runner increment passed all declared pairs on macOS. This workflow
change adds Linux execution capability; it does not claim a Linux run occurred.

This is deterministic correctness CI. The required complete upstream fuzzing coverage
and differential bridge remain a separate future job. Future benchmark CI must validate
outputs before timing and use the consolidated Ragnarök/interpreted/compiled table
recorded in the runner contract.
