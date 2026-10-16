# Activity statistics state: chapter 13

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **13**, `text/statistics.tex` `eq:activityspec` and core/service
activity domains, `text/accumulation.tex` accumulation statistics, and C.1 natural, E4, fixed/variable
sequence and dictionary definitions. Exact hashes are in [pins.json](pins.json). No dependency,
compiler or toolchain revisions change. Service keys now match published E4 framing; statistics gas policy remains **open**.

## Current T/C.1 interpretation and public domains

`src/state_statistics.nim` provides `activityStateEntry(source, config)` for C(13) and
`decodeActivityState(input, config)` for one complete component prefix:

```text
E(current_validator_count) || current_validator_count * (six E4 counters)
|| E(previous_validator_count) || previous_validator_count * (six E4 counters)
|| core_count * (eight ordinary natural fields)
|| E(service_count) || (E4(service_id) || eleven ordinary natural fields) pairs
```

There is no outer tuple count, core-array count or per-record field count. The first two
variable arrays have separate natural count prefixes; E4 applies recursively only to each
validator tuple. Core and service tuples use ordinary naturals, including their gas fields.
The service dictionary follows C.1 numeric-key order with fixed E4 keys, following T's general
fixed-width note and the uint32 service domain. Encoder inputs must already be strictly ascending/unique; no silent
sorting, duplicate merging or source repair occurs. Values need not be monotonic.

`ValidatorActivity` is a fixed array indexed by the named `ValidatorMeasure` enum: blocks,
tickets, preimage count, preimage bytes, guarantees, assurances. Every `ValidatorCounter` has
the full uint32 E4 domain. `CoreActivity` contains seven named `ActivityNatural` fields in
DA load/popularity/imports/extrinsic count/extrinsic bytes/exports/bundle bytes order, followed
by `ActivityGas`. `ServiceActivity` maps to provision(count, bytes), refinement(count, gas),
imports, extrinsic count, extrinsic bytes, exports, accumulation(work-item count, transfer count,
gas). Its nine non-gas fields have named `ServiceMeasure` positions and two separate nominal gas
fields. All ordinary natural/gas values support the full canonical uint64 domain; no contextual
plausibility ceiling is invented. Keys reuse `ServiceIndex`; core, validator and service-entry
positions have independent distinct index types.

## Profile, resource and ownership contracts

`ActivityConfig` contains `cores`, separate `current`/`previous` roster populations,
`maxServices` and complete `maxBytes`. Both roster domains use the existing 2..341 core, 3c
validator profile with 6..3*cores validators, divisible by three. A full-profile current roster
may shrink to six while the previous roster retains 1023 records. Epoch sequence counts must
exactly match the supplied corresponding populations; fixed core sources must have exactly
one tuple per configured core. A codec cannot verify the supplied populations against actual
roster state; whole-state composition must provide the correct context.

Canonical counts and fixed-array extents are checked before fixed reads. Service count policy
and native typed-storage capacity are checked before pair traversal or allocation. All count,
key, counter and gas bytes consume the complete parent budget. Checked addition and profile
bounds prevent native arithmetic/conversion overflow. Invalid configuration, wrong roster/source
shape, missing or overlong naturals, incomplete E4 keys, duplicate/descending keys and late gas
failures return typed reasons without values, owners or progress.

The decoder scans every nested field without heap allocation, then captures independent fixed
records in private acyclic ARC storage. Source encoding preflights the entire shape, order and
extent before allocating one fresh C(13) payload. Neither path publishes partial earlier arrays
after a late failure. Source/input stability is required only during synchronous calls.
Allocation exhaustion follows the existing Nim fail-stop policy.

`ActivityResult` defaults/failures contain only a reason. Complete prefix success binds the
retained snapshot to its consumed extent; suffix bytes remain with the caller. Complete-entry
callers must additionally require consumed == supplied value length. A successful prefix is
not proof that an entire entry matches the schema; composition enforces exact extents.

`ActivitySnapshot` value copies retain immutable private storage. `activityInfo` returns fixed
counts. `validatorActivityAt`, `coreActivityAt` and `serviceActivityAt` check their nominal indices
before narrowing and return independent fixed copies; no retained arrays, pointers or detached
spans are public. Validator extraction also selects its epoch. Missing/default owners and invalid
positions are typed failures. Caller source/input mutation, edits to extracted records and owner
replacement cannot affect retained data. Output entry bytes belong to the caller and stay stable
during a later [trie call](state-trie.md).

The module does not increment counters, rotate epochs, calculate DA/accounting totals, execute
statistics STFs, check actual service accounts or prove counter consistency with extrinsics,
reports, assurances or accumulation results. Those are contextual transition/import checks.

## Independent and published evidence

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_statistics_harness.py
python3 tests/test_state_statistics.py
python3 tests/test_spec.py
python3 tools/format.py --check
```

Seven literal oracle checks anchor no-count/fixed/natural framing, separate populations, key
order/domain, full gas values, late truncation, resource ceilings and the prefix-versus-complete
E4-key exact extent. **2,615** native requests compare complete entry keys/bytes, logical copied
fields/consumed extents or failure-only reasons against independent Python equations computed
before native execution. Decimal source fields are built without production decoding. Decoder
observations use the public owner accessors after destroying original input, rather than native
round trips as expected answers.

Cases cover every proper truncation of a mixed-field parent; each validator field's E4 boundaries;
each core/service field across every 7-bit natural width transition through full uint64; numeric
service key ordering and every E4 octet boundary; separate current/previous populations including 6/1023
and count-prefix boundaries; core counts 2/3/43/86/341; wrong source/announced shapes; invalid
profiles; exact/one-below count/byte ceilings; 0/1/127/128/129/255/256 service counts; malformed,
overlong, missing and huge counts/scalars at early/late positions; 150 deterministic valid sources
with single-byte and arbitrary raw mutations; suffixes; and thirteen partial C(13) trie roots.
Native supplementary tests protect retained scope, copied counter/gas/key records, independent
resized epochs, owner/index/result guards and private storage. Two negative compiler probes
reject gas-as-validator-counter and service-ordinal-as-core; one rejects access to owner storage.

At vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`, the four
`stf/statistics/{tiny,full}/{stats_with_some_extrinsic-1,stats_epoch_change_with_set_resize-1}.json`
blobs provide **eight partial validator-pair observations**, including a current 6/previous 1023
full-profile post-state. Their six named fields are mapped exactly and unchanged. Those fixtures
omit core/service statistics: their **zero core tuples and empty service dictionary are explicitly
authored completion**, not published full-state data or STF execution evidence.

The three `traces/fuzzy/0000000{1,2,3}.json` blobs supply six exact pre/post C(13) entries.
All six now decode to complete immutable records and re-emit the original bytes unchanged:

| Trace / phase | Supplied bytes | Consumed | Trailing bytes |
| --- | ---: | ---: | ---: |
| 1 pre | 307 | 307 | 0 |
| 1 post; 2 pre | 329 | 329 | 0 |
| 2 post; 3 pre | 332 | 332 | 0 |
| 3 post | 329 | 329 | 0 |

Sixteen additional exact values from the eight later snapshots in
[state-widths.md](state-widths.md) decode and re-emit completely, including nonzero service IDs
through 3953987649 and 55 same-state metadata-key associations. The E4 service-key migration is
complete; the former shorter-prefix and noncanonical verdicts no longer occur for these inputs.
No fixture rewriting, format fallback or guessed tuple fields are introduced.

**Remaining gas gate:** the general T note says non-discriminator numeric state fields use fixed
widths, and gas has a bounded 64-bit domain. The selected published C13 values instead reconstruct
with natural gas, including positive values and zero padding differences. This migration leaves
those gas bytes unchanged and keeps an explicit pending test. Ordinary measures are general
naturals in the paper; the reference ASN.1 domains are not used to invent fixed widths for them.
Wire agreement under this recorded gas interpretation does not establish full normative parity.

`build/state-statistics/results.json` retains corpus identity, build commands and per-entry raw
SHA-256, complete-match flag and consumed/trailing counts alongside the open gate. Fixtures are
SHA-256 checked before parsing at exact pinned Git blob identities; partial clones may fetch
promised objects without checkout/gitlink changes. No upstream generators run. Thirteen partial
roots commit C(13) alone, not complete JAM state or proofs. Nim 2.2.12 ARC/Clang LTO keeps
assertion/bounds/range/field/overflow guards. Linux CI runs the suite and uploads diagnostics;
local results are macOS arm64, with Linux confirmation pending CI after push. Existing crypto
gates remain unchanged.

The C13 service-key migration is complete. All 224 selected chapter captures and fourteen
published full-state mappings now pass [typed composition](state-composition.md), but M1 parity
remains incomplete pending C13 gas and request namespace policy. Next: request-length namespace
admissibility review; C13 gas still requires normative/reference clarification.
