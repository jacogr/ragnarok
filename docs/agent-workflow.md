# Efficient agent workflow

Keep routine work small: inspect the diff, run affected checks, and return concise evidence.
Protocol, ownership and result contracts in `AGENTS.md` remain mandatory.

## Resume existing work

Before broad source exploration, inspect the current branch, working-tree changes, recent commits,
remote heads and relevant branch history. A checkout on an older master may coexist with later
feature work or squash-merged equivalents. Fetch current heads, identify the actual continuation
point and preserve unpublished changes before selecting a branch. Start source reading from that
point instead of rediscovering work already completed on another branch.

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
head; pending checks are not a failure or a pass. Wait between queries; do not watch/poll unless
requested. PR creation must be followed by attaching its URL to the calling task.

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
# For new stack layers, create semantic commits before submitting draft PRs.
gh stack submit --auto --remote origin
```

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

- Implementation changes: selected native suite plus affected consumers/guards.
- Registry changes: inventory and relevant provenance/tooling tests.
- Documentation/comments: relevant formatting/link checks, no native rebuild.
- Identical-tree history changes: tree-equality evidence and prior test results, no repeated suites.
- Cross-cutting harness/build changes: affected harness tests and representative execution paths.

Use `make unit SUITE=<name>`; see [testing](testing.md). Full verification remains in CI unless
explicitly requested or justified locally. Save logs under `build/`, print short success summaries
and bounded failure excerpts, and retain failure exit codes. Exclude `build/` and `vendor/` from
ordinary source searches. Avoid reading entire registries or repeatedly opening unchanged
instructions. At a clean PR boundary, a short handoff with branch, stack, next action and verified
revision is enough; do not carry a chronological transcript into the next task.
