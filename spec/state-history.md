# Recent history and accumulation-output belt: chapter 3

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **3** and MMR encoding, `text/recent_history.tex`
`eq:recenthistoryspec`/`eq:accoutbeltspec`, and the eight-record history constant in
`text/definitions.tex`. Source hashes and consumed fixture blob identities are in
[pins.json](pins.json). No dependency or toolchain revision changes.

## Exact entry and field order

`src/state_history.nim` provides `historyStateEntry(source, config)` for C(3) and
`decodeHistoryState(input, config)` for one complete value prefix:

```text
E(block count)
|| for each block in retained order:
     header hash[32] || accumulation super-peak[32] || state root[32] || E4(timeslot)
     || E(reported package count) || sorted (package hash[32] || segment root[32]) pairs
|| E(belt peak count) || optional peaks (0, or 1 || peak hash[32])
```

**T explicitly places super-peak before state root.** The conceptual tuple in the recent-history
chapter lists these two fields differently; its order does not override the serialization equation.
Timeslots are exactly four little-endian bytes. Every variable count uses the canonical general
natural codec; neither the tuple nor each fixed identity/pair has another length prefix.

History source order is preserved. Each reported-package dictionary must have strictly increasing
lexicographic package keys. Duplicate keys reject even when their associated segment roots differ;
values are never sorted independently or detached from their keys. Repeated segment values at
distinct keys remain valid. `PackageHash` and `SegmentRoot` reuse the existing nominal report
fields, while history header/state/super-peak/peak/slot and extraction indices retain separate roles.
The encoder requires canonical sources and never silently sorts or replaces dictionary keys.

The belt is the MMR encoding from the paper: a variable sequence of optional hashes. Absence uses
one zero tag and has no readable hash; presence uses tag one and all 32 hash bytes. A present zero
hash differs from absence. Reserved tags 2..255 are `InvalidTag`. Holes, source order and trailing
absences are preserved; no trimming, implicit padding or inferred peak shape is introduced.

This increment does not append/rotate history, correct parent state roots, derive header hashes,
compute Keccak accumulation roots/super-peaks, append MMR nodes or construct proofs. Cross-field
commitment consistency, chronological validity and reachable belt shape are transition-level
responsibilities. Structurally decoded arbitrary values are not evidence of valid JAM state.

## Bounds, failures and ownership

`HistoryConfig` supplies explicit `CoreCount`, caller ceilings for retained blocks, per-block and
aggregate packages, belt peaks, and complete payload bytes. JAM history has at most **eight**
records. Each record has at most the configured core count of packages. At least two cores are
required, consistently with the existing JAM population policy. Caller limits may be stricter;
no tiny/full profile is inferred. Peak cardinality has an explicit caller ceiling, without an
invented protocol maximum or normalization rule.

Whole-source encoding validates every nested dictionary and peak extent before allocating output.
Whole-parent decoding uses a fixed eight-record stack layout and validates every late optional
value before allocating **any** parent/child arrays. Aggregate counts subtract before addition;
fixed wire and typed-array extents are checked before multiplication/narrowing. Counts, E4 fields,
optional tags and selected hash payloads all consume the parent byte ceiling. Allocation exhaustion
retains the project's Nim fail-stop policy rather than promising recoverable OOM.

Decoder error order is configuration, canonical history count and block cardinality/policy; then
for each block fixed extent, canonical dictionary count, core/item/native extent policy, complete
pair payload and strict key order; then canonical belt count, peak/native policy and each optional
tag/payload extent. Missing bytes are `Truncated`; overlong counts or dictionary disorder are
`NonCanonical`. Complete prefix success returns its consumed extent and leaves suffix bytes with
the caller. Empty history plus empty belt still needs two count bytes. Default/failure
`HistoryResult` alternatives expose only the reason, never values, owners or partial progress.

`HistorySnapshot` is a value handle to private immutable acyclic ARC storage. `historyInfo` and
`historyBlockAt` return independent fixed metadata; `historyPackageAt` binds a copied pair to its
original block; `historyPeakAt` returns a copied tagged optional value. Default owners and invalid
nominal indices are typed failures. Mutable sequences, raw pointers and detached spans are never
exported. Caller inputs remain stable during the synchronous call only; later source/wire/copy
mutation and handle replacement cannot alter retained results. Encoded entry payloads belong to
the caller and must remain stable during a subsequent [trie call](state-trie.md).

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_history_harness.py
python3 tests/test_state_history.py
```

Six literal harness checks protect T field order, E4 endianness, key/value association, optional
presence, framing and policy. **1,985** native requests compare independent entry keys/bytes,
structured owner-extracted fields/counts/consumed extents or failure-only reasons. Cases include
every proper truncation of a nested history/dictionary/peak value, every reserved optional tag in
early and late positions, all key-octet positions with sorted/descending/duplicate keys, duplicate
keys with different values, history counts 0/1/7/8/9, package counts through the 341/342 boundary,
127/128 and 255/256 prefix transitions, belt counts through 1,024, exact/one-below byte/item budgets,
E4 boundary values, malformed/huge counts and native typed-pair/peak overflow, present-zero versus
absence/trailing holes, random nested source/malformed input and nine partial C(3) trie integrations.

Eight published sources come from both pre/post states of tiny/full
`stf/history/*/progress_blocks_history-1.json` and `progress_blocks_history-4.json` at vector
revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Named `header_hash`, legacy-named
`beefy_root` (the super-peak), `state_root`, `slot`, reported hash/exports-root pairs and optional
MMR peaks supply explicitly derived component fixtures. Reported dictionaries are sorted by key
while retaining associations and checking uniqueness. These are **not** standalone published T
binaries, claims of passing the history STF, or verification of supplied cryptographic commitments.
At this pin the tiny/full files have identical contents: eight phase/profile observations do not
represent eight unique states. Authored cases separately exercise large dictionaries and belts.

All four exact Git blobs are SHA-256 checked before parsing, without executing generators,
expanding sparse checkout, changing source files or advancing gitlinks. Partial clones may fetch
promised pinned data objects. Native supplementary tests cover private parent/dictionary retention,
source/wire mutation, copied values/handles, absent-peak field guards, default/failure guards and
invalid indices. Two nominal compiler probes reject segment-as-package and block-as-peak-index
substitutions; one privacy probe rejects retained storage access. Native checks verify the 64-bit
int, 64-byte pair and 33-byte optional-peak assumptions used by reference extent checks.

Nim 2.2.12 ARC/Clang LTO builds retain assertions/bounds/range/field/overflow guards. Ignored
`build/state-history/` retains commands, request SHA-256, logs and results; Linux CI runs the suite
and uploads diagnostics. Local results are macOS arm64; Linux confirmation requires CI after push.

M1's C.1/C.2 framing baseline remains covered; complete state serialization remains open. Next
planned bounded chunk: **chapter 16 last accumulation outputs**; chapter 10 now has its
[availability-state codec](state-availability.md). The [M1 parity checklist](../docs/m1.md)
tracks remaining chapters, service entries and whole-state composition/root evidence.
