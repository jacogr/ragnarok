# Accumulation modified-account membership

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` eq:accinvocation and current host rows, and
`accumulation.tex` eq:accpar. This layer records exact modified-account membership
for genuine implication versions, independently of final root/value equality.
It does not remove the existing foreign publication gate or select parallel winners.

An invocation starts with its own service marked exactly when it receives at
least one incoming transfer, including a zero-valued transfer. Successful write,
upgrade, supervisor, solicit and forget mark their target; new marks its payer
(the new child is separately tracked by creation facts); deferred transfer marks
its source; direct transfer marks both endpoints; eject marks invoker and target.
Global role/queue/roster effects, yield and provisions preserve the set. Refusals
add nothing. Checkpoint selection retains the matching set; a successful no-op
or write followed by restoration remains a modification.

Expose nominal read-only count/index/membership queries. An explicit local
`modifiedAccounts` ceiling bounds unique identities; zero disables tracking and
queries return a typed disabled reason, preserving existing execution callers.
Preflight a complete immutable extension before store publication; limit/backend
failures expose neither partial membership nor candidate state. Copies retain
acyclic immutable fixed-index storage, never parent-effect chains.

Completion witnesses cover every host, same-account deduplication, duplicates and
restoration, incoming zero transfers, successful no-ops, authority/protocol/local
refusals, checkpoint and terminal selection, budget exhaustion, default/disabled
queries, nominal/extraction rejection, prior owners and fresh ARC release.

## Local verification (2026-10-22)

The new source-owned tracking suite and15 affected native host/publication suites
pass with fresh 1,000-cycle ARC evidence. Tests cover all nine account mutation
paths, each non-account effect, equal roots after no-op/restored writes, zero
incoming transfer presence, unique budget preflight without candidate hashing,
backend refusal and paired checkpoint/terminal facts. All264 production modules,
51 strict effect-result guards, nominal capacity/service/ordinal rejections,
focused failure/verification harnesses and inventory checks pass. Evidence remains
under `build/modified-accounts-*` and
`build/tests/modified-accounts-guards/results.json`. Local macOS evidence does not
claim complete parallel/JAM parity, PolkaVM host parity or exact-head Linux CI.

Next: retain the corresponding per-service physical account-write keys, then
apply current accpar conflict annulment/account selection and enable foreign
publication through those bound proofs. Modification membership alone does not
prove which serialized storage/request/preimage keys belong to a selected account.
