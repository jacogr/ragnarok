# Linux compiled PVM verification

## Scope and authority

The Gray Paper remains primary; PolkaVM is the pinned test-only cross-check. This
change enables its existing sandboxed x86-64 compiler backend on dedicated ephemeral
GitHub-hosted Ubuntu 24.04 runners. It changes no protocol interpretation, source pin,
local kernel setting, production build or experimental backend feature.

The pinned PolkaVM workflow `.github/workflows/rust.yml` at
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` enables
`vm.unprivileged_userfaultfd=1` and
`kernel.apparmor_restrict_unprivileged_userns=0` before Linux tests. The corresponding
sandbox initialization checks are in `crates/polkavm/src/sandbox/linux.rs`. The first
Ragnarök Linux benchmark, run 39583053110 at `e33460e5`, succeeded with explicit
unavailable compiled cells because both facilities were restricted. That run is
historical evidence, not evidence for the changes described here.

## Completion checks

A manual `pvm-compiled` scope runs all discovered public-reference/native fixture
pairs with `RAGNAROK_PVM_REFERENCE_BACKEND=compiler`. The manual `bench-pvm` scope
requires that correctness job to pass before measuring the same three-engine table.
Both jobs configure the pinned upstream sandbox prerequisites on their own hosted VM.
Ordinary full verification retains the interpreter job and does not enable these
settings. Summary/artifact steps retain failures as well as successful results.

The benchmark requires actual compiled samples in CI; local unsupported hosts may
still report unavailable. Record the requirement and observable Linux sandbox kernel
values in raw metadata. Check missing compiled samples, malformed settings, stale
success handling, workflow scheduling/dependency and unchanged pinned source hashes.
Obtain an exact-head Linux run before claiming compiled execution or timings.

Full upstream differential fuzzing remains a separate future CI obligation.

## Local verification

All 54 selected benchmark, runner, summary and CI safeguards pass. Workflow YAML
and the compiled correctness dependency parse successfully; inventory and diff
formatting checks pass. Native PVM source and fixture trees match merged master,
so their existing checked ARC/LTO evidence is reused. Compiled execution awaits
the exact-head hosted run; Apple Silicon cannot supply that backend locally.
