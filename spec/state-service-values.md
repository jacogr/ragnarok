# Service storage and preimage keyed values

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T's service storage/preimage mappings and C(service, preimage) key layout,
plus `text/accounts.tex` service maps and preimage invariants. Exact source/data identities are
in [pins.json](pins.json). Dependency/compiler/toolchain revisions and existing parity gates do
not change.

## Key namespaces and exact raw values

`src/codec/state/service_values.nim` exposes separate source constructors:

```text
serviceStorageKey / serviceStorageEntry:
  key = C(service, E4(2^32 - 1) || raw_storage_key)
  value = exact raw_storage_value

servicePreimageKey / servicePreimageEntry:
  key = C(service, E4(2^32 - 2) || preimage_hash[32])
  value = exact preimage bytes
```

The logical key/hash has no length discriminator, and storage keys are not independently hashed
before the namespace prefix is applied. `hashedServiceKey` remains the maintained C constructor:
Blake2b-256 hashes the complete prefix/key preimage; service E4 octets occupy key positions 0/2/4/6,
interleaved with digest octets 0..3, followed by digest octets 4..26. Result keys are 31 bytes.
The storage prefix is ff ff ff ff; the preimage prefix is fe ff ff ff.

Values have **no framing**, including no natural byte count, optional tag or per-value hash.
A value beginning with 00, 80 00 or arbitrary bytes is preserved literally. Empty raw keys and
empty values are supported structurally; an empty value is a present trie leaf, distinct from an
absent mapping. Each source constructor returns an independent mutable caller-owned `StateEntry`.

`ServicePreimageHash` is nominally distinct from code hashes and final state keys. `ServiceIndex`
and `StateKey` reuse existing domains. Serialization preserves the supplied preimage hash/value
pair even if they disagree. Checking hash(value) == lookup hash, associated request histories,
account existence, storage eligibility, storage/deposit counters and state transitions requires
contextual import/transition validation. Passing this serializer does not establish those invariants.

## Resource and scratch policy

`ServiceEntryLimits` contains independent logical `keyBytes` and raw `valueBytes` ceilings.
Key policy counts only original key bytes (storage) or 32 lookup-hash bytes (preimage), excluding
the fixed four-byte namespace overhead. Source entry constructors check raw value policy first,
then key policy/native extent before key work. Storage proves key.len + 4 before allocating one
bounded prefixed scratch array; the preimage path uses a fixed 36-byte local array. Hash/backend
failure returns no key/entry; raw output allocation occurs only after successful derivation.
Scratch is released at synchronous return, with no upstream/streaming/hash-runtime workaround.
Caller input sizes already inhabit native open-array extents; fixed overhead arithmetic is checked
before allocation. Allocation exhaustion follows the existing Nim fail-stop policy.

## Capturing existing keys without original-key enumeration

The paper explicitly permits implementations to keep only derived storage keys. Accordingly,
`captureServiceValue(service, stateKey, rawValue, maxBytes)` needs no original raw storage key
or namespace preimage. The caller supplies an already identified hashed service entry; capture
checks value policy and the four interleaved service octets before allocating/copying any data.
The supplied digest bytes remain opaque. That check binds the key to service context but **cannot**
prove its original namespace, original key, preimage relationship, key provenance, account
eligibility or cryptographic membership. Arbitrary hashed-service digest bytes with matching
service octets are structurally capturable. This API must not classify entries from key shape alone.

`ServiceValueSnapshot` copies retain private immutable acyclic ARC storage containing independent
key/service/value copies. `serviceValueInfo` returns fixed copied identity and length only.
`copyServiceValue` checks owner, complete destination capacity and overlap before writing any byte;
it changes only the raw-value prefix, leaving destination suffix bytes untouched. Short/aliased
copies fail atomically. `serviceValueEntry` rechecks current byte policy and returns fresh key/value
output. Default owners and all failed `ServiceValueResult` alternatives contain reasons alone,
never fabricated keys, values, counts or partial copy progress. Captured empties differ from defaults.

Input extent is authoritative: every supplied byte belongs to the raw value, so there is no
prefix consumed count or internally recognizable suffix. Caller/source stability is required
only during synchronous calls. Input/key destruction, scope exit, extraction edits and replacing
one handle cannot alter retained data. No mutable backing arrays, pointers or detached spans
are exported. Re-emitted payloads belong to callers and stay stable during [trie calls](state-trie.md).

## Evidence and reproduction

Run the complete checks; Make prepares native dependencies:

```sh
make check
```

Six literal oracle checks anchor namespace hashing, raw/unframed values, logical key/value policy,
service binding and externally delimited extent. **2,047** native requests compare derived keys,
exact raw bytes, copied identity/length/value observations or failure-only reasons against
independent Python Blake2b/key equations computed before native execution. Source transport and
opaque capture observations remain separate; native round-trip answers are not expected values.

Cases cover empty/binary storage keys; prefixed hashing-block boundaries; values around embedded
leaf and natural-looking byte boundaries; every preimage-hash octet; service IDs through uint32-max;
separate exact/one-below key/hash/value budgets; identical identity bytes across distinct namespaces;
raw count-like and suffix-like values; deliberate hash/content mismatch preservation; every key
octet mutation (service mismatches reject, digest mutations remain opaque); 150 deterministic
source sets per namespace; retained scope/input/key/value independence; owner/default/result guards;
short destinations and unchanged suffixes; and **83 partial single-entry trie roots**, including
present empty values in both namespaces. Three native binaries cover public ownership, private
native alias misuse and independent source/capture observations. Two compiler probes reject
code-hash-as-preimage and preimage-hash-as-final-key; one rejects retained storage access.
Malformed numeric/tag framing does not apply to unframed values: those bytes are data, not errors.

Four exact JSON blobs at vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`,
`stf/accumulate/{tiny,full}/{same_round_storage_isolation-1,same_round_storage_isolation-2}.json`,
supply **12 storage and 16 preimage mappings** across pre/post states. Source keys/hash/value fields
are preserved exactly; the adapter asserts the supported field schema. These are JSON-derived
mapping/key/value equations, not executed STFs or claimed exact full-state roots.

The four already pinned trace blobs `traces/fuzzy/00000010.json`,
`traces/storage/00000001.json`, `traces/storage/00000002.json` and
`traces/preimages/00000001.json` provide **16 selected opaque captures**: the first two sorted
non-global/non-metadata raw mappings per phase. They retain/re-emit exact original keys and bytes.
Their original hashed namespaces are **not recovered** and may include request-history entries.
They are capture/ownership evidence, not classified storage/preimage constructor conformance.
Per-entry source path, phase, service, original key, byte count and value SHA-256 are retained in
results JSON. All roots here commit one entry only, not a whole service/JAM state or trie proof.

Consumed blobs are SHA-256 checked at exact pinned Git identities before parsing; promised blobs
may be fetched without modifying upstream sources/checkouts/gitlinks. No upstream generators run.
The historical Nim 2.2.12 ARC/Clang LTO retained assertion/bounds/range/field/overflow guards.
Ignored
`build/tests/runtime/` stores corpus SHA-256, commands and native/type diagnostics. Linux CI
runs the suite and retained logs; local validation is macOS arm64, with Linux confirmation after
push.

State chapters 1–16, account metadata and storage/preimage mappings now have codecs, but **M1 state
parity remains incomplete**. Request-history framing is implemented; whole-state composition/root
evidence and the maintainer-parked request-length question remain. Chapter 13 follows the accepted
compact gas and numeric service-key policy without an alternate-width fallback. Next planned bounded increment:
**whole-state composition/root evidence and parity review**. See the [M1 checklist](../docs/m1.md).


## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

The experimental branch ports this family to pristine Nimony 0.6.3 nightly `5b51edfed`, preserving
namespace/key/value bytes, policy precedence and copy atomicity. `ServiceValueResult[T]` keeps its
status/payload private behind a read-only reason and success-only accessor. Retained owner storage
is explicitly nullable and checked through stable retained locals; copied metadata cannot expose
mutable bytes. The private scratch-extent helper retains the existing native prefix-addition check.

Run `make runtime` with the pinned
compiler; Make installs it as needed. The runner includes the original 2,047-request corpus, six
literal checks, 12
storage/16 preimage JSON mappings, sixteen unclassified raw trace captures and 83 partial roots.
Two positive suites include retained/replaced owners, source/input/output independence, exact
aliases, shifted overlaps, short-copy precedence and untouched suffixes. The separate test-only
crypto observer proves backend refusal/recovery, preflight before hashing and scratch release;
production corpus binaries link the unmodified maintained primitive bridge.

Thirty-eight isolated actual/default reads reject through the exact success contract; eleven
private/read-only compiler probes reject result/storage bypasses and two nominal probes reject
code/preimage/final-key substitution. Scratch extents at `high(int)-4` and above are checked without
fabricating huge open arrays or allocations. After 1,000 warmed lifetime/refusal/recovery cycles,
public live allocation returns from 272 to 272 bytes locally. No upstream or private-runtime patch
is used. Results are macOS ARM64, checked ARC/Clang LTO; Linux and full M1 parity remain gates.

Next is the Nimony request-history family, preserving the maintainer's parked namespace question.
See the [trial](../docs/nimony-trial.md) for cumulative totals and remaining work.
