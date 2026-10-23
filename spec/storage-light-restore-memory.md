# Light-file restore ownership and memory

This standalone storage improvement keeps the canonical light image and every trust,
validation, mutation and durability contract in [light updates](storage-light-updates.md).
It changes temporary buffer ownership during reopen, without weakening proof checks,
changing the on-disk format, or selecting chain/root authority from file metadata.

The baseline extracts read bytes through a copying result accessor and then copies
validated bytes into a prepared image. The hypothesis is that transferring the owned
read result and adopting its validated buffer removes avoidable whole-image copies.
The accepted metric is fresh native process peak RSS, with retained ARC bytes and
exact proof/checksum attempts required to remain identical. No latency win is inferred.

`takeLightSnapshot` accepts `var seq[byte]`. It checks the entire image and all proofs
against independent expected chain/root and caller limits before consuming the buffer.
Success empties the caller slot and retains private immutable canonical bytes; failure
leaves the input unchanged. Existing borrowed `restoreLightSnapshot` remains a copying
operation. Safe caller aliases must remain independent of the retained prepared image.
The file owner transfers only the result buffer it owns, then uses the same decode,
publication, close and uncertainty paths as before.

Fixed measurement inputs are 4,096 sorted complete-map entries with 64-byte or 1,024-byte
values. Keys are leading big-endian two-byte ordinals followed by zeroes; value byte j
of entry i is `(i+j) and 255`. Independent flat-map root calculation and trie proof production
run in separate producer processes. Every consumer gets its independently calculated
expected root explicitly, verifies all 4,096 present values, retains a reader across
close, and checks exact ARC retirement only after every resource/temporary leaves scope.
The producer and Python observer are excluded from native child RSS. OS cache policy
is unchanged; this is not a physical IO or isolated in-call allocator-peak measurement.

Completion checks include copied/consumed input independence, safe aliases, all failure
classes leaving owned input intact, failure at every hash prefix, retained edits/readers,
1,000 exact ARC lifetimes, affected snapshot/file/update suites and ownership guards.
Matched baseline/candidate consumers must preserve image bytes, roots, hash attempts,
retained memory and resource retirement. Samples run in both build orders.

## Local measurement

Baseline `caaf509e`, macOS ARM64, pinned Nimony
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, ARC/Clang, checked release speed and ThinLTO.
Each build/fixture has ten fresh native consumers, five in each paired build order,
for 40 consumer samples. Every consumer verifies exactly 73,729 hashes and the same
retained memory, validates all values and releases to its 400-byte initial ARC baseline.

| Value bytes | Baseline median peak RSS MiB | Owned restore median peak RSS MiB | Reduction |
| ---: | ---: | ---: | ---: |
| 64 | 23.125000 | 13.781250 | 40.4% |
| 1024 | 44.546875 | 27.687500 | 37.8% |

Retained open-owner ARC bytes are 5,837,664 and 13,701,984 for the two fixtures in both
builds. After close with an immutable reader retained, bytes are 856,576 and 4,788,736.
Encoded images are 4,886,656 and 8,818,816 bytes. No image format, proof count, expected
root or synchronization policy changes. Memory reduction is measured; faster IO or
latency is not claimed. Valgrind and Hyperfine are unavailable on this host, so the
accepted evidence is repeated whole-native RSS plus exact deterministic witnesses.

The maintained source is `tests/performance/storage_light_reopen_workload.nim`:
`produce 64 <new-directory>` or `produce 1024 <new-directory>` emits the independent
expected root and image length. `consume <size> <directory> <expected-root>` validates
reopen, all lookups and exact retirement. Build through `NativeChecks` after Make-owned
setup with the crypto observer, ARC/Clang, checked release speed and ThinLTO; the full
build commands and SHA-256 identities are retained in the measurement records.
The existing `tools/storage_limit_child.py` accepts an absolute native executable and
captures each fresh consumer's resources. Require both observer success and its saved
native `exit_code == 0`; observer exit alone does not establish native success.

Ignored reproduction records are `build/storage-db30-measure/{identity,fixtures,
baseline-build,candidate-build,observations}.json`, with the exact measured
`workload.nim`, `build.py`, `build-candidate.py` and `observe.py`. Records include binary,
workload, provider and source identities, exact flags and every resource receipt.

## Verification

The owned-restore suite and affected snapshot, file-cache and incremental-update
suites pass through the pinned checked native runner. New cases cover every proper
prefix, native-count overflow, identity/size/checksum/proof failures, all eight
checksum/proof backend refusal prefixes, successful consumption, safe alias mutation,
copying restoration and retained edits/readers. Its 1,000 success/partial-failure/retry
cycles retain 1,632 occupied ARC bytes before/after. Three runtime guards, two positive
controls, three privacy rejections and actual owner-duplication lowering rejection
pass. Formatting and inventory pass. Local evidence does not claim exact-head Linux CI.
