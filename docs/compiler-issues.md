# Tracking compiler and standard-library issues

Use the [issue register](../spec/compiler-issues.md) as the starting point for periodic reviews.
Keep one stable local ID per behavior, even before there is an upstream issue. The compatibility
reference describes how to write working code; the register owns status and next actions.

## Capture and classify

1. Add an entry when a compiler/stdlib failure needs a workaround or follow-up. Record the trigger,
   practical impact, exact compiler commit/platform, last tested date, source/PR using the workaround,
   evidence and next action. Mark an unconfirmed observation as suspected, not a proven compiler bug.
2. Preserve raw commands, full output, exit codes and controls under ignored `build/compiler-issues/<id>/`
   (existing evidence directories may be referenced). Keep a portable reproducer, relevant output and
   environment in a tracked report under `spec/nimony-reports-YYYY-MM-DD/`; ignored logs alone are
   not a durable record. Do not copy secrets, generated caches or private project data into reports.
3. Read the pinned language/API contract before deciding the expected behavior. Search open and
   closed upstream issues and PRs using both trigger and diagnostic; link exact duplicates rather
   than preparing another submission. An internal compiler crash still needs tracking even if the
   triggering source is unsupported; distinguish a normal diagnostic from an assertion failure.

## Reproduce and prepare a draft

Use the installed `nim-bug-reporting` skill when preparing compiler/stdlib reports.
Reduce in a scratch directory without changing other tasks' sources. Prefer a standalone stdlib-only
reproducer, preserve the same diagnostic, and run from five independent empty directories. Check
line minimality and a passing control; for intermittent behavior measure and record the failure rate.
Record runtime results separately from compilation. Keep assertions, ownership and bounds checks;
do not patch the compiler or add expensive container copies merely to silence a diagnostic.

Each draft contains the title, version/platform/pin, exact command and input, observed output,
expected behavior supported by the inspected contract, verified alternative, duplicate search and
explicitly unperformed checks. Copy diagnostics from actual runs and identify path redactions.
Document uncertainty about semantics or root cause. A draft can remain pending nightly retest or
contract review; do not label it ready to submit until those gaps are addressed.

## Review and submit

The register states the next decision so the maintainer can periodically ask which entries need
retesting or submission. Review existing entries before each compiler upgrade and when requested;
this process does not itself create a recurring automation.

Use explicit status descriptions: suspected, draft (with remaining gates), ready for maintainer
submission, submitted, upstream fix merged / awaiting released compiler, locally verified fixed,
or closed as expected behavior. Keep last-tested compiler/date separate from upstream status.
A maintainer-filed issue updates the same entry and report. Submit upstream issues/comments only
with explicit user authorization, following upstream disclosure/contribution requirements.
If upstream classifies behavior as expected, correct the local expectation and retain the supported
implementation choice; do not continue listing it as an outstanding compiler defect.

## Retest and retire

An upstream merge is not a local fix. Verify that the selected official compiler archive contains
the fix, run the unchanged reproducer and control, then test the real affected consumers and
relevant guards before removing a workaround. Keep pins and toolchains pristine. Record the exact
compiler identity, checks and cleanup PR; preserve useful regression coverage and historical output.
Keep zero-copy/read-only alternatives where they are appropriate regardless of the compiler bug.
Close the entry only after local verification, or record a separate upstream resolution without
claiming the pinned build has changed. Keep resolved entries so future reviews avoid rediscovery.
