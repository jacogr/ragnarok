# Regular hash-return provision projection

## Scope and authority

The maintainer requested this next stacked increment after the #533 projection
adoption was identified as next work. Adopt only C's regular X provision
projection from [GP #533](https://github.com/gavofyork/graypaper/pull/533), merged
2026-07-22 at `0c0664eb52ba92afd8d21cef96c0e1da506eddfe`. Its reviewed
`text/pvm_invocations.tex` SHA-256 is
`e36d6aaf4b84f06632cd427e5d9a04cff082b47cb4bc1e37a34ad68bec3ea6fd`.
Base GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` and vector
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` pins remain unchanged. The exact
adoption is recorded in [the authority record](pvm-hash-return-adoption.json).
The preceding layer already adopts #533/#538 grow_heap fixes; this is not a
blanket adoption of the remaining host-function changes.

A successful halt with an accessible exactly-32-byte return selects regular
accounts, transfers and provisions and replaces only the regular yield. Retain
nonempty X provisions even when checkpoint Y differs. Panic, fault and OOG still
select Y. Non-32-byte and unreadable returns retain regular yield/provisions.
The normalizer uses the existing immutable yield successor, never constructs a
new provision set, consumes caller facts or hashes/fulfills persistent data.
AmbiguousProvisions remains a reserved historical enum value, not a runtime gate.

## Completion tests

Use genuine provide/checkpoint/hash-return guests for empty, X-only, equal X/Y
and strictly larger X provision sets. Append-only effects make Y-only provisions
unreachable; do not forge them. Verify exact payloads, targets, returned commitment,
original/checkpoint immutability, capped gas and pure normalization with a refused
hash backend. Cover non-32-byte, zero-hash and unreadable return boundaries.
Publish selected provisions through terminal integration and common-source batches
against independent full maps with literal timestamps and incoming balances.
Cover union budgets, execution order, copied/detached owners, late invalid-execution
preflight, backend rollback and fresh 1,000-cycle ARC cleanup. Retain strict
extraction/privacy guards and affected downstream semantic checks.

M1 framing is complete; full serialization, full accpar and whole-block publication
remain open. Participating-target collision validity and the parked request-domain
pin upgrade remain separate boundaries.


## Local verification (2026-10-19)

Six native suites passed: pvm_accumulation_provide,
accumulation_terminal_provisions, accumulation_batch, pvm_accumulation_outcome,
accumulation_complete_batch and pvm_accumulation_integration. Every suite retained
fresh stable 1,000-cycle ARC evidence. The expanded provide, terminal and batch
workloads used 993,104, 424,848 and 1,284,832 occupied bytes before and after.
Twenty-eight strict outcome/terminal/batch extraction guards, eleven privacy
rejections and four downstream semantic checks passed. Four independent source/
adoption/set Python checks passed with the former projection pending test active.
Inventory, affected pinned formatting and whitespace checks passed. These are local
macOS results; exact-head CI remains separate. Native bridges, toolchains, vendor
gitlinks and the base GP/vector pins are unchanged.

Evidence: `build/pvm-hash-return-native.log`,
`build/pvm-hash-return-publication.log`, `build/pvm-hash-return-batch.log`,
`build/pvm-hash-return-regressions.log`,
`build/pvm-hash-return/guards-results.json`, and matching Python/inventory/format
logs. The regression driver also verifies the full previously retrieved merged
#533 source hash and its exact C hash-return X projection. Existing native
libraries, fixture assembly and supported runner functions were reused. One new
nested default-result assertion needed an explicit local for this pinned compiler;
only unfinished or changed suites reran. No dependency setup or broad corpus run.

Next bounded work: terminal-selected outgoing-transfer collection under explicit
count/memo limits, before recursive transfer input/gas integration. Preserve the
current outgoing-debit publication and continuation gates until their consumers
are supported. M1 framing remains complete; full serialization, complete accpar
and whole-block publication remain open.
