# Light snapshot publication memory

This storage-only improvement keeps [light file publication](storage-light-files.md)
and its fixed chain/root/policy binding, exact canonical bytes, atomic replacement,
durability receipts, pending cleanup and uncertain-IO recovery contracts.

The baseline copies an entire prepared image through `.bytes` before calling the
existing synchronous manifest writer. The hypothesis is that an owner-bound read-only
`lent seq[byte]` view removes that temporary image while preserving the same single
native write request and all file/rename/directory synchronization boundaries.
Keep the improvement only if matched native memory observations and IO counts agree.

`encodedBytes` borrows immutable canonical bytes from its prepared snapshot owner.
Callers must keep the owner alive for the borrow. Direct mutation and escaping a local
owner must be rejected by the compiler; assigning a mutable sequence makes an independent
copy. The ordinary `.bytes` API keeps its copying contract. A default view access is
runtime-guarded. No mutable pointer, callback-retained borrow, unchecked image constructor
or format fallback is introduced.

File initialization and replacement borrow the canonical bytes only for the synchronous
existing writer call. They retain the prepared owner throughout that call. IO uncertainty
still blocks fresh cache access until close and validated reopen. Previously retained
readers and prepared images remain valid after success, failure or file close.

Use the existing independently rooted 4,096-key images with 64/1,024-byte values. Fixture
production runs separately. Fresh native consumers load and verify the source, initialize
a destination, perform eight real replacements, close, check all retained values and
retire all ARC ownership. Publication requires eight writes, sixteen syncs and eight
renames, with no proof/checksum hashes during the publication window. Parent observers
verify exact selected file SHA-256 after the native child exits, then remove only the
owned destination's CURRENT/LOCK names. Observers/producers are excluded from native RSS.
No latency or physical IO throughput improvement is inferred; OS cache policy is unchanged.

Completion checks cover no-copy live views, independent mutable extraction, owner-lifetime
and mutation compiler rejections, default runtime guards, retained readers, failed file
publication/recovery, exact publication IO counts and 1,000 ARC lifetimes, plus affected
snapshot/file/update consumers. Compare matched samples in both build orders and preserve
all native verdicts, flags, source/provider identities and resource receipts.

## Local measurement

Baseline `970a02d4`, macOS ARM64, pinned Nimony
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, ARC/Clang checked release speed and ThinLTO.
Forty fresh native consumers cover ten samples per build/fixture, five in each paired
build order. The source and destination images, retained memory, IO counts and exact
ARC retirement agree for every matched case.

| Value bytes | Copying publication median peak RSS MiB | Borrowed publication median peak RSS MiB | Reduction |
| ---: | ---: | ---: | ---: |
| 64 | 12.296875 | 7.625000 | 38.0% |
| 1024 | 24.875000 | 16.453125 | 33.9% |

Each consumer initializes one destination and performs eight real full-image replacements.
Only the eight replacements contribute the reported eight writes, sixteen syncs and
eight renames; initialization retains its normal additional barriers. Source restoration
performs exactly 73,729 hashes and publication performs zero hashes. All 4,096 retained
values are checked after file close. Live ARC bytes before/after the eight publications
are 5,837,776 or 13,702,096 for the two fixtures in both builds. Complete scope retirement
returns to the consumer's initial ARC baseline. The parent requires native success and
checks selected-file SHA-256 against the independent producer image before exact cleanup.

Whole-native RSS includes source restore, initialization, publications, retained-value
checks and retirement; it excludes producer/Python observer memory. No unrelated peaks
are subtracted to estimate an in-call component. No latency or physical IO throughput
claim is made. OS cache policy is unchanged; Valgrind and Hyperfine are unavailable here.

The maintained source is `tests/performance/storage_light_publication_workload.nim`.
It supports the fixed existing `produce`/`consume` modes and `publish <64|1024>
<source-directory> <independent-root> <destination-directory>`. Build through
`NativeChecks` after Make-owned setup with ARC/Clang checked release speed and ThinLTO,
crypto observer and storage IO observer, the SDK-first `native/storage_io/redirect.h`
header and WRITE/FSYNC/RENAMEAT observer flags. `tools/storage_limit_child.py` requires an
absolute native executable. Both observer and saved native verdict must succeed.
The parent observer validates/removes destination files after child exit.

Ignored `build/storage-db32-measure/{identity,fixtures,baseline-build,candidate-build,
observations}.json` retain source, binary/provider/observer hashes, exact flags and
all resource receipts; `workload.nim`, `build.py` and `observe.py` record the fixed plan.
Initial pilot samples with an early output-temporary ARC observation are rejected and
excluded. The accepted workload samples retirement after all resource temporaries leave
scope; pilot destination files were removed only after proving their exact selected bytes.

## Verification

The focused borrowed-bytes suite and affected snapshot, file-cache and incremental-update
consumers pass through the checked native runner. Borrowed reads make no payload allocation;
mutable extraction and owning returns remain independent; retained readers/edits remain
valid. Its 1,000 borrow/copy/edit cycles retain 1,216 occupied ARC bytes before/after.
Fifteen snapshot/file runtime guards, twelve positive controls, seven privacy rejections,
two concrete borrow mutation/lifetime compiler rejections and actual owner-duplication
lowering rejection pass. Existing real write, file-sync, rename and directory-sync refusal
recovery passes. Formatting and inventory pass. Local results do not claim exact-head
Linux CI or production power-loss qualification.
