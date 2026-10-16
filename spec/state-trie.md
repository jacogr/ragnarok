# Roots over serialized state entries

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex`, equation M and its B/L node encodings. The chapter SHA-256 is frozen in
[pins.json](pins.json). This increment adds `src/state_trie.nim` over the existing
[state-key/node foundation](state-layout.md), without changing dependencies or cryptographic domains.

## API and scope

`stateTrieRoot(entries, limits)` takes already serialized `StateEntry` key/value pairs. Keys have
exactly 31 bytes (`StateKey`); values are raw byte sequences. The completed `StateRoot` is nominally
distinct from an internal `StateNodeHash`, partial left-child commitment or raw value hash.
Successful metadata reports the input entry count and exact nonempty leaf/branch node count.
`StateTrieResult` exposes that metadata only on success; default and failed alternatives contain
only `Uninitialized`, `LimitExceeded`, `DuplicateKey`, `LengthOverflow` or `BackendFailure`.

This is a root calculator, not a persistent trie. It does not implement state-component
serialization T(state), state transitions, proofs, node storage, root updates or block import.
The caller remains responsible for selecting the correct state-key namespace and value encoding.
A root over arbitrary supplied pairs does not establish a valid JAM state.

## Exact construction

An empty mapping returns 32 zero bytes and zero nodes, including with all-zero limits. It does not
hash an empty value or zero-filled node. A singleton immediately becomes one leaf at any depth.
For larger mappings, consume the next key bit **most significant first**, partition into zero/one
children, recursively calculate complete child hashes, encode B and hash its raw 64 bytes.

Every shared-prefix bit contributes a branch, even when the opposite child is empty. There is no
path compression. Keys differing only in their final bit produce 248 branches and two leaves:
250 nonempty nodes. Leaves retain the complete original 31-byte key. L embeds values up to 32 bytes
and hashes longer raw values. B clears only the left child's high bit when encoding; recursion
never substitutes a partial commitment for a complete identity. There is no general-tree `$node`
prefix on these hashes.

Input order does not affect a mapping root. A private sorted key/index array makes the MSB-first
partition deterministic, without reordering caller entries or copying their values. Duplicate
keys are rejected even when their payloads are identical; this API never silently deduplicates or
chooses the last occurrence. Identical values at distinct keys remain valid.

## Resources, errors and lifetime

`StateTrieLimits` requires explicit entry (`ElementLimit`), individual and aggregate payload
(`ByteLimit`), and nonempty-node (`TrieNodeLimit`) ceilings. Entry count and native typed extents
are checked before input-derived scratch allocation. Payload preflight checks individual sizes
and adds aggregate lengths using subtraction to avoid overflow. After sorting and duplicate
rejection, a topology-only pass checks the exact node budget before **any cryptographic work**.
Each increment checks its ceiling first, including at the uint64 maximum.

The node budget counts leaf/branch node hashes; it excludes empty zero children. Long leaves also
hash their raw payload, whose work is separately bounded by the payload ceilings. Hash/backend
failure returns no root or intermediate progress. Policy failures also expose no progress. Native
extent overflow is defended but cannot be exercised with ordinarily allocated test sequences of
small sizes; no fake unsafe sequence descriptor is fabricated to force that branch. Allocation
exhaustion retains the project's Nim fail-stop policy rather than promising recoverable OOM.

Entries, keys and payloads are borrowed synchronously and must remain stable during the call,
including against mutation from another thread. No pointers or values are retained. Sorted fixed
keys/source indices and standard sorting scratch use O(n) transient storage; traversal uses at most
248 branch levels. ARC releases scratch on all return paths. Outputs are fixed independent copies
and survive mutation/destruction of the source values after return.

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_trie_harness.py
python3 tests/test_state_trie.py
```

The independent Python reference partitions unsorted lists directly and hashes with standard
`hashlib.blake2b(digest_size=32)`. It does not reuse the production sorted-range/binary-search
algorithm. Six literal topology/boundary checks protect the oracle. **2,308** native observations
compare exact roots, entry/node counts or failure-only reasons, covering every divergence bit
0..247 with zero/one shared prefixes, source permutations, exact/one-below node limits, empty and
singleton maps, 32/33-byte leaves, primitive block boundaries, per-value/aggregate/count policies,
duplicate equal/unequal values, randomized maps and maps through 1,024 entries. Native supplementary
checks protect source preservation, copied roots and default/failure variant guards. Two negative
compilation probes reject root-as-node and byte-limit-as-node-limit substitutions.

All **11** frozen historical `trie/trie.json` roots at vector revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` match after explicitly projecting their
32-byte keys to the first 31 bytes. Tests check that projection produces no duplicate identities.
The exact Git blob SHA-256 is verified before parsing; no upstream generator is executed and
no checkout/gitlink is changed. The later [whole-state root suite](state-roots.md) separately verifies
fourteen unchanged current-format pre/post mappings. These older cases are projected compatibility
checks, **not**
unmodified current-schema conformance vectors. The current equations and authored 31-byte cases
supply the specification evidence; the older state-layout suite retains its five singleton checks.

Builds retain Nim 2.2.12, ARC, checked Clang LTO and all assertion/bounds/range/field/overflow guards.
Ignored `build/state-trie/` retains build commands, logs, request SHA-256 and results. Linux CI runs
the suite after native crypto construction and uploads diagnostics. Local results are macOS arm64;
Linux verification remains CI's responsibility after push. No timing or production scale is claimed.
