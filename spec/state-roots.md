# Whole-state root evidence and serialization audit

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T and binary-trie equations, C.1 serialization,
`text/accounts.tex` service/request domains, `text/statistics.tex` counter domains,
`text/definitions.tex` gas/blob-length domains and `text/pvm_invocations.tex` solicit.
Exact file hashes are recorded in [pins.json](pins.json). Toolchain and dependency revisions are
unchanged; the subsequent dictionary-width migration is documented below.

## Unmodified full mappings

At vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`, these seven already-pinned
Git blobs supply fourteen complete pre/post serialized mappings and ten distinct published roots:

- `traces/fuzzy/00000001.json`, `00000002.json`, `00000003.json`, `00000010.json`.
- `traces/storage/00000001.json`, `00000002.json`.
- `traces/preimages/00000001.json`.

Every blob is SHA-256 checked before parsing at its exact Git identity. The harness preserves all
original 31-byte keys, values and pair order. Duplicate keys reject before reference hashing;
there is no projection, field rewriting, missing-entry completion or conversion through a typed
component decoder. Both the independent Python list-partition/hashlib reference and checked native
Nim trie reproduce every supplied root. Repeated pre/post states remain separate provenance
observations. Mapping sizes range from 21 to 93 entries and 142,488 to 268,090 value bytes.

For each observation, eleven native requests check the original map at exact count/per-value/
aggregate/node limits, reversed and seeded shuffled input order, each ceiling reduced by one,
a duplicated key, a changed value, a removed entry and an added present-empty leaf. Altered maps
have independently computed roots distinct from the published root. Duplicate probes have enough
payload budget to reach duplicate rejection. There are **154 native requests** in total.

This establishes full-root agreement for **already serialized mappings**, including opaque keyed
service entries. It does not establish that our typed component codecs reproduce T(state), execute
these transitions or validate the states. In particular, hashing original C(13) bytes successfully
does not resolve their different service-key width. This evidence is separate from the older
explicitly projected historical trie fixtures in [state-trie.md](state-trie.md).

## Numeric-width audit: migration and remaining conflict

The general note after T says non-discriminator numeric state serialization is fixed-length
according to the term's size. Explicit E4/E8 overrides are already used in role groups, validator
counters, slots, account metadata and output service IDs. The subsequent investigation supports
a migration of bounded dictionary domains while documenting the accepted compact statistics-gas profile:

| Field | Current codec | Normative context / published evidence | Verdict |
| --- | --- | --- | --- |
| C(12) always-accumulate service/gas pairs | E4 service ID and E8 gas | Four pinned nonempty STF fields uniquely match E4 IDs/E8 gas, corroborating T and the bounded domains. Selected raw T12 dictionaries remain empty. | E4/E8 migration complete. |
| C(13) service dictionary key | E4 service ID | Thirteen additional nonempty raw entries fit E4 keys; ten include nonzero IDs with exact same-state metadata-key associations. | E4 migration complete. |
| C(13) gas fields | Natural gas | Gas has a 64-bit domain; selected trace gas fields are variable-width, despite the general T note. | Accepted compact encoding per maintainer; text discrepancy recorded, no fallback. |
| C(13) ordinary measures | Naturals | Statistics declares these as general naturals, unlike bounded service IDs/gas; arbitrary fixed widths cannot be inferred from their current values. | Do not invent a fixed width. |

See [chapter 12](state-privileges.md) and [chapter 13](state-statistics.md) for existing API contracts
and evidence. Their codecs and independent tests now use the supported dictionary widths, without
fixture repair or format fallback. C12 E4/E8 pairs and C13 E4 keys are implemented. The maintainer
accepts compact statistics gas as used by the vectors; the text discrepancy is documented in
[state-clarifications.md](state-clarifications.md) and is no longer a pending policy gate.
Nonempty raw T12 entries remain unavailable in the selected sample; corroborating nonempty bytes
are explicitly STF fields.

## Key-domain audit: still open

The T request key hashes `E4(length) || hash`; storage/preimage markers use `E4(2^32-1)` and
`E4(2^32-2)`. `bloblength` has the full unsigned 32-bit domain. Therefore request lengths
`0xfffffffe` and `0xffffffff` produce identical key inputs to preimage and 32-byte storage keys
respectively, for the same service/hash bytes. This is deterministic domain overlap, not a
cryptographic hash collision. The existing [request tests](state-requests.md) prove both overlaps
and duplicate rejection when overlapping entries are passed to the trie.

The inspected solicit rule rejects lengths outside `bloblength` and checks request state, readable
hash memory and account balance. It does not state a reservation for those two lengths. This audit
does not establish reachability or unreachability through every possible transition. Large sizes,
gas constraints or selected small trace examples are insufficient evidence for inventing a
serialization restriction. Keep the existing pending namespace-admissibility test and full E4
codec domain until the valid-state cross-map constraint is clarified. Opaque trace keys are not
classified into guessed service namespaces by their digest bytes.

## Reproduction and remaining work

```sh
make check
```

Six active literal harness checks cover input widths, duplicate preservation, present-empty
values, the request matrix, migrated C12 widths and accepted compact C13 gas with no fallback.
The historical Nim 2.2.12 ARC/Clang LTO retained assertions, bounds, range, field and overflow
guards. The runner
records compiler/Python/OS identities, build command, source hashes, each published root, byte/
entry/node counts, corpus hash and per-request expected/actual verdicts in ignored
`build/tests/runtime/results.json`. Linux CI runs the same checks after building native crypto and
retains logs/results. Local macOS arm64 passing results do not certify Linux CI.

[Typed composition](state-composition.md) now integrates exact chapter captures, typed metadata
and typed or explicitly opaque service values, with parent limits and duplicate rejection. All fourteen
published complete mappings compose and reproduce their roots under the recorded interpretation.
M1 state parity remains qualified by the [parked request-namespace question](state-clarifications.md).
Compact gas is accepted project policy, with the text discrepancy recorded. Further implementation
scope is selected separately; trie proofs/persistence, transitions and PVM execution remain future work.
