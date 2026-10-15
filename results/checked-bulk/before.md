# Optimized checked benchmark

Platform: macOS-27.0.1-arm64-arm-64bit-Mach-O
Linux CPU affinity: None; complete: True

Checked optimized builds share inputs and the noinline observation boundary.
Batch throughput and individual-operation latency samples remain separate.

| Case | Operation | Nim median ns/op | Odin median ns/op | Mojo median ns/op | Odin/Nim time | Mojo/Nim time | Nim alloc calls/op | Odin alloc calls/op | Mojo alloc calls/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| digest-work_result_1 | encode | 58.3 | 40.8 | 226.9 | 0.70 | 3.89 | 0.0 | 0.0 | unavailable |
| blake2b-32 | hash | 140.2 | 145.9 | 160.8 | 1.04 | 1.15 | 0.0 | 0.0 | unavailable |
| natural-18446744073709551615 | encode | 11.7 | 5.8 | 16.4 | 0.50 | 1.41 | 0.0 | 0.0 | unavailable |
| digest-1024 | encode | 1204.1 | 68.6 | 1999.0 | 0.06 | 1.66 | 0.0 | 0.0 | unavailable |
| blob-1024 | encode | 665.9 | 34.8 | 1683.6 | 0.05 | 2.53 | 0.0 | 0.0 | unavailable |
| blob-0 | encode | 13.2 | 21.4 | 17.5 | 1.62 | 1.33 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-decode | 31478.7 | 2356.9 | 106382.4 | 0.07 | 3.38 | 2.0 | 2.0 | unavailable |
| fixed-0 | encode | 6.0 | 5.0 | 12.5 | 0.83 | 2.08 | 0.0 | 0.0 | unavailable |
| digest-1048576 | decode | 69.0 | 58.0 | 222.3 | 0.84 | 3.22 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-decode | 31548.5 | 2360.4 | 107019.7 | 0.07 | 3.39 | 2.0 | 2.0 | unavailable |
| fixed-0 | decode | 6.0 | 8.0 | 8.4 | 1.34 | 1.41 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-encode | 671308.4 | 16375.0 | 1689341.6 | 0.02 | 2.52 | 0.0 | 0.0 | unavailable |
| fixed-8 | decode | 6.3 | 5.3 | 11.7 | 0.84 | 1.87 | 0.0 | 0.0 | unavailable |
| blob-65536 | decode | 13.1 | 21.4 | 33.8 | 1.63 | 2.57 | 0.0 | 0.0 | unavailable |
| sequence-32 | encode | 713.7 | 54.2 | 643.8 | 0.08 | 0.90 | 0.0 | 0.0 | unavailable |
| blob-65536 | encode | 40740.7 | 824.0 | 104586.4 | 0.02 | 2.57 | 0.0 | 0.0 | unavailable |
| blob-32 | owned-decode | 67.1 | 106.4 | 225.0 | 1.59 | 3.36 | 2.0 | 2.0 | unavailable |
| digest-work_result_1 | owned-decode | 117.6 | 120.2 | 708.7 | 1.02 | 6.03 | 2.0 | 2.0 | unavailable |
| baseline | control | 3.5 | 2.6 | 6.3 | 0.73 | 1.79 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-encode | 663091.8 | 17091.6 | 1686283.4 | 0.03 | 2.54 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-encode | 7.6 | 10.0 | 10.2 | 1.32 | 1.34 | 0.0 | 0.0 | unavailable |
| blake2b-65536 | hash | 65193.2 | 63735.2 | 65409.4 | 0.98 | 1.00 | 0.0 | 0.0 | unavailable |
| sequence-1024 | encode | 21618.6 | 1159.7 | 19748.2 | 0.05 | 0.91 | 0.0 | 0.0 | unavailable |
| blake2b-1048576 | hash | 1045504.6 | 1014694.4 | 1043037.0 | 0.97 | 1.00 | 0.0 | 0.0 | unavailable |
| sequence-16384 | encode | 337550.3 | 17954.0 | 315347.7 | 0.05 | 0.93 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | decode | 47.6 | 37.9 | 205.4 | 0.80 | 4.32 | 0.0 | 0.0 | unavailable |
| digest-65536 | encode | 66213.3 | 804.7 | 104763.0 | 0.01 | 1.58 | 0.0 | 0.0 | unavailable |
| natural-127 | decode | 5.8 | 5.1 | 9.3 | 0.89 | 1.61 | 0.0 | 0.0 | unavailable |
| natural-128 | encode | 6.0 | 7.3 | 10.6 | 1.22 | 1.76 | 0.0 | 0.0 | unavailable |
| blob-32 | encode | 31.7 | 25.7 | 62.9 | 0.81 | 1.98 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | decode | 38.5 | 30.6 | 171.8 | 0.79 | 4.47 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-decode | 497008.4 | 28041.6 | 1680875.0 | 0.06 | 3.38 | 2.0 | 2.0 | unavailable |
| blob-32 | owned-encode | 27.7 | 12.4 | 57.3 | 0.45 | 2.07 | 0.0 | 0.0 | unavailable |
| natural-0 | decode | 5.7 | 5.1 | 9.5 | 0.90 | 1.66 | 0.0 | 0.0 | unavailable |
| natural-16384 | encode | 6.6 | 8.9 | 11.5 | 1.35 | 1.74 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-decode | 545.6 | 135.4 | 1827.5 | 0.25 | 3.35 | 2.0 | 2.0 | unavailable |
| digest-work_result_0 | owned-decode | 130.7 | 125.4 | 812.6 | 0.96 | 6.22 | 2.0 | 2.0 | unavailable |
| natural-18446744073709551615 | decode | 13.0 | 11.6 | 15.4 | 0.89 | 1.19 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | owned-encode | 69.0 | 12.2 | 141.8 | 0.18 | 2.05 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-encode | 734.3 | 22.1 | 1810.2 | 0.03 | 2.47 | 0.0 | 0.0 | unavailable |
| blob-0 | decode | 10.7 | 18.9 | 32.7 | 1.76 | 3.04 | 0.0 | 0.0 | unavailable |
| blob-32 | decode | 10.7 | 18.7 | 32.6 | 1.74 | 3.03 | 0.0 | 0.0 | unavailable |
| fixed-4 | decode | 6.0 | 4.7 | 10.4 | 0.78 | 1.75 | 0.0 | 0.0 | unavailable |
| sequence-32 | decode | 133.1 | 45.7 | 227.6 | 0.34 | 1.71 | 0.0 | 0.0 | unavailable |
| digest-1024 | decode | 67.6 | 57.3 | 220.0 | 0.85 | 3.25 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-encode | 41770.2 | 804.2 | 105473.6 | 0.02 | 2.53 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-encode | 668.2 | 20.8 | 1664.7 | 0.03 | 2.49 | 0.0 | 0.0 | unavailable |
| blake2b-1024 | hash | 1030.6 | 1007.7 | 1049.8 | 0.98 | 1.02 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-decode | 51.9 | 105.9 | 176.5 | 2.04 | 3.40 | 2.0 | 2.0 | unavailable |
| fixed-4 | encode | 8.9 | 6.7 | 19.3 | 0.75 | 2.17 | 0.0 | 0.0 | unavailable |
| natural-16384 | decode | 7.9 | 10.0 | 11.4 | 1.26 | 1.43 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | decode | 13.0 | 11.6 | 15.5 | 0.89 | 1.19 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | encode | 11.7 | 5.7 | 16.1 | 0.49 | 1.38 | 0.0 | 0.0 | unavailable |
| sequence-16384 | decode | 57206.3 | 7099.4 | 99953.0 | 0.12 | 1.75 | 0.0 | 0.0 | unavailable |
| natural-0 | encode | 5.6 | 10.2 | 10.6 | 1.82 | 1.88 | 0.0 | 0.0 | unavailable |
| blob-1048576 | decode | 13.3 | 20.8 | 33.7 | 1.57 | 2.54 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-decode | 652.0 | 176.4 | 2525.2 | 0.27 | 3.87 | 2.0 | 2.0 | unavailable |
| digest-1048576 | encode | 1060091.6 | 15366.6 | 1672008.4 | 0.01 | 1.58 | 0.0 | 0.0 | unavailable |
| natural-127 | encode | 5.6 | 7.0 | 10.7 | 1.24 | 1.91 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-decode | 502708.2 | 27933.4 | 1680016.8 | 0.06 | 3.34 | 2.0 | 2.0 | unavailable |
| digest-65536 | decode | 68.7 | 57.9 | 224.0 | 0.84 | 3.26 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | owned-encode | 66.6 | 12.1 | 135.6 | 0.18 | 2.04 | 0.0 | 0.0 | unavailable |
| fixed-8 | encode | 10.8 | 7.6 | 20.8 | 0.71 | 1.93 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-encode | 42156.9 | 741.1 | 105148.1 | 0.02 | 2.49 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | encode | 74.9 | 51.9 | 233.0 | 0.69 | 3.11 | 0.0 | 0.0 | unavailable |
| blob-1024 | decode | 12.3 | 20.2 | 32.5 | 1.64 | 2.64 | 0.0 | 0.0 | unavailable |
| blob-1048576 | encode | 651950.0 | 14550.0 | 1672800.0 | 0.02 | 2.57 | 0.0 | 0.0 | unavailable |
| natural-128 | decode | 6.9 | 8.5 | 10.7 | 1.24 | 1.56 | 0.0 | 0.0 | unavailable |
| sequence-1024 | decode | 3551.9 | 477.8 | 6274.6 | 0.13 | 1.77 | 0.0 | 0.0 | unavailable |

Time ratios above one mean Nim took less time in this run; no significance is implied.
Borrowed decoding validates framing/fields without copying opaque payloads.
Owned decoding includes metadata selection and final release; prepared owned encoding excludes capture.
JSON retains samples, latency percentiles, RSS, allocation observations and source/input hashes.
Mojo exposes public process malloc live bytes here; allocation call/free counts are unavailable.
These baseline measurements imply no optimization ceiling or language winner.
