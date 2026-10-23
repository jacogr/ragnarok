# Exact owning physical trie exports

Scope: allocate the preflighted record descriptor extent exactly for full/delta/inverse physical
exports and offer once-only result ownership transfer. Preserve child-before-parent record order,
full physical identities, detached mutable payloads, omission semantics, budgets and complete
source graphs. Existing copying result access remains compatible. Changes stay in standalone
storage, source-owned tests/guards and this feature contract.

## Measured problem and implementation

Public ARC calibration on parent `6b0a4855` measures a fixed 8192-entry graph with 16386 physical
nodes. An exact `seq[TrieRecord]` allocation occupies 2424832 bytes; the growable export result
retains 3080192 descriptor bytes, including 655360 bytes (640 KiB) of spare capacity. With 256-byte
values, its whole result retains 5177344 bytes, including independently calibrated payload owners.
A separate copying `.value` accessor adds another 4521984 bytes while the result remains held.
The zero-byte-value case adds another 2424832 bytes. Both are ownership costs, not graph-layout
or deployment RSS observations. Baseline source/build/scalar evidence is under ignored
`build/storage-db21-baseline-*`.

Export preflight already traverses the immutable source/base pair, counts exact emitted records,
bounds descriptor count by caller policy and `high(int) div sizeof(TrieRecord)`, and proves copied
payload totals before allocation or hashing. Allocate that exact count once. The existing recursive
writer fills successive checked slots, still emitting children before their parent and copying
each leaf payload independently. The same immutable omission decisions are used in both walks;
the final cursor must equal the allocated extent. No growable descriptor capacity survives,
and no partial output can escape a refused preflight. Allocation exhaustion remains fail-stop.

`TrieResult.takeValue` requires success, moves its completed revision/value/export out once and
resets the consumed result to `Uninitialized`. It transfers no source-graph mutation authority.
Default, failed and already-consumed outcomes cannot be extracted. Existing `.value` still copies
raw transports independently and still retains immutable revision/value owners according to their
existing semantics. No public raw-success constructor, discriminator or writable payload is added.
For a large transport, callers can choose transfer without duplicating the descriptor/value graph:

```nim
var exported = exportFullTrie(trie, limits)
if exported.error == TrieError.None:
  let batch = exported.takeValue
  # batch owns detached mutable records; exported now has only Uninitialized.
```

## Verification

`full_state_trie_exports` calibrates every held export against independently allocated exact
record/value buffers at empty, singleton, descriptor boundary and larger map sizes with zero,
33-byte and 256-byte values. Independent flat-map roots and strict repository admission verify
full/delta/inverse/no-op/empty-target exports, historical readers, exact root/count metadata,
unchanged source ownership, copying extraction isolation and allocation-free once-only transfer
of raw exports, immutable revisions and retained values. Narrow record/value budgets refuse
without hashing; the suite requires 1000 scoped ARC cycles. Existing complete/incremental trie,
physical export, codec, replay and StateStore/disk consumers remain affected checks without
changing those application implementations.

The maintained `full_state_trie` failure family adds default/failed/consumed raw-export transfer
cases with exact `AssertionDefect` diagnostics and a valid transfer control. Private result,
revision and value compiler guards remain. Pinned formatting and inventory are publication checks.
Matched parent/candidate public calibration must preserve descriptor/value classes, copying
accessor allocation, complete counts, canonical wire checksum and exact release. Preserve full
source/compiler/provider/build identities, commands, raw scalar observations and local logs
under ignored `build/storage-db21-*`; do not infer peak RSS from occupied-heap endpoint deltas.

Measured runtime source is `61d14342`, parent `6b0a4855`. Seventeen affected native suites pass,
including exact 1000-cycle export ownership. The maintained runtime family passes all ten exact
`AssertionDefect`/diagnostic cases, including the three new transfer refusals, plus a successful
owned-export transfer control. Four private trie/result/value compiler checks, pinned formatting
and inventory remain separate publication evidence. A later probe-only adjustment keeps the first
transferred export alive during the consumed-result refusal; runtime source remains unchanged.

Twenty matched checked native processes cover both binary orders with five repetitions, each
observing the same two fixed maps. Every observation preserves complete counts, calibrated
allocation classes, copied output, wire checksum and exact source/result/copy retirement.

| Fixed 8192-entry export | Parent result | Candidate result | Saving |
| --- | ---: | ---: | ---: |
| Empty values | 3080192 bytes | 2424832 bytes | 655360 bytes (21.3%) |
| 256-byte values | 5177344 bytes | 4521984 bytes | 655360 bytes (12.7%) |

The copying accessor still adds exactly 2424832/4521984 bytes for these cases. The owning accessor
adds no allocation in the separately checked full/delta/inverse, revision and retained-value
witnesses; its source becomes `Uninitialized`. Do not sum independent observations into a peak
RSS or deployment-ceiling claim. No time/speedup claim is made.

Strict canonical transport BLAKE2b-256 checksums remain
`daa9e8eebd64c26d135b7d7dcaa5a08ff0b770618729ba74945e5c67dd1e8526` (empty values) and
`6b16011570e3be0174e7c6a89bdd2506321a334ecdaad0679639f85bb24a671e` (256-byte values).
`build/storage-db21-measure/observations.json` retains every command, native result, raw scalar
observation and source/compiler/library/binary/build identity. Reproduce with
`build/storage-stack-build.py build/storage-db21-measure.json`, then
`build/storage-db21-observe.py` in a new private evidence directory. The fixed source is
`build/storage-db21-export-workload.nim.txt`. Runtime transfer evidence and control are
`build/storage-db21-transfer-guards/results.json` and `control.json`; selected native/guard/format/
inventory logs share the `build/storage-db21-` prefix. These are scoped local checked native results.

## Limits

Export payloads remain independent copies and the complete immutable graph remains resident.
Exact extent still includes normal allocator rounding. `.value` intentionally keeps copying;
consumers must select `takeValue` to transfer once. There is no streaming, zero-copy alias into
private graphs, format migration, provider/compiler/allocator change or new StateStore/application
adoption. M1 framing is complete; full JAM state serialization and whole-block parity remain open.
Scoped local checks remain separate from exact-head Linux CI and routine performance CI is unchanged.
