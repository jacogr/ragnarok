# Ready and accumulated work state: chapters 14–15

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapters **14/15**, `text/accumulation.tex` `eq:readyspec` and
`eq:accumulatedspec`, C.1 fixed/variable sequences and canonical sets, and C.2 work reports.
Exact source and fixture identities are in [pins.json](pins.json). No upstream, compiler or
toolchain revision changes. Existing chapter-13 and crypto parity gates remain unchanged.

## Exact schema and source types

`src/state_workqueues.nim` provides `readyStateEntry` / `decodeReadyState` for C(14), and
`accumulatedStateEntry` / `decodeAccumulatedState` for C(15):

```text
C(14): for each configured epoch slot:
  E(ready_report_count)
  || (complete work report || E(dependency_count) || dependency hashes[32]) items

C(15): for each configured epoch slot:
  E(accumulated_package_count) || accumulated package hashes[32]
```

Both outer sequences are fixed by the configured epoch length and have **no outer count**.
Every slot, including an empty one, carries its own canonical natural row count. Ready rows are
ordered sequences, not sets: preserve original slot/report order, without sorting by package hash,
core, dependencies or time. A report has its complete C.2 framing, with no report-length prefix,
guarantee credentials or registration timestamp. Each dependency set has its own natural count.
Accumulated rows and dependency sets contain fixed 32-byte package hashes in strict lexicographic
octet order, unique within each set. Equal or descending source/wire sets reject without sorting
or merging. The same package/report may appear at different positions structurally; cross-ring
membership consistency remains a transition/import concern.

`ReadyItem` is a synchronous source with an immutable `OwnedReport` handle and borrowed stable
sequence of `PackageHash` dependencies. `ReadyRow` is an ordered item sequence; `AccumulatedRow`
is a canonical hash-set source. `WorkQueueSlot`, `ReadyItemIndex` and `WorkQueueHashIndex` separate
ring, report and set-member positions. Ready and accumulated snapshots have distinct types.
`EpochSlots`, `CoreCount` and `PackageHash` reuse existing nominal protocol domains.

## Resource preflight, children and lifetime

`WorkQueueConfig` contains positive `epochSlots`, the existing supported 2..341 core report
profile, per-slot and aggregate `perSlot` / `totalItems`, per-report and aggregate dependency
`perDependencies` / `totalDependencies`, `reportBytes` and complete `maxBytes` ceilings.
For ready state, items count reports; for accumulated state, items count package hashes.
Dependency/report-byte ceilings apply only to ready children. These item limits are **caller
resource policy**, not invented protocol queue capacities. Dependency sets are not given a new
hardcoded size or checked as subsets of a report's declared prerequisites by this codec.

Configuration validates before traversal: fixed ring descriptors must fit native addressing and
at least one row-count byte per slot must fit parent policy. Source rings must contain exactly
the configured slot count. Canonical count framing precedes count policy; per-row and remaining
aggregate policy precede child traversal. Individual typed arrays and copied aggregate metadata
must fit native extents. Checked multiplication/addition precedes byte access or allocation.
Complete parent byte policy includes every row count, report, dependency count and hash.

Existing `decodeReportBorrowed` validates complete child structure without allocation, including
core/erasure profile, bounded payloads, lookup/prerequisite ordering and output tags. Consumed child
bytes are checked against `reportBytes` and parent policy. Source owners must exist; a handle
captured under a broader profile is rechecked for core/shard ceilings and current child-byte
policy. Default source handles return InvalidReport. No child structural rule is weakened.

The decoder preflights **every** fixed slot and child before allocating any retained parent,
report owner or dependency/hash array. Its local scan proof contains counts/consumed extent, not
an input-derived layout array. Capture repeats proved reads over stable input, creating immutable
report owners and private fixed hash copies. A late bad report, count or set publishes no earlier
rows, owners or progress. Nim allocation exhaustion retains the existing fail-stop policy.

Source encoding preflights complete shape, child owners/profile, set order, counts and extent
before allocating one fresh final entry. Retained reports copy directly into that independent
output; no extra report scratch array or synthetic prefix is needed. Source/input stability is
required only during synchronous calls. Output entry bytes belong to the caller and stay stable
during a subsequent [trie call](state-trie.md).

`WorkQueueResult` defaults/failures contain only a reason. Prefix success binds the complete
retained ring to its consumed extent; suffix bytes remain with the caller. Complete entry callers
must require consumed == supplied value length. `readyInfo` / `accumulatedInfo` return copied
cardinalities; slot-count accessors validate nominal ring positions. `readyItemAt` returns a copied
report handle and dependency count, never the dependency array. That report retains its immutable
bytes after the parent is released. `readyDependencyAt` and `accumulatedHashAt` return independent
fixed package values through the selected owner/slot/item. Missing owners and invalid positions
are typed failures. No mutable retained arrays, raw pointers or detached spans are exported.

The module does not rotate rings, resolve dependencies, age/drop entries, test readiness or
availability, enforce membership/eligibility, execute work reports/PVMs, accumulate services,
verify signatures or calculate post-state. Passing these codecs does not establish a valid
queue transition or consensus-eligible report.

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_workqueues_harness.py
python3 tests/test_state_workqueues.py
python3 tests/test_spec.py
python3 tools/format.py --check
```

Six literal oracle tests anchor empty/no-outer-count rings, fixed hash framing, unprefixed report
composition, dependency count/order, source shape, byte/item policy and precise late failures.
**2,904** native requests compare entry keys/bytes, retained report bytes, copied hashes/counts,
consumed extents or failure-only reasons against independent Python equations computed before
native execution. Report structural expectations reuse the existing independent mathematical
report reference; production code composes existing borrowed/owned report APIs directly.

Cases cover every proper truncation of representative ready/accumulated rings; all identity
octets deciding set order; duplicates/disorder; report/slot order and repeated identities across
positions; canonical count boundaries 0/1/127/128/129/255/256; independent per-row/aggregate item
and dependency limits; exact/one-below child/parent byte budgets; empty and late-populated
1/12/127/128/600-slot rings; incorrect source lengths; zero/unsupported/huge profiles;
overlong/missing/huge early/late row/dependency counts; malformed late reports; broader-profile
children; suffixes; 100 deterministic ring sources per component with single-byte and arbitrary
raw mutations; and **48 partial C(14/15) trie roots**. Native supplementary tests exercise copied
parent/source/input sets, report retention after parent scope exit, owner replacement, independent
fixed extraction and result/index guards. Three nominal compiler probes reject set-index-as-item,
item-index-as-slot and accumulated-owner-as-ready; two privacy probes reject storage access.

At vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`, six exact blobs
`stf/accumulate/{tiny,full}/{accumulate_ready_queued_reports-1,enqueue_and_unlock_chain-1,enqueue_and_unlock_chain_wraps-1}.json`
supply **24 pre/post/profile component observations**. Ready slots/reports are preserved unchanged;
dependency and accumulated JSON arrays transport mathematical sets and are explicitly sorted
lexicographically before deriving bytes. Duplicate identities and wrong hash widths reject the
fixture adapter. The selected embedded report schema has empty segment-root lookup and successful
work results; the adapter asserts those properties rather than silently dropping unsupported data.
All 24 derived components pass, including nonempty ready rows, dependency chains, ring wraparound
and populated accumulated history. These are JSON-derived component bytes, not standalone
published T binaries or executed accumulation STFs.

The existing pinned `traces/fuzzy/0000000{1,2,3}.json` blobs provide **12 exact raw C(14/15) entries**
across pre/post phases. They remain unchanged, consume completely and re-emit identically under
both the independent reference and native implementation. Selected ready rings are empty;
published nonempty ready coverage comes from the JSON cases. Some trace accumulated rings contain
one package. Trace evidence is distinct from derived JSON evidence. Their per-entry consumed
counts, population and SHA-256 identities appear in the results JSON. All roots here commit one
component, not a complete JAM state, persistent database or trie proof.

Every consumed blob is SHA-256 checked before parsing; partial clones may fetch exact promised
objects without source/checkout/gitlink changes. No upstream generators run. Checked Nim 2.2.12
ARC/Clang LTO retains assertion/bounds/range/field/overflow guards. Ignored
`build/state-workqueues/` records build commands, corpus identity, logs and fixture verdicts.
Linux CI runs the suite and retains diagnostics; local results are macOS arm64, with Linux
confirmation pending CI after push. Standard formatting is applied without toolchain patches.

M1 framing-baseline coverage remains distinct from full state serialization. Chapters **1–15**
now have typed serializers, with chapter 13's trace key-width gate still open. Chapter 16, service
entries and whole-state composition/root evidence remain. Next planned bounded increment:
**chapter 16 last accumulation outputs**. See the [M1 checklist](../docs/m1.md).
