# Bounded terminal-selected self account writes

## Scope and authority

Extend PR #191's self-metadata publication using GP 0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex `accpar` self-account
projection, followed by `fnprovide`. Vectors remain
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Pins, host behavior and parked 0.8.0
request namespaces do not change.

An explicit per-execution self-key ceiling enables immutable provenance for write,
solicit and forget. Zero preserves the earlier execution behavior and publication
gate. Only canonical keys derived by these actual self operations enter the trace;
self metadata is copied separately. Capture unique keys, including deletions, with
preflight before trace allocation or account hashing. Final values come from the
same terminal-selected current account owner; touched keys never carry stale values.
Repeated writes share one final descriptor. Checkpoints freeze account scope, keys
and accounts together; yield/provide/upgrade preserve the proof. Broader mutations
remain sticky Unsupported regardless of later upgrade or restored equal bytes.

Batch self-write count and copied-value byte limits default to zero independently
of the existing self-metadata count and terminal provision policy. Copy final puts
or deletions on a private common-source fork, then fulfill provisions there. Reject
physical duplicate keys across all selected metadata/data writes before publication.
Distinct invoking services may change equal logical storage keys without overwriting
one another. No whole-map scans, generic snapshot diff, journal value copies, mutable
proof exposure, created/deleted service merger or outgoing-transfer publication.

Grow_heap remains UnsupportedHostCall. Transfer, privilege/queue/staging and
cross-service creation/deletion effects remain UnsupportedAccountEffects. M1 framing
is complete; full serialization, full accpar, recursive transfers and block publication
remain outside this bounded layer.

## Completion tests

Use real common-source PVM executions for two services writing equal raw keys,
repeated replacement/deletion, request creation/removal/restoration and selected
checkpoint rollback. Check exact metadata counters, credits, histories, raw bytes
and independent full-map roots, including combined upgrades/provisions. Cover
explicitly disabled/short/exact trace and batch budgets, stale plans, foreign owners,
late backend refusal, detached key ownership and fresh 1,000-cycle ARC release.
Retain strict default/index/private-key guards and parent gate witnesses. Run affected
native consumers and downstream semantic checks; reuse prepared native dependencies.

Next: cross-service creation/deletion provenance and conflict rules; outgoing transfers
and grow_heap remain separately gated.

## API and ownership

`prepareAccumulationEffects` and `executeAccumulationMachine` append the optional
`accountWriteKeys: ElementLimit` policy. Zero disables self-key tracing without
turning the earlier local host success into a refusal. A positive bound makes trace
capacity exhaustion a typed local LimitExceeded, before account-map hashing. A
broader unsupported lineage never regains a self-only certificate. This is local
resource policy, not a new guest return code or protocol length restriction.

The immutable `SelfEntries` scope retains a private unique-key owner. Read-only
`effectAccountWriteCount` and `effectAccountWriteKeyAt` provide a copied count and
one fixed key at nominal `AccumulationAccountWriteIndex`. Default, unsupported
and out-of-range queries expose reasons alone. Upgrade preserves SelfEntries;
yield/provide retain the exact key owner; checkpoint shares the whole context.
An operation copies the bounded key list only when a new unique key is added;
replacement/deletion of traced keys shares it. Neither historical values nor
parent effect chains are retained by this trace.

`AccumulationBatchLimits.selfWrites` bounds aggregate nonmetadata descriptors;
`selfValueBytes` bounds aggregate copied final values independently. Both default
to zero, while `accounts` continues counting only fixed self metadata. `batchInfo`
reports these three observations separately. Deletions consume one descriptor and
zero copied bytes. The unchanged store enforces its own combined write/value
ceilings on the account phase, followed by independent terminal provision policy.
All failures retain the caller's exact prior, including late provision refusal.

The existing common-source and unique-service checks run before key extraction.
Fixed physical keys are checked for duplication across metadata and data writes;
conflicts return UnsupportedAccountEffects without selecting a winner. The parked
request namespace remains unchanged, and no new hash collision interpretation or
interim request encoding is introduced.

## Local verification (2026-10-19)

Eight native suites passed: pvm_self_account_writes, accumulation_batch,
accumulation_complete_batch, pvm_account_publication,
pvm_accumulation_integration, pvm_accumulation_write,
pvm_accumulation_solicit and pvm_accumulation_forget. Every suite retained fresh
1,000-cycle ARC evidence with unchanged occupied memory; the new workload stayed
at 158,080 bytes. Independent complete-map roots cover own credits, same raw
storage keys in different services, replacement/deletion including prior storage,
request creation/forget/restoration, selected checkpoints, upgrade preservation,
combined provisions, exact budgets, stale and foreign provenance, detached owners
and both early account-root and late provision-root failures.

Four downstream modules passed semantic compilation: accumulation_execution,
accumulation_outputs, accumulation_continuation_execution and
accumulation_reentry_execution. 53 runtime extraction guards passed across effects,
batch and dispatch; eleven privacy rejections and one nominal key-index rejection
passed. Pinned parser metadata confirms ten attached API docs. Sixteen selected
failure/inventory Python tests, source-owned inventory, pinned Nim/Rust formatting
and whitespace checks passed. Native bridges and vendor pins are unchanged.
These are focused local macOS checks; exact-head Linux CI remains separate.

Logs are under `build/pvm-self-account-writes/`: regression.log, guards.log,
guards-results.json, semantic.log and individual semantic logs, inventory.log,
python-selected.log and format-check.log. Existing parent gates continue passing
with the default zero trace policy.

Efficiency: reused the guest framing, complete-map fixtures, prepared native
libraries, native runner and focused guard drivers. Trace replacements share their
key owner; only new unique keys copy the explicitly bounded fixed-key list, with
no journal value copies or full-map traversal. Two compile corrections involved
retaining an explicit nonnil owner for the new accessors and using uint64 register
constants/the existing LimitExceeded dispatch reason in the new fixture. No
compiler/dependency setup or unrelated whole-source/native sweep was repeated.

## Created-account extension

[Created-account publication](pvm-created-accounts.md) adds a separate bounded proof
and publication count for genuine new-service additions. Existing self-key/value
ceilings remain independent; zero creation policy preserves the earlier gate.
Ejection, transfers, privilege changes and grow_heap remain gated.
