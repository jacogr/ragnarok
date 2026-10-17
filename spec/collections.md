# Canonical typed set and dictionary codecs

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.1.3
variable discriminators, C.1.5 dictionaries, C.1.6 sets, and the existing C.1.1/C.1.7 scalar
encodings. Exact serialization chapter and published fixture hashes are already recorded in
[pins.json](pins.json); no vendor files, pins or toolchain versions change in this increment.

## Schemas and logical order

`collections.nim` provides reusable generic collections over three explicit value-only families:

- `JamNatural`: canonical general natural encoding, logical numeric order.
- `CollectionUInt[width]`: E0..E8 little-endian unsigned encoding, logical numeric order. Its
  `FixedUnsigned` source value is range-checked; width is a compile-time schema parameter.
- `CollectionBytes[size]`: fixed octets, identity serialization and lexicographic octet order.

Dictionary key/value types are independent `Entry[K,V]` fields. Keys determine strict canonical
order; associated values may repeat, descend or otherwise be unordered. Duplicate/descending
keys are `NonCanonical`; encoders never silently sort, deduplicate or overwrite an entry.
A typed numeric key 255 precedes 256, although their E2 encodings `ff00` and `0001` have the
opposite lexicographic wire order. Fixed byte keys instead compare the first differing octet.
Natural encoded bytes likewise cannot substitute for numeric logical key ordering.

Only these approved scalar families have an implementation/ownership contract. Arbitrary mutable
referenced types, recursive collections, Boolean/bitstring children and other application records
are not silently accepted as adapters. Further schemas need explicit extensions. This is a
reusable collection implementation over the current scalar foundation, not a universal callback
or arbitrary schema framework. Existing specialized report/prerequisite/evidence APIs remain
unchanged; there is no behavioral migration of callers in this increment.

## Framing and APIs

C.1.6 encodes a set as its ordered element concatenation, with **no inherent count prefix**.
`encodeSet` / `decodeSet[T]` require an explicit `CollectionCount` supplied by a fixed schema.
`encodeVariableSet` / `decodeVariableSet[T]` explicitly apply C.1.3 and add one canonical natural
element count. A fixed encoder requires exact source cardinality; it cannot truncate or invent
source values. Fixed zero elements encode as no bytes, variable zero elements as `00`.

C.1.5 dictionaries contain one canonical natural **pair count**, then each key and matching value
in order. `encodeDictionary` / `decodeDictionary[K,V]` add no per-pair length, second value count
or byte-string wrapper. Two natural pairs `(1,9),(2,3)` encode as `02 01 09 02 03`.
Decoders consume one prefix; a standalone caller must separately reject unrelated trailing bytes.

`CollectionLimits` has nominal `ElementLimit` and `ByteLimit` ceilings. The latter covers the
complete consumed/written prefix, including any count, all keys and all values; spare input/output
suffixes do not consume it. `CollectionCount` is distinct from raw uint64 and resource limits.
Zero-width schemas remain real logical values: E0 contains only numeric zero and empty fixed
bytes contain only the empty identity. Their sets/dictionary key domains admit at most one entry.
A second zero-width key is rejected promptly rather than iterating or allocating an arbitrary
claimed collection count. Dictionary values can have zero width without removing pair counts.

## Preflight, ownership and failures

Variable count framing/canonicality precedes item policy, typed host allocation-size bounds,
count-prefix byte budget and minimum complete payload extent. Minimum extents use division, not
unchecked count*stride. Typed storage uses a nonzero host stride even for empty byte-array schemas.
Only then does a no-allocation pass decode every child, check whole-prefix budget and strict logical
key order. A dictionary validates/budgets a key and checks its order before its associated value.
Missing or noncanonical late values discard all earlier pairs. Zero-width singleton domains bound
otherwise zero-progress traversal. Host conversion and every aggregate addition are checked.

Successful decoding allocates an immutable, acyclic ARC **typed value snapshot**, not a retained
wire buffer. A second stable-input pass copies the supported reference-free scalar values. Caller
input must remain stable during the synchronous call and may then be changed or destroyed.
`OwnedSet[T]` / `OwnedDictionary[K,V]` are distinct schema-bound handles. Last-owner destruction
releases the snapshot. Allocation exhaustion follows Nim's existing fail-stop policy.

`setCount`, `setAt`, `dictionaryCount` and `dictionaryAt` return copied metadata/scalars/pairs
through matching retained owners, never mutable sequences, pointers or detached input spans.
Mutating a returned byte-array/scalar copy cannot change the snapshot. Default handles differ
from validated empty collections; missing owners and signed invalid indices return typed failure.
The owner encoders retain those same complete source and resource checks, including stricter new
limits. A set owner can reframe fixed/variable, with an exactly matching explicit fixed count.

Source encoding validates fixed cardinality, item/typed-size bounds, all scalar widths/ranges,
strict logical order, checked total bytes and byte policy before complete output capacity and
aliases. The whole written destination must be disjoint from every source scalar/pair, including
later fields; owner encoding applies that check to its private typed storage too. Every write is
infallible after stable-source preflight. Failure leaves all output unchanged; success preserves
spare suffix capacity. No whole-frame staging allocation or hash-table iteration order is involved.

`CollectionResult[T]` carries values/progress only in its `None` alternative. All failed/default
alternatives carry only the reason. On the Nimony branch, private status/payload fields and
success-precondition accessors enforce selected-alternative checks. Bounds/contracts and assertions
remain enabled; host extent arithmetic is explicitly checked before addition/multiplication because
Nimony intentionally wraps arithmetic. Invalid schema widths fail at compile time; runtime
source width overflow is `ValueOutOfRange`. Unsupported scalar schemas fail compilation.

## Verification

Run `make check`. Seven
literal known-answer checks protect independent Python equations. The historical Nim 2.2.12
ARC/Clang LTO corpus compared **13,161** deterministic requests: logical fields, exact ordered
wire, prefix consumption, both set framing forms and typed failure reasons. It includes all E0..E8
instantiations, natural and fixed-octet schemas, mixed dictionary types, 127/128/129 pair/element
count transitions, numeric versus wire-order inversions, duplicate/descending keys, arbitrary
value order, fixed empty/singleton schemas, all small truncations, overlong/huge counts, uint64
host-bound claims, exact/short/spare output, count/byte limits, late scalar overflow and malformed
random inputs. Encoder sources are independent logical values, not native decoder results.

Published tiny/full report JSON currently has empty prerequisites and empty segment-root lookups.
Frozen hashes and their generic empty set/dictionary framing are checked, but these are **empty
field cross-checks**, not published nonempty collection vectors. Nonempty numeric/hash/octet order
and key/value association cases are independently authored. No upstream vector is modified.

Native regressions cover caller input mutation/release, retained handles, returned-copy independence,
stricter owner policy, defaults/index bounds, zero-width singleton domains, source/private-storage
cross-field aliases, failure atomicity and selected-result guards. Three nominal probes, one
unsupported-schema probe, two invalid-width probes and two privacy probes require compiler
rejection. White-box alias tests include only this project's own source module, using no compiler
or private-runtime hooks. Linux CI runs the same checks and retains diagnostic logs, build commands,
request digest and result manifest under ignored `build/tests/runtime/`. Local verification is macOS
arm64; Linux x86-64 validation occurs in CI after push. These are structural codec tests, not
consensus/state-transition or cryptographic validation.

## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

Reproduce current coverage with
`make runtime`. The runner retains all 13,161
independent requests, seven oracle known answers and both native ownership/alias suites. It adds
50 isolated failed/default result reads and 22 privacy/nominal/schema compilation rejections.

Generic callers combine an explicit scalar-operation concept with the closed supported-family gate.
Nimony's cross-module matching requires visible implementations. `scalarMinimum`, `readScalar`,
`scalarSize`, `scalarLess` and atomic `encodeScalar` provide that interface. Scalar decoding returns
a guarded `ScalarRead[T]` containing copied value/progress. Scalar encoding preflights source range
and whole-field capacity, snapshots the value, then writes; source/output overlap is supported for
that copied scalar API. Parent set/dictionary encoders still reject whole-source aliases. Unchecked
cursor writers and snapshot storage remain private. E0–E8 collection schemas are checked at compile
time; direct constant-invalid scalar-width calls also reject at their supported precondition.

`CollectionBytes[0]` has a private one-byte physical unit so standard sequence capacity arithmetic
never divides by a zero element size. Positive-width scalar sizes remain unchanged. The unit is
excluded from the wire, logical order and copied public byte fields; it is not caller-editable.
All original zero-wire-width singleton and huge-count expectations remain unchanged.

Retained source escape/replacement, copied pairs and warmed ARC release coverage extend the native
suite. After 100 warmups, 1,000 scoped retain/replace/reframe/drop cycles return live occupancy to
baseline, including zero-width snapshots. This measures that workload rather than RSS or general
leak freedom. Commands, exact source/request/output hashes, release counts and each verdict are in
`build/tests/runtime/results.json`. See [the compiler record](../docs/nimony-trial.md) for the exact
compiler, cumulative totals and observed generic/compiler rough edges. Verification is local macOS
ARM64; complete M1, Linux and M2/M3 migration remain separate work.
