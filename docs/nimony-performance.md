# Checked-LTO Nimony migration comparison

Local macOS ARM64 measurement on 2026-10-17; seven native batch samples per case. Both builds use
ARC, Clang/LTO and their checked release profiles. The identical workload is compiled against
pre-port commit `aea27ad0789ddb0abbea24c3923d0eb192a67e3a` with Nim 2.2.12 and current Nimony sources.
The retained backend build commands confirm Clang `-O3` and LTO in both builds.
Both adapters call the same native crypto library. This measures the migration, including changed
result/ownership representations; it does not isolate compiler code generation alone.

| Operation | Nim 2 median, ns/op | Nimony median, ns/op | Nimony / Nim 2 |
| --- | ---: | ---: | ---: |
| observer | 7.14 | 2.89 | 0.405 |
| natural decode | 7.90 | 6.01 | 0.761 |
| E4 sequence decode 4096 | 6507.36 | 3606.08 | 0.554 |
| E4 sequence encode 4096 | 13226.10 | 7168.27 | 0.542 |
| owned bytes decode 64 KiB | 1746.10 | 1729.54 | 0.991 |
| owned bytes encode 64 KiB | 1030.23 | 1051.84 | 1.021 |
| Blake2b 64 KiB | 66091.72 | 66143.57 | 1.001 |
| Keccak 64 KiB | 100605.10 | 100514.65 | 0.999 |
| Ed25519 verify 64 KiB | 149599.62 | 149749.53 | 1.001 |

The tested bulk sequence paths improve by roughly 45–46%; owned-byte operations are within about
2%, and shared-provider crypto cases are within about 0.1%. Tiny-call measurements include a
different observer/call overhead, shown explicitly rather than subtracted. Differences near unity
are noise-sized observations, not demonstrated performance wins or regressions.

No production optimization was made for this comparison. Setup, process startup, compilation,
fixture preparation, preflight and output are excluded from native batch time. A non-LTO shared
observer makes complete results visible; the workload has an identical noinline operation boundary.
Equal odd iteration counts preserve result fingerprints. Execution order alternates per sample;
every case has matching fingerprints. The ordinary correctness corpora remain the authority for
wire/crypto correctness; timing does not replace them.

Limits: one host/session, no CPU affinity/frequency isolation, no contention, cold-cache, full-client
or network-throughput measurement. No Linux performance claim follows. Assertions, bounds and
access protection remain enabled; Nim 2 additionally retains its range/field/overflow checks.
Intentional Nimony arithmetic wrapping is not exercised by these valid-input workloads.

This resolves the bounded local migration-performance gate without showing a broad regression in
any measured path. It is not a promise for other workloads or future compiler versions.

## Reproduction and evidence

After normal correctness verification has built the native library:

```sh
python3 tools/compare_nimony.py --baseline-compiler /absolute/path/to/nim-2.2.12
```

Workload: `tests/performance/compiler_workload.nim`; observer: `tests/performance/observe.c`.
`build/nimony-comparison/results.json` retains raw samples, exact build commands, both source
inventories/hashes, compiler versions, Clang/platform metadata and workload/observer/native-library
hashes. Adjacent logs and isolated snapshots retain the actual builds. Historical source is
extracted from Git without altering the checkout or adding a production compatibility path.
