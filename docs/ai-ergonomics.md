# Measuring AI-assisted development ergonomics

This protocol applies to subsequent **authorized** native implementation increments. The current
[comparison](../results/ai-ergonomics.md) audits the completed M1/M2/M3 POC. It does not turn old
commits, successful test runtimes, overwritten logs or chat recollections into measured development
histories. Unknown historical values are N/A, including an unknown count that might have been zero.

## Equivalent tasks

Before the first candidate starts, preregister one plan for all three languages. Record:

- An equivalence ID, exact functionality, pinned specification and required error/ownership behavior.
- Identical acceptance check IDs and semantics, with concrete per-language command arrays.
- Identical existing baseline check IDs/granularity and their per-language command arrays.
- Source paths per candidate, including affected tests, configuration and project-owned FFI support.
- Actual compiler versions/flags, allocator/runtime modes, optimization/check settings and environment.
- AI model/version, reasoning setting, context/reference access and agent arrangement; unavailable
  metadata stays explicitly N/A. Do not infer a historical model from the current session.
- Candidate order. Counterbalance order across real increments so each language takes each position.
- The LOC definition and reviewed task-specific file/inline-test scope used at completion.

Provision pinned toolchains and common fixtures/oracles before candidate handoff; record shared
setup separately. Start the journal when the registered task is handed to its coding agent, before
implementation analysis or edits. No unlogged implementation work may precede the clock. The
measured wall time includes development, compiler/test execution, pauses, human response and
instrumentation overhead. It is not active typing time, CPU time or benchmark runtime.

The old implementation order was not controlled: Mojo inherited the completed Nim/Odin examples,
corrected APIs, infrastructure and tests. Conversely, it introduced a new SDK/FFI surface. Those
asymmetries prevent a fair retrospective speed/iteration comparison. Do not create artificial
features, weaken tests or change behavior solely to improve a metric. A newly authorized task in
only one language is not permission to implement it in the others for this study.

## Operational definitions

| Metric | Recorded unit and boundary |
| --- | --- |
| Compiler repair iterations | Each declared fix/recompile cycle linked to an actual failed direct compiler invocation. The initial attempt, unchanged retries, test failures and intentional rejection probes are separate records. |
| Time to passing tests | UTC wall time from registered handoff to the first complete passing acceptance frontier on the final source bytes. Final checks must also pass; later repeated green verification does not inflate first-green time. |
| Bugs found after compilation | Distinct confirmed implementation defects found after a successful build, with test/fuzz/review evidence. Deduplicate root causes; an API risk without demonstrated violation is a separate finding. |
| Implementation LOC | Project-authored, non-generated physical nonblank/noncomment source lines. Exclude tests, drivers, benchmarks, shared infrastructure and dependencies. Retain file hashes and reviewed exclusions for embedded tests. Include language-specific FFI support separately and in the combined total. |
| Human interventions | Independently actionable human decisions/corrections beyond the initial registered assignment. Record nature, evidence and whether common to all candidates; count decisions, not messages. |
| Regression rate | Distinct reviewed previously passing check IDs confirmed broken / distinct passing-baseline check IDs actually retested. Report baseline coverage and raw recheck failures separately. With no denominator or incomplete annotation, use N/A. |

For each completed round, show both the per-round compiler repairs and implementation LOC and
their running measured totals in the comparison docs. Link each contribution to its journal/LOC
snapshot. Label cumulative new-task LOC separately from whole-repository LOC; do not fill
untracked historical repair counts with zero or add the same reused implementation twice.

The regression unit is a **registered check**, not the number of assertions hidden inside a command.
Use the same check granularity for all three languages. A new test catching an old coverage gap is
post-compilation defect evidence; its existence alone does not prove a formerly passing identical
check regressed. One defect may fail thousands of fuzz inputs and remains one defect.

Every finding/repair has a cause: `language` (syntax/types/ownership contracts), `compiler` (compiler
crashes/internal errors), `logic` (protocol/algorithm/state-machine behavior), `library` (library/API/backend behavior), `ffi` (ABI/foreign lifetime),
`infrastructure` (harness/CI/setup/measurement), or `unknown`. Cause changes are explicit attributed
events; preserve the original observation. A human correction can also identify a defect, but that
must not duplicate the defect under multiple IDs.

Intentional negative-compilation tests demonstrate safeguards. They are not development mistakes,
repair iterations or evidence that a language is harder. Successful compilation also does not prove
correctness. Do not quiet a domain/lifetime error with a cast merely to reduce the iteration count.

## Prospective journal

The standard-library-only [journal](../tools/ergonomics/journal.py) supports `begin`, `run`, `event`
and `finish`. It has no native implementation effects of its own. No matched native task has been
started solely for this audit. The original audit had an empty prospective cohort. The later
[complete-report record](../results/work-report/ergonomics.md) captures an authorized implementation
increment, with explicit limits on timing and causal reliability comparisons.

A plan is JSON with these keys; replace descriptive placeholders before using it:

```json
{
  "equivalence_id": "next-authorized-increment",
  "functionality": "Exact same requested behavior and limits for each candidate",
  "specification": "Pinned revision and sections",
  "task_order": ["odin", "mojo", "nim"],
  "agent": {
    "model": "Record actual version or N/A",
    "reasoning_effort": "Record actual setting or N/A",
    "context_policy": "Same reference/spec/test access; record differences"
  },
  "configuration": {
    "nim": "Exact compiler flags, ARC and check settings",
    "odin": "Exact compiler flags, allocator and check settings",
    "mojo": "Exact SDK flags, runtime and check settings"
  },
  "source_paths": {
    "nim": ["nim/src", "nim/tests", "interoperability"],
    "odin": ["odin/codec", "odin/tests", "interoperability"],
    "mojo": ["mojo/codec", "mojo/tests", "interoperability"]
  },
  "acceptance": {
    "new-contract": {
      "nim": ["CONCRETE_MATCHED_COMMAND"],
      "odin": ["CONCRETE_MATCHED_COMMAND"],
      "mojo": ["CONCRETE_MATCHED_COMMAND"]
    }
  },
  "baseline": {
    "existing-contract": {
      "nim": ["CONCRETE_BASELINE_COMMAND"],
      "odin": ["CONCRETE_BASELINE_COMMAND"],
      "mojo": ["CONCRETE_BASELINE_COMMAND"]
    }
  }
}
```

Create one journal per candidate. For example, after preparing the actual plan:

```sh
python3 tools/ergonomics/journal.py begin --state build/ergonomics/task-nim.json \
  --plan path/to/actual-plan.json --language nim
python3 tools/ergonomics/journal.py run --state build/ergonomics/task-nim.json \
  --phase baseline --check existing-contract
# Wrap each direct compiler invocation, using the actual target and flags:
python3 tools/ergonomics/journal.py run --state build/ergonomics/task-nim.json \
  --phase compile --cause unknown -- nim c --mm:arc path/to/actual-target.nim
# After an actual source/configuration fix, link the next attempt to the failed event ID:
python3 tools/ergonomics/journal.py run --state build/ergonomics/task-nim.json \
  --phase compile --repair-of e2 --repair-note "Describe the actual fix" \
  -- nim c --mm:arc path/to/actual-target.nim
python3 tools/ergonomics/journal.py run --state build/ergonomics/task-nim.json \
  --phase acceptance --check new-contract
python3 tools/ergonomics/journal.py run --state build/ergonomics/task-nim.json \
  --phase recheck --check existing-contract
```

These commands are examples, not a task to execute now. Event IDs are assigned in the actual log;
never copy `e2` blindly. Do not label a script that hides multiple compiler invocations as one
compiler attempt. Wrap the direct attempts or leave attempt coverage incomplete. Log unexpected
retries, timeouts and tool-launch failures too. A timeout or missing compiler is not automatically
a rejected source program. `diagnostic` phase preserves deliberate rejection attempts separately;
the CLI returns the underlying command's success/failure status.

Record defects, decisions, confirmed regressions, other findings and cause attribution with:

```sh
python3 tools/ergonomics/journal.py event --state build/ergonomics/task-nim.json \
  --kind attribution --id cause-for-e2 --run-id e2 --cause ffi \
  --note "Observed ABI issue and diagnosis" --evidence path/to/actual-diagnostic.log
```

For `defect` use a successful preceding build and evidence of the violation. For `intervention`,
record the actual human decision/correction and source; do not invent a request or count routine
agent choices. For `regression`, `--run-id` must identify a failed recheck of a recorded passing
baseline. Requirements/acceptance changes invalidate the matched contract: retain the unfinished
trial as censored and preregister a separate task instead of rewriting its plan.

Prepare a task-specific LOC manifest with the same schema as
[the reviewed POC scope](../tools/ergonomics/loc-scope.json). Its hashes/ranges must match current
files, and all counted implementation files must belong to the journal's registered source scope:

```sh
python3 tools/ergonomics/measure.py snapshot --manifest path/to/task-loc-scope.json \
  --output build/ergonomics/task-loc.json
python3 tools/ergonomics/journal.py finish --state build/ergonomics/task-nim.json \
  --loc-snapshot build/ergonomics/task-loc.json --attempts-complete --annotations-complete
```

Use the completion flags only after checking capture completeness. Without them, total repair/first-green time,
intervention, defect or regression metrics remain N/A; without LOC evidence, LOC remains N/A.
The journal preserves raw observed attempts and cause breakdowns even when totals are unknown.
It refuses stale acceptance/LOC evidence, changed plans and unresolved interrupted attempts.
Do not overwrite such a trial to manufacture a clean run. Each journal has one writer; do not
run simultaneous commands against the same state file.

Archive the completed state, LOC manifest/snapshot and referenced command logs with the increment's
report. Compare only matched equivalence IDs, test coverage, model/context settings and environments.
Flag toolchain drift, incomplete trials, pauses, shared work and unequal baseline coverage. Summarize
per-task distributions and causal examples before choosing a language; a single aggregate score
would hide the differences between useful compiler rejection and defects that escaped compilation.

## Reproduce this audit

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/ergonomics/test_tools.py
python3 tools/ergonomics/measure.py snapshot --output results/ergonomics/loc.json
python3 tools/ergonomics/measure.py diagnostics --output results/ergonomics/diagnostics.json
```

The snapshot refuses source changes against unreviewed numeric test-exclusion ranges. The diagnostic
runner checks the intended error, not just a nonzero exit. It compiles the existing fixtures and one
archived contextual ABI probe; it changes no candidate implementation. Linux CI runs the synthetic
measurement-integrity tests. These Python tests are infrastructure validation, not comparative
native-language development trials.
