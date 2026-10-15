# Checked complete-report and guarantee workload

Host: macOS-27.0.1-arm64-arm-64bit-Mach-O. Nim: checked ARC/Clang LTO only.
Processes/case/candidate: 3; batches/process: 7; individual latencies/process: 128.

Times below are median µs/operation across native batch averages. Individual p95 is separate.

| Report | Stage | Nim µs | Odin µs | Mojo µs | Nim p95 µs | Odin p95 µs | Mojo p95 µs |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| official | decode | 0.242 | 0.288 | 1.347 | 0.292 | 0.334 | 1.458 |
| official | encode | 0.199 | 0.195 | 0.911 | 0.250 | 0.250 | 1.084 |
| official | owned | 0.329 | 0.415 | 1.609 | 0.375 | 0.500 | 1.708 |
| official | hash | 0.528 | 0.521 | 0.912 | 0.584 | 0.583 | 1.000 |
| official | verify2 | 71.364 | 114.438 | 71.258 | 74.458 | 119.333 | 75.500 |
| official | pipeline | 72.148 | 115.363 | 74.128 | 76.791 | 121.208 | 76.208 |
| minimal | decode | 0.213 | 0.256 | 1.132 | 0.250 | 0.292 | 1.292 |
| minimal | encode | 0.149 | 0.152 | 0.666 | 0.208 | 0.167 | 0.750 |
| minimal | owned | 0.302 | 0.382 | 1.391 | 0.375 | 0.417 | 1.500 |
| minimal | hash | 0.397 | 0.401 | 0.785 | 0.459 | 0.458 | 0.834 |
| minimal | verify2 | 72.731 | 116.935 | 72.406 | 79.500 | 123.292 | 76.125 |
| minimal | pipeline | 72.982 | 117.365 | 74.299 | 77.375 | 128.000 | 77.917 |
| typical | decode | 0.426 | 0.409 | 2.108 | 0.500 | 0.459 | 2.209 |
| typical | encode | 0.621 | 0.398 | 1.850 | 0.667 | 0.459 | 1.958 |
| typical | owned | 0.703 | 0.745 | 2.538 | 0.791 | 0.792 | 2.667 |
| typical | hash | 5.275 | 5.164 | 5.670 | 5.417 | 5.708 | 6.125 |
| typical | verify2 | 71.847 | 116.274 | 72.480 | 73.417 | 121.500 | 77.542 |
| typical | pipeline | 79.488 | 123.986 | 81.717 | 82.625 | 128.125 | 86.792 |
| maximum-metadata | decode | 0.997 | 0.935 | 5.214 | 1.084 | 1.000 | 5.209 |
| maximum-metadata | encode | 1.554 | 1.045 | 5.132 | 1.625 | 1.084 | 5.291 |
| maximum-metadata | owned | 1.128 | 1.125 | 5.441 | 1.208 | 1.209 | 6.042 |
| maximum-metadata | hash | 2.257 | 2.191 | 2.675 | 2.292 | 2.375 | 2.750 |
| maximum-metadata | verify2 | 72.831 | 116.763 | 72.598 | 79.042 | 123.125 | 81.916 |
| maximum-metadata | pipeline | 75.793 | 119.493 | 81.260 | 85.458 | 128.542 | 84.875 |
| maximum-payload | decode | 1.025 | 0.977 | 5.275 | 1.083 | 1.083 | 5.417 |
| maximum-payload | encode | 2.214 | 1.694 | 6.200 | 2.292 | 1.792 | 6.708 |
| maximum-payload | owned | 3.788 | 4.306 | 7.739 | 4.042 | 4.334 | 8.042 |
| maximum-payload | hash | 52.926 | 51.299 | 53.382 | 55.250 | 53.000 | 54.875 |
| maximum-payload | verify2 | 72.637 | 116.307 | 72.628 | 77.542 | 121.208 | 75.500 |
| maximum-payload | pipeline | 130.641 | 171.733 | 133.107 | 144.208 | 181.750 | 139.625 |
| maximum-auth | decode | 0.339 | 0.284 | 1.587 | 0.375 | 0.334 | 1.708 |
| maximum-auth | encode | 1.037 | 0.879 | 2.033 | 1.333 | 1.042 | 2.125 |
| maximum-auth | owned | 2.917 | 3.480 | 4.082 | 3.250 | 3.833 | 4.625 |
| maximum-auth | hash | 51.013 | 49.405 | 51.115 | 51.166 | 51.333 | 53.125 |
| maximum-auth | verify2 | 71.548 | 114.819 | 71.380 | 74.917 | 120.750 | 73.666 |
| maximum-auth | pipeline | 126.240 | 168.906 | 127.160 | 135.375 | 178.458 | 133.500 |
| maximum-lookup | decode | 0.485 | 0.284 | 1.846 | 0.542 | 0.333 | 1.917 |
| maximum-lookup | encode | 0.440 | 0.173 | 1.374 | 0.500 | 0.209 | 1.459 |
| maximum-lookup | owned | 0.583 | 0.433 | 2.131 | 0.625 | 0.500 | 2.209 |
| maximum-lookup | hash | 0.937 | 0.916 | 1.342 | 1.000 | 0.959 | 1.459 |
| maximum-lookup | verify2 | 74.241 | 117.484 | 73.518 | 78.917 | 120.584 | 75.833 |
| maximum-lookup | pipeline | 75.353 | 119.027 | 77.608 | 78.458 | 133.333 | 79.917 |

`owned` includes capture, canonical re-emission and last-owner release. `hash` includes the
normative guarantee domain. `verify2` verifies two distinct prepared ordinary-key credentials.
`pipeline` includes all these operations together. No startup, file I/O or credential imports are timed.

Nim/Mojo use the pinned BoringSSL primitive bridge; Odin uses pinned core crypto. Verification
differences include provider choice. The unresolved small-order Ed25519 acceptance policy remains a gate.

Allocation observations, exact commands, source/binary/input hashes, affinity, toolchains,
raw paths and provider provenance are retained in `comparison.json.gz`. Counter scopes differ; Mojo has no public allocation-call counter.
