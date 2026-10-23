# Bounded admission: measured qualification

The [contract](storage-bounded-admission.md) starts at merged
`d5064139a6775faf2b82c53d941522ab7d65ae31`. The clean baseline capture is
`08bd7723cb8000ee34d9ad8cd4c5050f23a97f47`; the clean final candidate is
`048c01e9542f5a3c72eb562a247bcd0ebc7c1a4d` (layer 27). The two production changes are
`src/storage/record_codec.nim` and `src/storage/node_repository.nim`. The only other approved
benchmark-input difference is `Makefile`, which adds optional paired-run targets. No compiler,
provider, native fixture, physical format, checked build flag or default Perf workload changes.

The [ordinary Linux allocation diagnosis](storage-bounded-admission-evidence.md) refreshed the
actual baseline and found leaf-payload allocation refusal during complete detached-batch
materialization. The implementation now preflights whole serialized inputs, decodes/hashes one
record at a time, stages private immutable owners and admits complete graphs before publication.
It does not bypass validation of public mutable transports or confer graph authority on callbacks.

## Matched fresh-process memory observations

Host: Apple M1 Max, Darwin 27.0.0, ARM64, 16 KiB pages. The maintained
`make bench-storage-reopen-pair` driver completed eight producer invocations and sixteen fresh
consumer opens: case/binary orders reverse on the second pass, with baseline and candidate
producer directions checked. Both readers consume the same closed namespace in each pair.
Every case matches both original captures' selected file hashes and expected roots, complete-map
checks, physical node counts, independent view lifetime and final allocator release. Whole-child
RSS and retained live Nim allocation are different observations; ordinary cache policy and
ambient scheduling remain host behavior. No timing speedup or exact allocation-site byte
attribution is claimed.

| Backend | Entries | Baseline RSS range MiB | Candidate RSS range MiB | Baseline live Nim MiB | Candidate live Nim MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| journal | 32768 | 57.2–57.2 | 43.3–43.3 | 18.7–18.7 | 18.7–18.7 |
| journal | 131072 | 240.3–240.3 | 165.9–165.9 | 74.2–74.2 | 74.2–74.2 |
| managed | 32768 | 63.8–63.8 | 43.3–43.3 | 18.7–18.7 | 18.7–18.7 |
| managed | 131072 | 240.2–240.2 | 172.6–172.6 | 74.2–74.2 | 74.2–74.2 |

The earlier clean implementation-only capture at
`acc23b3fd2c170851f2c339d9b32f8f0b5c12ac2` independently produced the same journal peak and a
170.6–172.6 MiB managed range for 131,072 entries. The final maintained-driver run therefore
reproduces the reduction after the full failure/ownership matrix and observer tooling were added.
Neither run reduces the full retained graph floor or establishes cold-cache/out-of-core behavior.

Local receipts: `build/storage-db9-final-paired/results.json`, `summary.md`, raw process logs and
resource counters; frozen captures under `build/storage-db9-baseline/` and
`build/storage-db9-candidate-final/`. Read-only Make summary validation passed without executing
any imported command. All 447 candidate benchmark-input hashes match the current checkout.

| Identity | SHA-256 |
| --- | --- |
| Baseline native executable | `f0b5c1e9633dfb4d852060edc0d058fba2ab2c77f066e626d75b42d4f6ec906e` |
| Candidate native executable | `14e0dfd71bb0377965305aa9016efbdf68ad842f20c18c17f0e7ac2a97b41b36` |
| Paired report | `0a5e1bff6b9dc7773f42edd0d797cfae69b84fc7fcdb2f1d9197c7c99bcd9077` |
| Paired driver | `7e4cba9031162ef3b0769044615022350e45c45f8f8cd2a89059b952316bf537` |
| Shared comparison validator | `1049435f52c92dd199acc46adcc9964da741436df80730cc1125c749e5755d9e` |

## Scoped Linux resident pressure

[Run 39844545831 / job 120054259600](https://github.com/jacogr/ragnarok/actions/runs/39844545831/job/120054259600)
passed in **8m34s** at the exact clean layer-27 head above. This is the existing explicit
`storage-pressure` scope; it adds no default Perf job, matrix, sample or timeout change.
Host: AMD EPYC 9V45, Linux 6.17.0-1022-azure x86-64, glibc 2.39. The private cgroup enforcement
probe passed before native setup. Artifact `storage-resident-pressure-1` retains the executable,
raw reports, limits/events/PSI/I/O/swap counters, native logs and retirement receipts.

Independent validation matched all 447 source hashes against the checkout and SHA-256
`c22ee5e940fc12e5e667533d7db7b32a368c741167b82d265421ddb6f3088cba` against the downloaded
ordinary native executable. It reparsed the maintained strict report, all 48 observations,
16 unrestricted before/after controls, actual command/limit enforcement, selected-byte hashes
and service cleanup. Only the fixed remote build-path interpretation is adapted for cross-host
validation; no artifact is rewritten and no imported command or executable is run locally.

There are **36 completed opens, 8 observer timeouts and 4 local cgroup OOM kills**, with no
unavailable treatments. Every unrestricted control completes, every selected file remains
unchanged even on refusal/timeout, and every owned service retires. All 32,768-entry observations
complete. The larger cases retain the following separate outcomes on both passes:

| 131,072-entry treatment | Journal | Managed |
| --- | --- | --- |
| Unrestricted before/after | Completed; child RSS 169.8–169.9 MiB | Completed; child RSS 175.7–175.9 MiB |
| High 128 / max 512 MiB, no swap | Observer timeout, 35-second native deadline | Observer timeout, 35-second native deadline |
| High/max 128 MiB, no swap | Local cgroup OOM kill | Local cgroup OOM kill |
| High 128 / max 256 MiB, no swap | Observer timeout | Observer timeout |
| High 128 / max 256 MiB, swap allowance 256 MiB | Completed, 5.75–6.22 seconds | Completed, 5.52–5.83 seconds |

Both larger swap-enabled layouts actually page: kernel swap peaks are 114.7–131.4 MiB for
journal and 130.2–132.0 MiB for managed. These are observations, not a timing speedup claim.
Successful large cases retain 74.2 MiB live Nim allocation and return it completely after held
views release. Unrestricted unit peaks include observers, kernel and file-cache charges:
226.7–226.9 MiB journal and 232.7–232.9 MiB managed, distinct from native child RSS.

All capped treatments retain a **128 MiB soft high watermark**. Consequently the max-256
no-swap timeout is not an isolated 256 MiB hard-cap experiment. Per-file eviction advice is not
proof of a fully cold host cache; block activity includes native loader/storage work. The
unchanged outcome categories do not qualify either larger 128 MiB no-swap workload. The measured
macOS transient reduction and successful Linux controls therefore do not imply a smaller
retained graph, recoverable allocation failure or out-of-core storage.

Local strict receipts: `build/storage-db9-linux-39844545831/independent-validation.json`,
`validated-observations.json` and `build/storage-db9-linux-validation.log`. The final evidence,
usage and status layers change documentation only; all 447 native measurement inputs remain
byte-identical to the completed layer-27 Linux run.

## Functional and ownership coverage

Local checks use the pinned Nimony compiler, ordinary native allocator and checked ARC/Clang
release/LTO. Structural/record delivery, inspection/preparation, detached codecs, image decode,
encoded/raw publication and delivery-footprint suites pass. Affected snapshot/journal/context,
disk replay, managed reopen, context owner and compaction consumers also pass; results are reused
only while their covered runtime inputs remain unchanged.

The new focused failure matrix passes policy precedence, staged image refusal, per-retained-root
policies, raw/fused mutable-source independence, malformed whole-input zero-work, primitive
refusal after successful prefixes, graph authority under every full/delta permutation and
real-file inner corruption behind valid outer checksums/bindings. Repeated admission
failure/ownership suites retain 1,000-cycle ARC release evidence; finite exhaustive malformed and
real-fsync matrices run once. Failed encoded publication does not install a head, failed image
admission drops staged cells, held views remain independent and failed file opens release locks.

Five new compiler rejections protect the scan, callback binding, decoded-cell factory and both
stages using exact private-module diagnostics. Those and three related existing guards passed
with successful worker controls; private diagnostic predicate tests also passed. Eight paired
Python tests reject substituted binaries/providers/observers, paths, commands, rows, counters,
roots, maps, byte hashes, ownership namespaces and host/environment identities. Related
fresh-reopen, comparison, resource-validation and Make safeguards passed locally. One mocked
Make package-manager fixture exceeded its ten-second subprocess deadline during the combined
run; its isolated unchanged retry passed. Pinned formatting and verification inventory pass.
These local checks are separate from the exact-head Linux pressure workflow, which does not
claim a complete unit, compiler-guard, Python or interoperability CI run.
