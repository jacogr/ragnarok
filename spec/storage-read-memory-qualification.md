# Storage read-memory qualification

This storage tranche reduces transient read/decode ownership overlap. It preserves checked
ARC/Clang release/LTO, the pinned compiler and native providers, physical formats, strict
selected-file admission, exact roots/maps/generations and immutable retained views. The
[initial contract](storage-read-memory.md) records the original baseline and boundary scope.
This is storage resource qualification, not complete JAM protocol or power-loss certification.

## Ownership and bounded reads

Regular-file metadata seeds one bounded allocation. Native reads fill it directly in windows
of at most4096 bytes, retry interrupted calls, accept short progress and trim to actual EOF.
The existing excess probe detects growth after metadata preflight. Shrinkage supplies only
actually read bytes; strict snapshot/journal validation still decides admission. Metadata never
supplies an artificial valid payload or overrides typed limits.

`ManagedIoResult`, `RecordResult`, `SnapshotResult` and `FrameResult` expose a mutable,
success-guarded `takeValue`. It moves the owned payload and resets the source to `Uninitialized`.
Existing `value` access retains copy semantics. Internal consumers transfer admitted byte arrays,
record batches and replay contexts once. Private raw record admission still copies borrowed
caller data into immutable cells. Managed acquisition releases the detached snapshot input
before journal replay while retaining its actual read extent.

## Matched local observations

Baseline: `e7df0c60428c7ddd079c4d95f145b168edd85d5d`.
Candidate implementation: `0b700cf8a3c409cc335d64cbf60f7c4ef05040f0`.
Host: Apple M1 Max, macOS/Darwin27.0.0, ARM64,16KiB pages. Existing OS cache policy and
inherited limits were unchanged; no active pressure or cold-cache claim. Each of two passes
used exclusive synthetic namespaces and reversed both case and binary order. Baseline and
candidate readers consumed the same closed bytes, with producer direction reversed as well.
All16 opens validated complete roots/maps, generations, read counts and full live-Nim release.

| Backend | Entries | Baseline RSS range MiB | Candidate RSS range MiB | Baseline live Nim MiB | Candidate live Nim MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| journal | 32768 | 84.4–84.4 | 57.2–57.2 | 18.7–18.7 | 18.7–18.7 |
| journal | 131072 | 342.2–342.2 | 240.3–240.3 | 74.2–74.2 | 74.2–74.2 |
| managed | 32768 | 97.8–97.8 | 63.8–63.8 | 18.7–18.7 | 18.7–18.7 |
| managed | 131072 | 401.0–401.0 | 212.5–240.2 | 74.2–74.2 | 74.2–74.2 |

These are whole-child peak RSS observations and net live Nim allocation after open, measured
separately. At131,072 entries, journal peak RSS decreased about30%; managed decreased about40–47%
in these two observations. Managed candidate variation is retained in the range. Unchanged live
Nim allocation means the full materialized graph floor remains. Independent peaks do not identify
exact removed-copy bytes, allocator/cache retention or a general speedup.

The maintained `tools/compare_storage_reopens.py` reparses both schema2 reports and requires
clean sources, explicit approved source differences, fixed native workload/observer and matching
compiler/providers/interpreter/environment geometry. Physical files, roots, stored nodes and
check counts must match. Imported report command vectors are never executed. The reports omit
CPU/OS and active-pressure identity; the separate paired record supplies the host identity here.

Frozen local evidence under ignored `build/`:

- `storage-db8-baseline-final/` and `storage-db8-candidate/`: reports, raw logs and exact binaries.
- `storage-db8-paired/`:16 native opens,8 producers, per-child counters, byte fingerprints,
  host/build identities and forward/reverse summary.

Baseline binary SHA-256: `115924cf4f7b2c412d34d6b02384d8db8dad3dfe64149c5c74fcb9108094d2b7`.
Candidate binary SHA-256: `f0b5c1e9633dfb4d852060edc0d058fba2ab2c77f066e626d75b42d4f6ec906e`.

## Verification scope

Selected local native Make suites passed across the owning implementation changes:
`storage_read_buffers`, `storage_short_reads`, `storage_read_growth`, `storage_read_shrink`,
`storage_record_codec`, `storage_image_decode`, `storage_encoded_publication`,
`storage_snapshot_codec`, `storage_journal_codec`, `storage_context_codec`,
`storage_managed_repository`, `storage_managed_compaction`, `storage_context_repository`,
`storage_managed_publication_io`, `storage_disk_replay`, `storage_compaction_write_refusals`,
`storage_result_transfer_guards`, `storage_managed_read_preflight` and
`storage_journal_read_preflight`. Final reader-boundary and sparse-preflight checks were repeated
after the last reader retry refactor and common-trunk restack. Six Python comparison tests and
pinned formatting passed. Full local logs remain under ignored `build/storage-db8-*`.

The four runtime misuse children reached the real API guards and exited with the specific
assertion diagnostics; a successful child setup/start/join control passed. Separate pinned
compiler probes rejected immutable receivers with `cannot pass outcome to var/out T parameter`.
Those are frontend mutability checks, not ARC lowering or compiler-wide safety evidence.

## Linux resident-pressure qualification

[Run39826289827](https://github.com/jacogr/ragnarok/actions/runs/39826289827),
[job119990335960](https://github.com/jacogr/ragnarok/actions/runs/39826289827/job/119990335960),
passed on the exact candidate implementation head above. Artifact `storage-resident-pressure-1`
contains the raw reports, unit receipts, native binary and counters. Independent local validation
matched all447 recorded source hashes and the downloaded binary SHA-256,
`00fdc53aaacd4cf0e4026e6f3adddf82f44f1f78156f8baff8c21cbed8dbf8ba`.
All48 observations revalidated:36 completed,8 observer timeouts and4 local cgroup OOM kills.
All16 unrestricted controls completed; every selected-file fingerprint remained unchanged and
every private service retired. A validated panel includes the explicitly classified failures;
it does not mean that48 pressured reopens completed.

Host: Linux6.17.0-1022-azure x86_64, glibc2.39, AMD EPYC7763, Clang18.1.3 and the same pinned
Nimony5b51edfedb4d0dbd9028d9e57ac61d69dffe9410. The existing48-observation plan reverses
case/treatment order and brackets each owned namespace with unrestricted controls. Private
cgroup limits include the observer, kernel and file cache; native child RSS remains separate.
Existing host swap was available; no global swap/cache or host memory policy was changed.

| Entries | Treatment in both passes | Journal | Managed |
| ---: | --- | --- | --- |
| 32768 | Every treatment and unrestricted control | Completed | Completed |
| 131072 | Unrestricted before/after controls | Completed | Completed |
| 131072 | high128 MiB / max512 MiB / swap0 | Observer timeout | Observer timeout |
| 131072 | high128 MiB / max128 MiB / swap0 | Local cgroup OOM kill | Local cgroup OOM kill |
| 131072 | high128 MiB / max256 MiB / swap0 | Observer timeout | Observer timeout |
| 131072 | high128 MiB / max256 MiB / swap256 MiB | Completed | Completed |

Large unrestricted native RSS was244.2–244.4 MiB; live Nim allocation remained about74.2 MiB.
The eight large no-swap soft-pressure timeouts hit the35-second observer bound, with32.2–34.3s
of full memory PSI stall. They are not isolated tests of a256 MiB hard cap: both retain the
128 MiB soft limit. The four128 MiB hard-limit failures had local kernel OOM evidence.

Actual swap-enabled large reopens:

| Backend | Native RSS range MiB | Unit peak range MiB | Swap peak range MiB | Observed seconds |
| --- | ---: | ---: | ---: | ---: |
| journal | 131.3–132.2 | 129.9–130.0 | 135.5–142.9 | 8.2–8.6 |
| managed | 131.1–131.4 | 129.9–130.0 | 136.4–137.7 | 9.1–9.7 |

Nonzero kernel swap peaks and page-in/page-out deltas establish actual paging, not just permission.
For journal the two runs recorded71,170–72,335 pages in and93,308–94,643 pages out;
managed recorded93,332–95,957 pages in and112,639–116,084 pages out. These are complete-root/map
reopens with unchanged files. They remain synthetic host-specific observations, not a latency SLA
or an out-of-core storage contract. Historical Linux qualification used a different runner/kernel;
its outcomes do not supply a same-host causal speed comparison.

Local copies and the independent validation digest remain under ignored
`build/storage-db8-linux-39826289827/`. The final documentation layer changes only prose;
all447 recorded implementation/workload/tooling input hashes remain identical to the passing
implementation head. This input-equivalence check does not claim exact-head CI for the prose commit.
No default Perf Storage or Perf Storage Growth workload, sample count, job or budget changed.

## Remaining limits and next bounded work

The measured transient reduction is useful, but the full graph still materializes and the large
128 MiB no-swap cases remain unqualified. Allocation failure retains the existing fail-stop policy;
there is no new recoverable allocator or streaming/out-of-core guarantee. Disk restart still
requires complete strict format and graph admission; trusted external checkpoint import,
full/light state separation and full protocol state serialization retain their existing gates.
No new M1 completion is asserted here.

Next, refresh allocation-site and lifetime traces on this reduced-copy pipeline. Then use that
evidence to scope bounded decode/admission that avoids holding an entire detached record batch
alongside the materialized graph, preserving atomic failure and immutable caller ownership.
Measure peak and retained allocation separately before choosing retained-node layout or page
packing. Repeat only the affected fixed reopen/pressure cases for that implementation; do not
increase routine merge-feedback workloads merely to expand performance coverage.
