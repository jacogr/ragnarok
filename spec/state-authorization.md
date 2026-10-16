# Authorization pool and queue state serialization

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` serialization T chapters **1 and 2**, and `text/authorization.tex`
`eq:authstatecomposition`. The chapter hashes and consumed published data blobs are frozen in
[pins.json](pins.json). No dependency, toolchain or primitive revision changes.

## Exact entries

`src/state_authorization.nim` provides `authorizationEntry(kind, rows, config)` and
`decodeAuthorization(kind, input, config)`. `AuthorizationKind` selects the entry namespace and
value schema:

| Kind | Key | Raw value |
| --- | --- | --- |
| Pools | C(1) | One canonical natural count per core, followed by that core's 0..8 authorizer hashes. |
| Queues | C(2) | Exactly 80 raw authorizer hashes per core, with no inner count prefix. |

The outer sequence has exactly the configured core count and **no serialized count prefix**.
Each hash is 32 opaque bytes, reusing the existing nominal `AuthorizerHash` domain. Core order and
per-core sequence order are preserved. Repeated and all-zero hashes are representable; neither
sequence is a canonical set. Empty pools remain explicit zero count bytes for their respective
cores. Pool count 8 is valid, 9 is invalid; queue lengths other than 80 are invalid source shapes.
These constants follow the pinned authorization definitions, not caller-selected queue lengths.

The encoder borrows stable nested source sequences synchronously, preflights the entire component,
and returns a new independent `StateEntry` payload for the existing [trie API](state-trie.md).
It never retains caller storage, reorders hashes or silently deduplicates rows. Its mutable entry
payload belongs to the caller and must remain stable during a subsequent root-construction call.

This increment covers serialization only. It does not progress authorization pools, remove used
authorizers, cycle queue positions by timeslot, execute is-authorized code, derive authorizer hashes
from code/configuration, or validate package eligibility. Other state chapters remain separate.
A commitment over these two entries alone is a partial mapping root, not a complete JAM state root.

## Resource, parsing and ownership contracts

`AuthorizationConfig` supplies `CoreCount`, aggregate hash `ElementLimit` and complete payload
`ByteLimit`. At least two cores are required, consistently with JAM's population constraints.
No tiny/full profile is inferred from the input. Configuration-derived row-descriptor and minimum
wire extents are checked before narrowing or multiplication. Every pool requires at least one
count byte; every queue requires 2,560 bytes. A policy below that minimum fails before parsing.

Pool counts use the existing canonical general-natural parser, preserving `Truncated` versus
`NonCanonical`. Protocol row cardinality is checked before aggregate hash policy. Aggregate counts
use subtraction to avoid overflow; prefix and fixed-stride extents are checked before addition or
multiplication, then charged against the byte ceiling. Missing payload bytes are `Truncated` only
after that row's shape/resource checks. Exact outer source cardinality is required on encoding.

The decoder validates **every configured row before allocating any snapshot storage**. It then
copies the validated stable input prefix into private acyclic ARC storage, retaining component kind,
core boundaries and ordered hashes. Descriptor/hash arrays are bounded by configuration and wire
preflight. Allocation exhaustion follows the project's existing Nim fail-stop policy. No fake unsafe
sequence descriptor is constructed to test physically unrealizable source sizes.

`AuthorizationSnapshot` is a value handle around private storage. Replacing one handle leaves
other copies intact. `authorizationKind`, `authorizationCores`, `authorizerCount` and `authorizerAt`
check default handles; row/hash access additionally checks nominal core and position ordinals before
native conversion. Extraction returns independent fixed hash copies. Mutable nested sequences,
raw pointers and detached wire spans are never exported. Input destruction or mutation of extracted
copies cannot alter retained data.

`AuthorizationResult` success alone carries values or progress. Defaults and failures carry their
reason only, including invalid configuration/cardinality, resource/extent failure, malformed input,
invalid owner or invalid index. Prefix success returns the exact consumed extent and leaves any
unrelated suffix with the caller. Because outer cardinality is implicit, the caller must supply the
correct chain configuration; prefix parsing cannot identify an incorrectly selected core profile.

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_authorization_harness.py
python3 tests/test_state_authorization.py
```

Six literal harness checks protect the independent byte/reference equations. **7,059** native
requests cover all pairs of pool counts 0..9, exact and one-below aggregate budgets, late invalid
rows, every proper truncation of two full pools and two 80-hash queues, wrong outer source counts,
queue lengths 0/1/79/80/81, malformed/overlong/huge counts, invalid/overflowing configurations,
empty and repeated/non-sorted hashes, suffix preservation, randomized pools/malformed wire and two
partial-mapping trie integrations. Expected bytes and observations are derived independently in
Python; native decode/encode round trips do not supply expected results.

Both pre/post states of tiny/full `stf/authorizations/*/progress_authorizations-1.json` at vector
commit `d3c089c9a1d5352ad353626d7a2db8589f137b2a` provide four published state sources.
These are explicitly **derived component fixtures**, not standalone published T(state) binaries
or claims of passing the authorization STF. Exact Git blobs and their SHA-256 are checked before
parsing, with no generator execution, sparse checkout expansion, source change or gitlink advance.
Partial clones may materialize promised pinned Git objects when those data blobs are first read.

Native supplementary checks cover immutable ownership, destructive source/wire mutation, copied
hash and handle independence, default-owner/index failures and default/failure variant guards.
Two negative compilation probes reject core-as-position and byte-as-hash-budget substitutions;
a privacy probe rejects access to the snapshot's retained storage. The reference's native extent
model targets 64-bit checked ARC builds; native selftests verify an eight-byte int and 16-byte row
sequence descriptor, without inspecting private runtime APIs.

Builds retain Nim 2.2.12, ARC, Clang LTO and assertions/bounds/range/field/overflow guards. Ignored
`build/state-authorization/` records commands, request SHA-256, logs and results. Linux CI runs the
suite after primitive construction and retains diagnostics. Local verification is macOS arm64;
Linux verification requires CI after push. Existing crypto gates remain unchanged.
