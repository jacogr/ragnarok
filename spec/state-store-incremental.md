# Incremental StateStore integration

Scope authorized by the maintainer after the standalone storage stack merged: db #1 owns three
stacked PRs for StateStore contract coverage, incremental in-memory commitments, and consumer
validation/measurements. State #5 confirmed it has no pending overlapping changes and remains idle.
GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` M/B/L and existing pins stay unchanged.

## Frozen public contract

Keep the exported StateStore/StateStoreSnapshot/StateValue types and operations source-compatible.
Enumeration is sorted by every serialized key byte; missing keys differ from present-empty values.
Values, bounded copySlice results, snapshots and private forks retain their exact owners after
updates and destruction. Forks inherit complete-map and batch limits. Failed batches preserve
snapshot identity and values; only successful candidates publish. Empty batches retain identity.
Successful nonempty batches publish a new StateStore snapshot even if an absent delete or identical
put leaves the root unchanged. Independently constructed equal mappings do not share identity.
BackendFailure means a required cryptographic operation failed; backend call counts are not a
public contract, and cached unchanged subtrees need no new cryptographic operation.

`make unit SUITE=state_store_contract` freezes sorted iteration, independently recomputed complete
roots/counts, 0/1/32/33-byte leaves, deep prefixes, exact snapshot identity, retained slices, forks,
input/output mutation isolation and atomic invalid/duplicate/limit refusals on the original store.
Existing store, observer failure, slice, published replay and checkpoint suites remain mandatory
consumer evidence when the commitment implementation changes.

## Implementation and completion checks

Retain the sorted mapping for keyAt and bounded value slicing. Each private snapshot also owns one
immutable FullStateTrie revision. Validate the existing store batch before adapting writes and
publishing the sorted map and trie together. Keep stateTrieRoot as an independent test oracle,
not a second production commitment path. Check required-hash failures, exact topology ceilings,
retained forks and ARC release before enabling all existing consumers through this same API.

The fixed public workload `tests/performance/state_store_workload.nim` observes Blake2b call counts
and occupied ARC bytes for 128/1024 entries, 33-byte values, 64 single-key changes and retention
windows of one/eight snapshots. Capture a baseline before implementation with the same pinned
checked optimized ARC/Clang/LTO build and maintained crypto observer. Compare identical source and
inputs after integration; report memory tradeoffs explicitly. Occupied/peak bytes are live memory
observations, not total allocation counts. These counters make no wall-clock latency claim.

Disk adoption, journal/checkpoint/canonical-head atomicity, durable pin policy, full/light startup
selection and all other consumer adoption remain separately gated. This tranche adds no M1 or
complete state-serialization claim. No public StateStore backend selector or alternate execution
path is introduced.

## In-memory adoption

StateStore now privately retains a FullStateTrie in each snapshot beside its existing sorted
mapping. The complete-map constructor and every update use the incremental trie for commitments;
stateTrieRoot remains independent and test-only at this boundary. Existing validation/error
precedence, sorted keyAt and owner-bound value slicing remain in the state layer. Adapted writes
borrow stable input only for the synchronous call; both owners are private before publication.
A single head assignment publishes their matching root and mapping after all checks succeed.

Empty batches retain the exact snapshot. Successful nonempty absent deletes still allocate a new
StateStore snapshot, even if the underlying trie reuses its revision and needs zero hashes.
No required backend invocation is skipped on a changed path; failure there discards every new
node and leaves old snapshot identity/bytes unchanged. Forks retain the same immutable trie and
inherit all mutation ceilings. Sorted-map descriptors still copy with O(n) work. Leaf payloads
currently have separate owned copies in the sorted map and trie; measure that explicit memory
cost before proposing a different shared representation or changing the slice API.

The observer-linked `state_store_incremental` suite uses a complete 256-leaf balanced mapping:
a 33-byte single-key replacement requires exactly ten Blake2b calls (two leaf, eight branches),
including when applying the same mutation on an independently retained fork. First/fifth-call
failures prove atomic rollback; the independent whole-map calculator checks the final root and
every sorted key/value. Absent deletes and empty batches need zero calls; retained values/slices
survive both original and fork owner destruction.

## Consumer validation and reproducible measurements

`state_store_checkpoint_updates` resumes all seven independently pinned pre/post mapping pairs
from complete checkpoints, applies forward/inverse writes through restored stores and private
forks, verifies every original root/value/count, and reproduces the exact original checkpoint
bytes after inverse updates. Restored zero-write ceilings stay inherited by forks; retained
values outlive both restored owners. This checks mutation-capable trie reconstruction, not just
successful decode of a root.

Existing `state_checkpoint_bank_replay`, `application_chain`, `application_checkpoint_bundle`,
`pvm_accumulation_lookup`, `authorization_transition_failure` and `history_transition_failure`
pass through the same public store API. Their real checkpoint publication, state application,
bounded value slicing and required-backend-failure checks remain intact. The application chain,
checkpoint bundle, lookup and transition-failure ARC witnesses each complete 1,000 release cycles
without growth; occupied-byte baselines differ by the fixtures those suites deliberately retain.
No production consumer or checkpoint format changes were necessary.

Consumer fault injection must count the actual incremental mutation, rather than infer work
from a full-map constructor or total trie nodes. The incoming-credit witness measures a successful
credit before refusing each required state hash. Creation/deletion publication witnesses measure
an actual successful batch on a separate store handle, then refuse every required hash from the
same immutable prior. Both account-store and later provision failures must occur, with guarded
reason extraction and exact prior snapshot preservation after every refusal. Independent expected
roots, literal balances and stale-plan checks remain separate from that calibration.

This corrects the accumulation-credit, created-account and deleted-account failures observed in
Linux CI run `39553045492` after incremental-store adoption. All three selected suites pass locally
with the checked optimized non-LTO unit profile and unchanged expected output; each retains its
1,000-cycle ARC witness without growth. Production store behavior and compiler flags are unchanged.
Exact-head Linux verification remains separate.

Reproduce measurements without changing a checkout or Git ref:

```sh
STATE_STORE_BASELINE_REF=6e300dd4 make measure-state-store
```

The tool archives only project sources from the explicit reviewed baseline, compiles the identical
current workload against both source trees with the same compiler/library/profile, and executes
each binary twice. It refuses changed compiler/crypto inputs, incompatible report metadata,
missing/duplicate cases or divergent repetitions. The four Python validator tests exercise those
numeric/report refusals. Existing local reports can instead be supplied with
`STATE_STORE_BASELINE=path/to/results.json`; full evidence lives under
`build/tests/state-store-measurements/`. Make owns setup and maintained observer preparation.

Observed checked optimized macOS ARM64 results (64 updates per case, 33-byte values):

| Entries | Retained snapshots | Baseline Blake2b calls | Incremental calls | Baseline peak occupied bytes | Incremental peak occupied bytes |
| --- | --- | --- | --- | --- | --- |
| 128 | 1 | 24576 | 640 | 57792 | 128544 |
| 128 | 8 | 24576 | 640 | 159088 | 237776 |
| 1024 | 1 | 294848 | 1152 | 410048 | 1079504 |
| 1024 | 8 | 294848 | 1152 | 1127792 | 1805184 |

Both repetitions agree exactly, and the archived-reference baseline reproduces the independently
captured pre-change baseline exactly. The 1,024-entry cases perform 99.6% fewer Blake2b calls;
peak live occupied memory increases by 669,456/677,392 bytes for one/eight retained snapshots.
Initialization increases by 565,168 bytes in those cases. Absolute occupied bytes include the
same authored input mapping and retained snapshots; deltas expose the added cached trie and
separately owned payloads. These are crypto-work/live-memory observations, not total allocation
counts, RSS, throughput or wall-clock latency claims. Descriptor merging remains O(n), and
reducing the measured memory cost needs a separately justified representation change.

All stated evidence is local to this checked profile. Exact-head Linux CI remains separate.
The scoped three-PR in-memory tranche is complete; disk/canonical-head integration and startup
configuration remain deferred, and the existing M1/serialization completion gates are unchanged.
