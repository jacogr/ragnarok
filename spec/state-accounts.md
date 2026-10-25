# Service-account metadata: C(255, service)

Current target: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/merklization.tex` T's C(255, service) mapping, `text/accounts.tex` `eq:serviceaccount`,
storage-footprint domains and C.1 natural discriminator/E4/E8/fixed-hash framing. Exact source
and fixture hashes are recorded in [pins.json](pins.json). This contract now describes
the implemented current schema; historical release evidence below remains separately qualified.

## Exact version-zero schema

`src/codec/state_accounts.nim` provides `serviceMetadataEntry(service, metadata, maxBytes)` and
`decodeServiceMetadata(input, maxBytes)`. The entry key uses existing `chapterServiceKey`:
255 followed by the four little-endian service-ID octets at key positions 1,3,5,7, with all other
key octets zero. The source service ID is **not** encoded again in the metadata payload:

| Offset | Field | Bytes |
| ---: | --- | ---: |
| 0 | Canonical version zero | 1 |
| 1 | Opaque code hash | 32 |
| 33 | Supervisor service ID | E4 |
| 37 | Supervisor incarnation/creation timeslot | E4 |
| 41 | Liquid balance | E8 |
| 49 | Protected supervisor balance | E8 |
| 57 | Minimum accumulation gas per work item | E8 |
| 65 | Minimum deferred-transfer gas | E8 |
| 73 | Storage footprint octets | E8 |
| 81 | Gratis storage/deposit offset | E8 |
| 89 | Storage footprint items | E4 |
| 93 | Creation timeslot | E4 |
| 97 | Last accumulation timeslot | E4 |
| 101 | Parent service ID | E4 |

The current payload is exactly **105 bytes**. There is no outer count or code-hash length. Unlike generic
natural fields, every metadata numeric payload field uses the explicit width in T. The first
zero is a canonical natural discriminator. Complete unknown version values return UnsupportedVersion;
missing and overlong discriminator encodings retain Truncated and NonCanonical respectively.
The source type represents version zero only and cannot emit an unsupported schema by accident.

`ServiceMetadata` owns all fields by value. It reuses `CodeHash`, `Gas` and `ServiceIndex` and
introduces distinct `AccountBalance`, `AccountStorageBytes`, `AccountStorageItems` and `AccountSlot`
domains. Balance and deposit offset share token units; creation and last accumulation share
absolute timeslot units. All fields preserve their full unsigned E8/E4 domains, including zero
and maximum values; opaque code hashes are not checked for associated code/preimage availability.

## Preflight, results and copies

Caller `maxBytes` must accommodate the complete current 105-byte schema before input access or
output allocation. Decoder precedence is byte policy, canonical version framing, supported version,
complete payload presence, then fixed field copies. Fixed offsets need no untrusted arithmetic or
input-derived allocation. A missing final parent-service byte cannot publish earlier account fields.
The encoder checks the fixed budget, then creates a fresh independent key/value entry.

`ServiceMetadataResult` defaults/failures expose only a reason. Complete prefix success returns
`ServiceMetadataRead` with fixed copied metadata and consumed=105; unrelated suffixes belong to the
caller. Whole-entry callers must additionally require consumed == supplied value length. These
fixed records contain no mutable sequences, refs, pointers or borrowed spans, so decoding requires
**no heap-backed snapshot or lifetime association**. Input/source destruction, scope exit and
mutation of one extracted copy cannot alter another value. The returned encoded entry's payload
belongs to the caller and stays stable during later [trie calls](state-trie.md). Allocation
exhaustion for that fresh output follows the existing Nim fail-stop policy.

Default all-zero fixed metadata is structurally encodable, as are apparently inconsistent values:
this codec does not check minimum balance/deposit formulas, derive footprint from nested maps,
validate creation/last-accumulation chronology, enforce parent-account eligibility or prove code
availability. Those require whole-service context and state-transition/import rules. Storage,
preimage and request dictionaries are separate keyed entries, absent from this payload. A decoded
record is not a validated service account or executed accumulation result.

## Current versus historical evidence

The strict current decoder accepts only the implemented 105-byte schema. The
selected pinned release traces contain 89-byte metadata, and refuse as truncated
without a release fallback. Existing test-only expansion inserts zero supervisor
identity/incarnation and protected balance; it changes complete-map roots and
does not define a network migration or supply current-pin upstream parity.
See the [exact source audit](state-current-source-audit.md) for both roots and
source qualification, and the [authored complete corpus](state-complete-serialization-corpus.md)
for independent current-schema expected bytes and wide-field tests.

## Historical release evidence and reproduction

The numerical observations and published-byte claims in this section record the
original 89-byte release qualification. Current reference replay explicitly derives
the additional fields; those derived bytes/roots are not unchanged published answers.

Run the complete checks; Make prepares native dependencies:

```sh
make check
```

Six literal oracle checks anchor the service key, exact offsets/widths, empty numeric values,
opaque hashes, version failures, policy/truncation and full unsigned domains. **1,794** native
requests compare complete keys/bytes or logical fixed fields/consumed extents/failure reasons
against independent Python equations computed before native execution. Decimal source fields and
literal hashes construct typed values without production decoding. Decoder observations follow
complete caller-input destruction; native round trips are not expected answers.

Cases include every proper truncation of a full record; all five E8 and four E4 fields across
integer boundaries; every code-hash octet; service key boundaries through uint32-max; budget
0/1/32/33/72/73/88/89/90; all nonzero initial discriminator octets; canonical unknown larger
versions; truncated and overlong discriminators; suffixes independent of consumed-byte policy;
250 deterministic fixed records with single-byte and arbitrary raw mutations; and **51 partial
metadata-entry trie roots**. Supplementary native tests cover source/input/scope/value independence,
all fields and result guards. Three negative compiler probes reject gas-as-balance,
byte-footprint-as-item-count and timeslot-as-parent-service substitutions. No storage privacy probe is
needed for a record containing only public fixed copies and no retained mutable storage.

At vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`, four existing pinned blobs
`stf/accumulate/{tiny,full}/{always_accumulate-1,bless_from_non_manager-2}.json` supply **20
pre/post metadata records** from `accounts[].data.service`. The adapter checks the exact supported
version-zero field schema and preserves every value: `min_item_gas` / `min_memo_gas` map to the two
gas minima, `bytes` / `items` to footprint, `deposit_offset` to gratis, and creation/last/parent to
the final fields. Their component bytes are explicitly JSON-derived; no accumulation STF executes.

The four already pinned trace blobs `traces/fuzzy/00000010.json`,
`traces/storage/00000001.json`, `traces/storage/00000002.json` and
`traces/preimages/00000001.json` supply **20 exact raw pre/post metadata entries**. Only keys that
exactly reconstruct as C(255, service) are selected; a hashed service key merely starting with ff
is insufficient. Full payload lengths are required, all versions are zero, and keys/bytes re-emit
identically. Evidence includes nonzero service IDs and different metadata values. Per-entry
path/phase/service/key/value hash and complete-match verdicts are recorded in the results JSON.
Roots here commit one metadata entry only, not a whole service or JAM state.

All consumed data is SHA-256 checked at exact Git blob identities before parsing; no upstream
scripts run or source/gitlink revisions change. The historical Nim 2.2.12 ARC/Clang LTO retained
assertion,
bounds, range, field and overflow checks. Ignored `build/tests/runtime/` stores build commands,
corpus SHA-256 and diagnostics. Linux CI runs the suite and retained logs; local validation is
macOS arm64, with Linux confirmation pending CI after push.

State chapters 1–16, current metadata, request-domain enforcement, whole-state composition
and authored complete-map/root qualification are implemented. The old request-namespace and
composition backlog is closed. Independent GP-derived current-schema qualification is recorded in
[the current status](jam-serialization-status.md); additional original published current-schema
maps remain separate corroboration rather than a pending implementation task.


## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

The experimental branch ports fixed account metadata to pristine Nimony 0.6.3 nightly `5b51edfed`,
preserving all keys, bytes, unsigned domains and failure precedence. `ServiceMetadataResult[T]`
keeps its discriminator/payload private behind a read-only reason and a success-only accessor.
The fixed decoded record contains no references and needs no heap-backed owner. Scalar/array
initialization is explicit and fixed byte-budget comparisons use matching unsigned types.

Run `make runtime` with the pinned
compiler; Make installs it as needed. The runner includes the original 1,794-request corpus, six
literal checks, 20
JSON-derived records, 20 exact raw trace metadata entries and 51 partial entry roots. Two native
suites retain fixed source/input/scope/copy independence and exact little-endian field reads.
Sixteen isolated actual/default result reads reject through the exact success contract. Six
private/read-only compiler probes reject result bypasses, and three nominal probes retain
balance/gas, storage-byte/item and timeslot/service separation. After 1,000 warmed copy/entry cycles,
public live allocation returns from 192 to 192 bytes locally; decoded records themselves have no
retained storage.

Results are local macOS ARM64, checked ARC/Clang LTO. Linux confirmation and complete M1 migration
remain separate gates. No compiler patches, account-state validation or transition execution are
introduced. The next bounded Nimony family is service storage/preimage keyed values; cumulative
evidence and remaining gates are recorded in the [trial](../docs/nimony-trial.md).
