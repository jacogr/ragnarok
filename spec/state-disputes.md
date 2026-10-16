# Dispute judgment and offender state: chapter 5

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **5**, `text/judgments.tex` `eq:disputesspec` and canonical
sequence ordering from `text/notation.tex`. Chapter hashes and exact consumed fixture blobs are
recorded in [pins.json](pins.json). No upstream revision, dependency or toolchain changes.

## Exact entry and canonical ordering

`src/state_disputes.nim` provides `disputeStateEntry(source, config)` for C(5) and
`decodeDisputeState(input, config)` for one complete component prefix. The raw value is:

```text
E(good count) || good report hashes[32 each]
|| E(bad count) || bad report hashes[32 each]
|| E(wonky count) || wonky report hashes[32 each]
|| E(offender count) || offender Ed25519 keys[32 each]
```

There is no outer count, tag or per-identity length prefix. Every count uses the canonical general
natural encoding. Four empty sets occupy four zero bytes. Each set is independently in **strictly
increasing lexicographic octet order**, matching T's explicit sorted-set construction. Duplicate or
descending identities within any set are `NonCanonical`. The encoder requires already canonical
borrowed sources and never silently sorts or deduplicates them.

Report identities reuse `DisputeHash`; offender identities reuse the separate `OffenderKey` domain.
`JudgmentSet` retains good/bad/wonky membership. The same report appearing in more than one class
is structurally representable by these independently framed sets; contextual consistency and
transition rules are not inferred from serialization. Equal octets in a report and offender key
also remain distinct nominal domains. No signature, point-validity, verdict eligibility, quorum,
activity, offender-marker or state-transition verification is performed here.

## Bounds, failure and ownership

`DisputeStateConfig` requires independent per-set (`ElementLimit`), aggregate item (`ElementLimit`)
and complete encoded-byte (`ByteLimit`) ceilings. Each complete count is checked against per-set
and aggregate policy before native narrowing or payload access. Aggregate accounting subtracts
before addition; prefix and fixed-stride arithmetic are checked before addition/multiplication.
Native fixed-value storage extents are checked separately. Byte policy includes all four prefixes.

Error precedence within each section is canonical count framing, per-set/aggregate limits, native
extent overflow, byte policy, complete payload extent, then strict ordering. Missing counts or
identity bytes are `Truncated`; overlong counts are `NonCanonical`. Four sections are checked in
order, so a late failure rejects the whole component. Empty input is incomplete even when the
caller supplies all-zero limits; encoding four empty sets still needs four bytes of policy.

Whole-source encoding validates the final set before allocating any output. Whole-parent decoding
validates every set before allocating **any** owner or child array. The encoder returns a new
independent `StateEntry` payload. Decoder success returns a private immutable copied snapshot and
its exact consumed extent, leaving unrelated suffix bytes with the caller. `DisputeStateResult`
default/failure alternatives contain only the reason, never a value, owner or partial progress.
Allocation exhaustion follows the existing Nim fail-stop policy rather than recoverable OOM.

`DisputeStateSnapshot` is a value handle to private acyclic ARC storage. `disputeStateInfo` returns
fixed copied counts; `judgedReportAt` and `stateOffenderAt` return independent fixed values through
the owner and nominal ordinal. Default handles and out-of-range indices are typed failures. Neither
mutable sequences nor detached spans/pointers are exported. Caller arrays/input are borrowed only
during the synchronous call and must remain stable then. Mutation/destruction after the call,
mutation of extracted copies, or replacing one owner handle cannot alter retained data. Entry
payloads belong to the caller and must remain stable during a later [trie call](state-trie.md).

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_disputes_harness.py
python3 tests/test_state_disputes.py
```

Six literal harness checks protect the independent byte/reference equations. **2,766** native
requests compare complete entry keys/bytes, independent owner-extracted identities/counts/consumed
extents or failure-only reasons. They cover strict-order differences in every one of the 32 identity
octets and every set, equal/descending sources and wire, late malformed offender order, every proper
truncation of a nonempty four-set component, empty sets, count boundaries 127/128 and 255/256,
sets through 1,024 items, exact/one-below count/aggregate/byte ceilings, malformed/overlong/huge
counts in each section, suffixes, randomized sorted/source-hostile cases and twelve partial trie
integrations. Those roots commit C(5) alone and do not establish complete JAM state validity.

Twelve published sources come from both pre/post states of tiny/full
`progress_with_verdicts-4.json`, `progress_with_verdicts-6.json` and
`progress_with_culprits-2.json` at vector revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. They contain psi good/bad/wonky/offender
fields. JSON arrays represent mathematical sets: the reference explicitly verifies identity width
and uniqueness, then sorts them to derive T's required order. These are **derived component
fixtures**, not standalone published T(state) binaries or claims of executing the dispute STF.
Raw hostile order is tested separately and is never silently normalized by the native API.

All six exact Git blobs and their SHA-256 are verified before parsing. Sparse checkout and gitlinks
remain unchanged; Git may materialize promised pinned data objects in a partial clone. No upstream
generator is executed or source edited. Existing cryptographic parity gates remain unchanged.

Native supplementary checks cover whole-parent retention, destructive source/wire mutation,
extracted-copy/handle independence, empty-state/default-owner distinction, index errors and default/
failure guards. Two negative compilation probes reject report-as-offender and byte-limit-as-ordinal
substitutions; one privacy probe rejects retained storage access. Native selftests verify the 64-bit
int and 32-byte record assumptions used by reference extent checks.

Nim 2.2.12 ARC/Clang LTO builds retain assertions/bounds/range/field/overflow checks. Ignored
`build/state-disputes/` retains commands, request SHA-256, logs and results. Linux CI runs the suite
after primitive construction and retains diagnostics. Local results are macOS arm64; Linux
confirmation requires CI after push.

M1's documented C.1/C.2 framing baseline remains covered; complete state serialization remains
open. Chapter 3 now has a separate [recent-history codec](state-history.md). Next planned bounded
chunk: **chapter 10's availability assignments**.
The [M1 parity checklist](../docs/m1.md#m1-parity-checklist) records the remaining chapters,
service-account entries and whole-state composition/root evidence.
