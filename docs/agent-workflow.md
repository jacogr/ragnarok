# Efficient agent workflow

Keep routine work small: inspect the diff, run affected checks, and return concise evidence.
Protocol, ownership and result contracts in `AGENTS.md` remain mandatory.

## Focused execution

- Before integrating an unfamiliar compiler or stdlib API, check the pinned implementation and
  compile a minimal example when support is uncertain. Use Make to provision the pinned tools;
  keep temporary probes and logs under ignored `build/`, using the affected build's compiler flags.
  Consult [Nimony compatibility](nimony-compatibility.md) for previously observed differences.
- Let the owning Make setup prerequisites finish before dependent checks; direct compiler probes
  may also need generated build metadata/assets. Reuse a suitable clean, provisioned checkout across
  increments after verifying its branch, pins and configuration. Do not recreate toolchains or clone
  dependencies merely for a new layer; preserve other worktrees and unpublished work.
- Search named production modules first with `rg`; exclude `vendor/` and `build/` unless investigating
  those trees. Read relevant sections and batch independent reads. Expand only when evidence points
  elsewhere; load skills and supporting references only when their instructions apply. Reuse guidance
  already read for the current scope; reread when it changes or new work makes another rule relevant.
- Bound tool output at its source: select needed fields and summarize large results inside the
  command before returning them. Keep full evidence under `build/` instead of printing whole logs.
  If a read is truncated, narrow the next read to the missing symbol/section rather than repeating
  the same bulk output. On failure, inspect the originating diagnostic before wrapper tracebacks.
- Wait for running commands with bounded waits that permit progress updates; avoid repeated short
  polls returning unchanged logs. Inspect output when completion or new evidence changes the next action.
- Start performance investigations with a bounded representative benchmark using matching inputs
  and build profiles. Broaden when results are inconclusive or do not cover the affected workload.
- Prefer small patches with inspectable diffs. Use a transformation script when its scope is clear
  and verify every transformed pattern before compilation.
- Plan the boundary, tampering and ownership witnesses before the first expensive linked run.
  Format the final source, then run the affected semantic check with its required defines/import
  paths before linking native suites. Repeat checks when new cases or failures change the evidence.
- Resolve compiler/API failures with the smallest relevant probe or check before rerunning a large
  suite. Finish with the affected Make suites and consumer checks; a probe does not replace them.
  Probe nullable borrows across mutable calls and resource-owner copies early. Ownership rejection
  requires the actual lowering diagnostic; successful semantic checking does not establish safety.
- Reuse a passing result while its covered source, dependencies and build configuration remain
  unchanged. Explain why a new change or failure requires broader verification.
- Keep a compact working record of scope, authorization, branch/PR, decisions, modified files,
  verification results, unresolved failures and next action. Include the absolute active checkout,
  exact head/immediate parent, covered tree/build profile and evidence paths with source/dependency/
  configuration identity. Reference relevant guidance/compatibility notes and the next bounded
  increment. Carry forward current constraints and unresolved facts, not a transcript of commands,
  full logs or abandoned attempts. Keep durable protocol evidence in the feature spec and link it.
  Show concise verdicts and actionable error excerpts; retain full logs and exit status separately.
- Reuse existing selected-check entry points. When a sequence becomes stable and recurring, prefer
  a tested shared helper over near-identical temporary runner scripts. Preserve source-owned
  discovery, exact diagnostics and separate runtime/compiler verdicts.
- Keep progress updates short and tied to new evidence, decisions or blockers. During waits, use
  brief required updates rather than repeating the plan or narrating speculative debugging.

## Token-efficient continuity

- Use the compact working record as the source for settled decisions and the next action. Reopen
  decisions only when new evidence, changed requirements or an unresolved contradiction warrants it.
  Consult relevant chat summaries before loading full histories; retrieve only missing context.
- Coordinate through concise changes: new interface proposals, ownership changes, evidence or blockers.
  Link the existing contract instead of repeating it; include enough context for the receiving agent
  to act without rediscovering the work.
- For an authorized multi-layer stack, batch publication and remote verification of several coherent,
  locally checked layers when no feedback or dependency requires earlier publication. Preserve a
  reviewable PR per substantive increment, including its supporting tests/docs and any useful
  separate commits, following the PR sizing rule in `AGENTS.md`. Preserve all native stack/head
  checks below.

## Resume existing work

Before broad source exploration, inspect the current branch, working-tree changes, recent commits,
remote heads and relevant branch history. A checkout on an older master may coexist with later
feature work or squash-merged equivalents. Fetch current heads, identify the actual continuation
point and preserve unpublished changes before selecting a branch. Start source reading from that
point instead of rediscovering work already completed on another branch.

For repeated "next stacked" requests, start from that working record, verify the published parent
heads and select the next bounded increment. Reopen architecture/protocol guidance only for a new
boundary or changed instruction; refresh evidence when its covered inputs change.

## GitHub

Use authenticated `gh`; no custom credential extraction, repeated API clients or browser navigation
for operations the CLI supports. Do not print credentials or full API objects. Examples:

```sh
gh pr view 132 --json number,headRefOid,baseRefName,mergeable,state
gh pr checks 132 --json name,bucket,link --jq '.[] | [.name,.bucket,.link] | @tsv'
gh api 'repos/{owner}/{repo}/pulls/132' --jq '.stack | {number,position,size}'
gh pr create --base master --title 'type(scope): summary' --body-file build/pr-body.md
```

A missing `.stack` means membership is unverified. CI observations must match the exact latest
head; pending checks are not a failure or a pass. Query status when it determines the next action;
wait between queries and do not watch/poll unless requested. PR creation must be followed by
attaching its URL to the calling task.

PR creation, pushes and rebases do not request CI. Keep local verification appropriate to the diff;
request remote checks only when asked or when the maintainer has authorized that verification.
Use `ci:unit` for native units/corpora, Python tooling and source compilation, `ci:e2e` for
end-to-end networking alone, `ci:interop` for all interoperability jobs, `ci:perf` for
all performance jobs, or `ci:full` for every CI group. Add the label to the selected PR
(normally the stack tip); remove and reapply it for a fresh request after later commits. Existing
labels do not trigger checks on new commits. See [requesting CI](testing.md#requesting-ci). Master
pushes retain automatic full verification.

## Native stacks

Read the installed `gh-stack` skill when working on a stack. Check ownership and cleanliness of
all affected worktrees before commands that can update several branches. Use explicit targets and
`--remote origin` where supported; never use interactive menus from an agent. Native commands:

```sh
gh stack checkout https://github.com/jacogr/ragnarok/pull/132
gh stack view --json
gh stack rebase --remote origin
# Resolve only the files and worktree named by the native operation, then stage those files.
gh stack rebase --continue
gh stack push --remote origin
# For new stack layers, create semantic commits before submitting PRs ready for review.
gh stack submit --auto --open --remote origin
```

Immediately before native submission/push, compare freshly read published heads with actual local
branch tips (`git rev-parse`), not just saved catalog heads. For a deliberate native restack, verify
that recorded remote heads remain unchanged and inspect the affected trees/patches before allowing
its guarded rewrites. Make a failed check stop the same orchestration process before mutation;
a Python assertion followed by an unconditional shell command does not provide that guarantee.
On unexpected drift, preserve local commits, fetch and inspect the changes, then reconcile through
native stack commands. Verify the resulting published heads and membership after submission.

Regular PRs are the default; use drafts only when the maintainer requests them. The `--open`
flag also marks existing PRs in the submitted stack ready for review.

These are separate steps, not a script to run blindly. Use `--upstack` when updating only the
layers above an edited branch. If sync restores a conflicted stack, start native rebase to resolve
it; do not assume a zero sync exit means it synchronized. Native stack pushes may rewrite only
the verified stack branches through the extension's lease checks. Manual force pushes remain
forbidden. Never merge master independently into each layer: this adds merge history for subsequent
squash/restack operations to reconcile. Keep squash merging available and never merge a PR unless
the maintainer explicitly requests it. Do not prune branches or discard unpublished work.

For new independent work use a `codex/` branch from current master and `gh pr create`.
For stacked work initialize/add through `gh stack`, then submit and verify remote membership.
Edit generated PR titles/bodies with `gh pr edit`; use semantic titles and a body file.

Only for legacy unregistered dependent branches, reconcile a landed parent with
`python3 tools/sync_stack.py --parent <original-tip> --landed <squash>` before a normal master
merge. Its parent/landed ancestry and exact-tree checks must pass; never bypass a refusal with
blanket ours/theirs resolutions. This helper does not apply to native stacks.

## Verification and output

- Implementation changes: selected native suite plus affected consumers/guards. Build runtime
  misuse drivers successfully before exercising their failure cases; a compile-time contract
  rejection is compiler evidence, not a passing runtime guard. Keep genuine positive controls.
  Match compiler fixture expectations to an observed pinned diagnostic, including the intended
  call/argument position where available, rather than guessing alias names.
- Registry changes: inventory and relevant provenance/tooling tests.
- Documentation/comments: relevant formatting/link checks, no native rebuild.
- Workflow-only changes: affected CI safeguards and workflow lint; broaden for failures or behavior
  those checks do not cover.
- Identical-tree history changes: tree-equality evidence and prior test results, no repeated suites.
- Cross-cutting harness/build changes: affected harness tests and representative execution paths.

Use `make unit SUITE=<name>`; see [testing](testing.md). Full verification remains in CI unless
explicitly requested or justified locally. Save logs under `build/`, print short success summaries
and bounded failure excerpts, and retain failure exit codes. Exclude `build/` and `vendor/` from
ordinary source searches. Avoid reading entire registries or repeatedly opening unchanged
instructions. At a clean PR boundary, a short handoff with branch, stack, next action and verified
revision is enough; do not carry a chronological transcript into the next task.
