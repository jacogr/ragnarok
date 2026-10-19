# Accumulated-package history after finalized accumulation

## Scope and authority

Advance C(15) from the exact processed report prefix of a genuine finalization. Authority remains
GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`, the final accumulated-map
equations after `accumulationstatisticsdef`. Shift old row i+1 to new row i once and put the set
of processed package identities in the last row. The shift is per block, not per elapsed slot;
ready-queue C(14) expiry has different rules and remains separate. An empty processed prefix
still shifts history and appends an empty row. Deduplicate and octet-sort only the new row;
retain earlier rows exactly, including identities repeated across rows.

## API and ownership

`projectAccumulationHistory` is a pure projection from an immutable accumulated snapshot and
explicit stable package hashes. It returns a named projection with an immutable ring and fresh
canonical entry bytes; it does not certify block provenance. `AccumulationHistoryConfig` bounds
inspected processed hashes independently of the existing queue codec's input/output ring policy.
Parent metadata, row counts, combined native hash storage and epoch descriptors are checked before
copies. The parent policy includes the dropped oldest row. Sorting/deduplication uses bounded
scratch; the existing encoder preflights complete output framing before byte allocation, then the
existing decoder captures the immutable snapshot. Caller hash storage and returned entry bytes
cannot mutate that snapshot.

`prepareAccumulationHistory` accepts only `PreparedFinalAccumulation`, derives its original block
queue/profile and processed report prefix, and matches core/epoch domains before traversing reports.
Read exact parent C(15) from the retained full candidate, check byte extent before copying and require
complete decoding. Each selected report contributes its authenticated package hash. Fork the actual
finalized map under inherited store limits and apply the single projected C(15) entry privately.
Do not replay batches or publish caller state. Work/codec/store failures carry only guarded reasons.

The opaque `PreparedAccumulationHistory` retains exact finalization, immutable projected ring,
canonical entry and complete successor map. Copied observations include processed reports, unique
new packages and resulting ring counts. Source/ring/state getters retain immutable owners; entry
extraction makes fresh byte copies. Full-state provenance and C(16)/earlier service effects survive.
Defaults remain distinct from initialized empty history and all payloads require selected success.

## Completion tests

Pure witnesses cover literal multi-row shifts, dropping only the oldest row, empty updates,
duplicate/out-of-order input hashes, preserved cross-row duplicates, singleton epochs, detached
snapshots/entry isolation, exact/short/full-width work and codec limits. Genuine signed stopped
finalizations cover full and unaffordable processed prefixes, profile mismatches, exact package
identities, preserved C(16)/earlier state, immutable priors, backend refusal/retry, source lifetime
and 1,000 ARC cycles. Add strict extraction/privacy/nominal probes and run the registered native
suite, inventory, Python tooling and pinned formatting. Reuse unchanged finalizer/collector/PVM
and fixture evidence.

C(14), recent history C(3), complete C(13) coordination and account timestamps, remaining transfer/
account/privilege integration and whole-block publication remain subsequent work. M1 framing is
complete; full state serialization and accumulation/block parity remain open.

## Local verification

Passed `make unit SUITE=accumulation_history`. Independent literal 163-byte three-row and 140-byte
bound twelve-row encodings match, including exact shift/drop/append order, sorted new-row set
semantics, preserved cross-row duplicates and empty/singleton behavior. Input work, row/aggregate
and full wire policies refuse at their intended phase; full-width policies operate on actual
bounded counts. Mutating input hashes or returned bytes leaves captured rings unchanged.

Genuine signed finalizations cover all four reports, an unaffordable suffix and no reports.
Independent complete-map expectations match the C(15) successor root, while C(16), unrelated
entries and fulfilled provisions survive. Profile mismatches/default sources refuse; private
backend failure leaves priors untouched and retry succeeds. Copied metadata/entries, detached
source/state lifetime and 1,000 success/backend-refusal cycles pass with 850,288 occupied bytes
before and after. Pure projection performs no hashes even when the backend is disabled.

All ten strict extraction probes and five privacy/nominal compiler rejections passed. Python
discovery passed 443 tests with seven skips; source-owned inventory, pinned formatting and diff
checks passed. Diagnostic builds reused prepared native libraries. No existing fixture, queue
planner, finalizer, codec or PVM implementation changed, so unchanged consumer evidence was reused.
Logs are retained under ignored `build/accumulation-history/`; these are local macOS results,
separate from exact-head Linux CI. M1 framing remains complete; full state serialization and
accumulation/block parity remain open.
