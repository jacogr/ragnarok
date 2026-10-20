# Last-accumulation account timestamps

## Scope and authority

Update surviving accounts' last-accumulation slots after the private finalized recent-history
candidate. Authority remains GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex SHA-256 `bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
the accountspostxfer equation immediately after `accumulationstatisticsdef`. Reuse the pinned
[version-zero metadata layout](state-accounts.md) and [certified statistics](accumulation-statistics.md).
No pin, encoding width, account-creation rule or PVM behavior changes.

The equation intersects surviving accounts with keys of S. Work-items with missing code still
qualify through N, and allowance-only actual gas qualifies through G. An all-zero S tuple does
not qualify. Missing accounts stay absent; setting a timestamp cannot recreate an ejected account.
Preserve every metadata byte except E4 lastAccumulation at offsets 81..84. Derive the slot from
the same retained authenticated candidate header, never a caller-supplied clock or state map.

## API and ownership

`projectAccumulationTimes` is a hash-free, read-only projection over a complete initialized map,
a stable strictly numeric-service-ordered unique list, an explicit nominal AccountSlot and independent
service-work/write-count/aggregate-byte limits. It certifies no block provenance. Validate the full
service list before traversal. Preflight existing fixed records, including already-current timestamps,
and all actual rewrite extents before allocating the entry sequence. Missing metadata is an absent
account; present malformed, unsupported or suffixed metadata refuses. Re-read the immutable map
only after successful preflight to encode detached entries. Projection bytes belong to the caller.

`prepareAccumulationTimes` accepts only PreparedAccumulationRecent. It derives finalization through
the exact ready/accumulated-history chain, computes S using explicit statistics limits, and derives
its service keys and candidate slot from that same certificate. Fork the actual recent-history
successor under inherited store limits and apply all changed metadata in one atomic batch. Failed
projection/publication cannot alter any prior. A valid empty/no-change projection retains the same
complete map without hashing or opening a write batch.

The opaque result retains exact recent source, certified statistics, copied observations, private
entries and complete successor. Info distinguishes inspected services, surviving accounts, absent
accounts and changed records. Entry extraction checks a nominal write ordinal and copies bytes;
source/statistics/state getters retain immutable owners. Defaults and all refusals carry reasons
alone; value and selected statistics/metadata/store causes require guarded accessors. Full-node
complete-map semantics remain distinct from light-state proofs.

## Completion tests

Pure witnesses cover literal four-byte replacement, all other metadata fields and nominal key bytes,
already-current and absent accounts, unrelated/nested entries, input-list independence, empty maps,
full-width slots/limits, exact/short work/write/byte ceilings, duplicates/disorder and malformed,
unsupported or suffixed records. Hash-disabled projection must succeed without backend calls.
Signed full/partial/empty, missing-code and allowance-only histories verify S membership, candidate
slot binding, preserved C(3)/C(14)/C(15)/C(16), provisions and unrelated accounts, exact independent
full-map roots, source lifetime, copied observations/entries and private backend refusal/retry.
Require 1,000 ARC cycles, strict extraction/privacy/nominal probes, selected native verification,
source-owned inventory/Python tooling and pinned formatting. Reuse unchanged codec, statistics,
recent-history, fixture and PVM algorithm evidence.

## Remaining work

Combined C(13) validator/core/service activity publication, remaining transfer/account/privilege
coordination and whole-block publication remain open. M1 framing is complete; full state
serialization and accumulation/block parity remain open.

## Local verification

Passed `make unit SUITE=accumulation_times`. Pure witnesses match literal E4 replacements at
81..84 while retaining every other fixed field, including full-width balance/gas/footprint values.
Already-current and absent records consume no rewrite budget. Exact/short/full-width policies,
empty/default maps, duplicate/disordered lists, zero/short/suffixed records and unsupported or
noncanonical versions refuse at their intended boundary. Late malformed metadata never exposes an
earlier partial entry. Hash-disabled projection and preflight failures make zero Blake2b calls.

Signed four-round execution yields the existing two-service 66/66 actual-gas S and timestamps
both surviving accounts to candidate slot 2. An independent complete mapping with only those E4
changes reproduces the successor root. Allowance-only gas and missing-code work both qualify;
an all-zero missing-code tuple does not. New guarantees with empty accumulation S retain the exact
prior snapshot without hashing. C(3), C(14), C(15), C(16), unrelated metadata and fulfilled provisions
survive. Copied observations/entries, full-width write ordinals, detached owners, statistics-policy
refusal and immediate/delayed trie failure/retry pass. Over 1,000 scoped success and backend-refusal
cycles, occupied allocation remains 1,493,760 bytes before and after.

All eleven runtime extraction guards and five compiler privacy/nominal rejections pass through
existing runners. Python discovery passed 445 tests with seven skips; source-owned inventory,
pinned formatting and diff checks pass. Existing codecs, statistics/recent-history implementations,
shared signed fixtures and PVM code are unchanged, so their prior algorithm/consumer evidence is
reused. Logs remain under ignored `build/accumulation-times/` and native selected-suite/evidence
directories. These are local macOS results, separate from exact-head Linux CI. M1 framing remains
complete; full state serialization and accumulation/block parity remain open.
