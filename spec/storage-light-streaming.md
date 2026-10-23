# Streaming light snapshot proof verification

This storage-only improvement reduces temporary proof storage during canonical light
snapshot restoration. It preserves [owned buffer restoration](storage-light-restore-memory.md),
independent expected chain/root authority, exact on-disk bytes, future mutation limits,
proof semantics and file publication/uncertainty contracts.

The decoder still completes all format, identity, order, node/value/aggregate-size,
length and native-extent checks before hashing or input-derived allocation. It verifies
the complete checksum before invoking a proof reader. The change then reads and verifies
one bounded proof at a time into a private final cache, instead of retaining a complete
second set of encoded proof nodes and raw values plus admission/merge scratch.

`restoreLightStateCache` takes a fixed count and synchronous proof-reader closure.
It checks count/item/native bounds before allocation or invoking the reader. Nil readers
are uninitialized; negative counts exceed policy. It calls each index exactly once in
increasing order, requires strictly increasing keys, and checks each returned proof's
shape/value/aggregate limits before verification. Duplicate keys and descending order
are typed errors. Its final cache and inherited policy become visible only after every
proof succeeds. A refused suffix retires the whole private prefix. Future batch-write
limits do not restrict restoration; original cache constructors keep their contracts.

The reader is borrowed for this synchronous call and is never retained in the cache.
It must keep its backing input stable and bound its own per-item work/allocations; it
must not expose mutable private cache state. It may return ordinary untrusted proofs,
not pre-authenticated data or an unchecked success flag. Every proof is verified against
the same independently supplied complete root. The snapshot reader operates only on
already preflighted immutable input and maintains one explicit cursor.

Measure the same independently rooted 4,096-entry 64/1,024-byte value images as the
owned-restore record. Compare fresh native peak RSS in both paired build orders with
identical images, roots, 73,729 hashes, retained cache/image memory and ARC retirement.
No latency or physical IO win is inferred. Keep the change only for a repeatable memory
reduction with all validation and ownership witnesses intact.

Completion checks cover count/nil preflight before callbacks; reader order and quotas;
missing, malformed and wrong-root proofs; canonical/negative/present-empty lookups;
late provider failure and atomic retirement; callbacks not retained; zero future-write
limits; 1,000 success/failure/recovery lifetimes; affected snapshot/file/update/owned
restore consumers; and native ownership and result guards.

## Local measurement

Baseline `57c006a4`, macOS ARM64, pinned Nimony
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, ARC/Clang, checked release speed and ThinLTO.
The exact prior measured owned-restore binary is reused (its source differs from that
base only by a comment space). Final streaming code is rebuilt with identical flags,
workload and provider. Ten fresh consumers per build/fixture, five in each paired order,
supply40 consumer observations. No timing claim is made; Valgrind/Hyperfine remain
unavailable on this host.

| Value bytes | Owned-restore median peak RSS MiB | Streaming median peak RSS MiB | Reduction |
| ---: | ---: | ---: | ---: |
| 64 | 13.781250 | 7.593750 | 44.9% |
| 1024 | 27.687500 | 16.421875 | 40.7% |

Every consumer verifies all 4,096 values and exactly 73,729 hashes. Image sizes remain
4,886,656/8,818,816 bytes. Retained open-owner ARC bytes remain 5,837,664/13,701,984;
a retained reader after close holds 856,576/4,788,736 bytes. Complete retirement returns
to the 400-byte initial ARC baseline. Independent flat-map root calculation and proof
production run separately. Roots, input image SHA-256 and per-consumer witnesses agree.
The scope includes native reopen plus all lookups, excluding producers and Python
observers; OS cache policy is unchanged. Peaks from different processes are not subtracted
to estimate any component.

Reuse `tests/performance/storage_light_reopen_workload.nim` and the absolute-executable
`tools/storage_limit_child.py` recipe in the owned-restore record. Require the saved native
receipt's zero exit as well as observer success. Reproduction records are ignored
`build/storage-db31-measure/{identity,fixtures,baseline-build,candidate-build,observations}.json`,
with exact source snapshots, workload, build/observer scripts, binary hashes, linked provider
hashes, flags and every native resource receipt. Provisional pre-nullability measurements
are retained as `.initial` records; the table uses the final rebuilt candidate.

## Verification

The focused streaming suite and five affected snapshot, file-cache, incremental-update,
owned-restore and original-cache consumers pass through the checked native runner.
Nil/count/native limits precede callbacks; duplicate/descending keys, missing and
wrong-root evidence, per-proof/aggregate quotas, empty-root absence, immutable source
independence, later provider refusal and exact reader order are covered. Its 1,000
success/partial-failure/retry cycles retain 1,216 occupied ARC bytes before/after.
Eleven cache/file runtime guards, eight positive controls, three privacy rejections
and actual owner-duplication lowering rejection pass. Formatting and inventory pass.
Local evidence does not claim exact-head Linux CI or production power-loss qualification.
