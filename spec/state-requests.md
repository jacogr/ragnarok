# Service request-history entries

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T's service request mapping, `text/accounts.tex` request domain/history
semantics and `eq:preimageconstraints`, plus C.1 natural counts/E4/fixed-hash encoding. Source and
fixture hashes are in [pins.json](pins.json). Dependency/compiler/toolchain revisions do not change.

## Exact key and tagged history shapes

`src/codec/state_requests.nim` provides `serviceRequestKey`, `serviceRequestEntry` and
`decodeRequestHistory`:

```text
key   = C(service, E4(advertised_length) || lookup_hash[32])
value = E(history_count) || E4(timeslot[0]) || ... || E4(timeslot[count - 1])
        where count is 0, 1, 2 or 3
```

The hashing preimage is exactly 36 bytes, with no hash-length or natural length prefix. The
maintained `hashedServiceKey` performs the standard Blake2b/interleaved-service derivation.
`RequestLength` uses the full stated uint32 domain, distinct from `RequestSlot` and service IDs.
`ServicePreimageHash` reuses the preimage lookup identity domain. Service/length/hash identity is
supplied to entry encoding but absent from history payloads.

`RequestHistory` is a fixed tagged value, with alternatives matching the four cardinalities:

| State | Count | Active fields |
| --- | ---: | --- |
| Requested | 0 | None. |
| Available | 1 | since |
| Unavailable | 2 | availableFrom, unavailableFrom |
| Reavailable | 3 | originalFrom, removedAt, restoredAt |

Inactive fields are unavailable and retain runtime variant guards. Default history is the valid
empty Requested alternative; default **result** is failure and contains no history. Every
canonical accepted count occupies exactly one byte. All timeslots are explicit E4 values in their
supplied positions, including zero, uint32-max, equal and descending values. The codec neither
sorts times nor decides whether those values could arise from a valid lifecycle transition.

## Policy, results and copies

`RequestHistoryConfig` supplies caller `items` and complete `maxBytes`; policy can be stricter than
the protocol's three-slot shape. `RequestEntryConfig` adds logical `keyBytes` for the fixed 32-byte
lookup hash, excluding the E4 prefix overhead. Decoder precedence is canonical count framing,
protocol count <=3, caller count/byte policy, complete payload presence, then fixed field copies.
Huge counts reject InvalidCount while still uint64, before narrowing or payload access. Complete
accepted extents are 1/5/9/13 bytes, so all arithmetic is statically bounded. Empty requested
histories still consume their count byte. Unknown counts never create an extra history mode.

Source alternatives have valid shape by construction. Encoding preflights history item/byte policy,
then key policy/hash derivation, then allocates one fresh entry. Backend failure publishes no key.
Decoding allocates no heap owner: `RequestHistoryRead` contains a copied tagged history and exact
consumed extent. Complete prefix success leaves suffix bytes with callers; whole-entry consumers
must require consumed == supplied value length. Defaults/failed `RequestResult` alternatives carry
only reasons, without values, keys or progress. Input/source destruction, scope exit and edits to
one copied history cannot affect another value. Encoded entry bytes belong to callers and stay
stable during later [trie calls](state-trie.md). Allocation exhaustion for fresh output retains
the existing Nim fail-stop policy.

This component does not execute solicit/forget/provide, historic lookup or availability checks;
enforce chronology/age/expunge rules; validate parent service/account existence; verify preimage
hash/content/advertised length correspondence; or update footprint/deposit values. Those are
contextual lifecycle/import rules, not inferred from a decoded history shape.

## Explicit request-length namespace question

The stated blob-length domain is uint32. T uses E4(length) for requests, E4(2^32-2) for preimages
and E4(2^32-1) for storage. Consequently, for a common service/hash:

```text
request_key(length = 2^32 - 2, hash) == preimage_key(hash)
request_key(length = 2^32 - 1, hash) == storage_key(raw_key = hash[32])
```

These are reproduced mathematical domain overlaps, not collisions in Blake2b. No narrower
admissible-length rule is established by the request codec's cited schema. It therefore preserves
the stated domain instead of inventing restrictions or changing key prefixes. The [admissibility review](request-namespace.md) now supplies two small, funded local-rule
witnesses satisfying the inspected account/preimage/deposit and fresh-solicit predicates. Those
predicates do not exclude the combinations; full PVM/genesis reachability is not established.
The needed exclusion or namespace change still requires normative clarification. A dedicated
**pending namespace-policy test** is skipped explicitly until that rule can be specified. An
active literal test and native integration check reproduce both overlaps and show that existing
trie composition returns DuplicateKey rather than silently overwriting a mapping. This does not
resolve valid-state admissibility. Whole-state integration must retain duplicate-key rejection,
and **full state-parity claims remain gated** by this issue and the chapter-13 width discrepancy.

## Independent and published evidence

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_requests_harness.py
python3 tests/test_state_requests.py
python3 tests/test_spec.py
python3 tools/format.py --check
```

Six passing literal oracle tests anchor exact shape/count/E4 framing, policy, full domains,
service/length key separation and both namespace overlaps. One additional test explicitly records
the pending normative policy. **2,273** native requests compare keys/bytes, active tagged values,
consumed extents or failure-only reasons against independent Python equations computed before
native execution. Source modes are constructed from decimal fields, not production decode output;
raw hostile counts are tested without manufacturing impossible tagged source objects.

Cases include every proper truncation of representative modes; all E4 length/service/timeslot
boundaries including both marker lengths; every lookup-hash octet; equal/descending timestamps;
canonical count 0..3 and invalid 4/127/128/uint64-max; missing/overlong early count encodings;
caller item and byte limits independently across every shape; suffixes; 250 deterministic tagged
histories with single-byte and arbitrary raw mutations; and **98 partial request-entry roots**.
Native supplementary tests protect fixed scope/source/input/value copies, inactive requested/
available field reads, failed/default result guards, both domain overlaps and duplicate-key
composition failure. Two compiler probes reject advertised-length-as-timeslot and the reverse.
No retained mutable storage or privacy probe is needed for fixed tagged value records.

Eight exact JSON blobs at vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`,
`stf/preimages/{tiny,full}/{preimage_needed-1,preimage_needed-2,preimage_not_needed-1,preimage_not_needed-2}.json`,
supply **28 pre/post request histories**. Lookup hashes, advertised lengths and timeslot order are
preserved unchanged. Published shapes are count 0 (14), count 1 (6) and count 2 (8); three-slot
restoration coverage is explicitly authored. No STF or lifecycle transition is executed.

The four previously pinned trace blobs `traces/fuzzy/00000010.json`,
`traces/storage/00000001.json`, `traces/storage/00000002.json` and
`traces/preimages/00000001.json` supply **20 exact identified request entries**, all count 1.
Identification does not reverse or guess hashed keys: compute Blake2b(value) for a candidate raw
preimage, require its explicit preimage-domain key to match, derive the corresponding request key
using that hash and exact byte length, then require that key to exist in the same trace state.
Every request payload consumes completely and re-emits identically. Fixture duplicate keys reject
before reference dictionary construction can conceal them. Per-entry provenance/key/length/count/
value SHA-256 is recorded in results JSON. Roots commit one request entry only, not full state.

Consumed Git blobs are SHA-256 checked before use; promised objects may be fetched without source,
checkout or gitlink changes. No upstream generators run. Nim 2.2.12 ARC/Clang LTO keeps assertions,
bounds/range/field/overflow checks. Ignored `build/state-requests/` records commands, corpus SHA-256,
fixture evidence and native/type diagnostics. Linux CI runs the suite and retains logs; local
validation is macOS arm64, with Linux confirmation after push.

All state component families and selected complete compositions now have tests, but **M1 parity
remains incomplete** pending request namespace policy. C13 compact gas is accepted by maintainer
policy. The review preserves the full length domain and duplicate rejection. The maintainer has
[parked the request-namespace question](state-clarifications.md) pending Gray Paper 0.8.1/0.8.2
review; it is not active work.
