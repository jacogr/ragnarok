# Optimized checked benchmark

Platform: macOS-27.0.1-arm64-arm-64bit-Mach-O
Linux CPU affinity: None; complete: True

Checked optimized builds share inputs and the noinline observation boundary.
Batch throughput and individual-operation latency samples remain separate.

| Case | Operation | Nim median ns/op | Odin median ns/op | Mojo median ns/op | Odin/Nim time | Mojo/Nim time | Nim alloc calls/op | Odin alloc calls/op | Mojo alloc calls/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| digest-work_result_1 | encode | 44.5 | 39.3 | 231.0 | 0.88 | 5.19 | 0.0 | 0.0 | unavailable |
| blake2b-32 | hash | 138.8 | 145.0 | 160.0 | 1.04 | 1.15 | 0.0 | 0.0 | unavailable |
| natural-18446744073709551615 | encode | 11.5 | 5.6 | 16.2 | 0.49 | 1.40 | 0.0 | 0.0 | unavailable |
| digest-1024 | encode | 112.6 | 68.3 | 286.2 | 0.61 | 2.54 | 0.0 | 0.0 | unavailable |
| blob-1024 | encode | 24.8 | 34.1 | 29.9 | 1.38 | 1.20 | 0.0 | 0.0 | unavailable |
| blob-0 | encode | 12.9 | 21.3 | 17.1 | 1.65 | 1.32 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-decode | 1500.4 | 2314.7 | 1545.7 | 1.54 | 1.03 | 2.0 | 2.0 | unavailable |
| fixed-0 | encode | 8.2 | 5.0 | 12.6 | 0.61 | 1.53 | 0.0 | 0.0 | unavailable |
| digest-1048576 | decode | 66.4 | 57.9 | 220.5 | 0.87 | 3.32 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-decode | 1476.6 | 2341.2 | 1976.0 | 1.59 | 1.34 | 2.0 | 2.0 | unavailable |
| fixed-0 | decode | 6.2 | 7.9 | 7.5 | 1.29 | 1.21 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-encode | 15633.1 | 14677.0 | 21674.4 | 0.94 | 1.39 | 0.0 | 0.0 | unavailable |
| fixed-8 | decode | 5.7 | 5.3 | 10.7 | 0.94 | 1.90 | 0.0 | 0.0 | unavailable |
| blob-65536 | decode | 13.5 | 20.9 | 34.9 | 1.54 | 2.58 | 0.0 | 0.0 | unavailable |
| sequence-32 | encode | 459.9 | 55.3 | 813.9 | 0.12 | 1.77 | 0.0 | 0.0 | unavailable |
| blob-65536 | encode | 916.9 | 801.5 | 1449.2 | 0.87 | 1.58 | 0.0 | 0.0 | unavailable |
| blob-32 | owned-decode | 59.4 | 105.7 | 174.8 | 1.78 | 2.94 | 2.0 | 2.0 | unavailable |
| digest-work_result_1 | owned-decode | 80.8 | 119.9 | 580.0 | 1.48 | 7.18 | 2.0 | 2.0 | unavailable |
| baseline | control | 3.5 | 2.5 | 6.5 | 0.72 | 1.85 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-encode | 14609.8 | 18435.8 | 21612.0 | 1.26 | 1.48 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-encode | 7.2 | 9.9 | 9.9 | 1.38 | 1.38 | 0.0 | 0.0 | unavailable |
| blake2b-65536 | hash | 65138.4 | 63437.4 | 65153.0 | 0.97 | 1.00 | 0.0 | 0.0 | unavailable |
| sequence-1024 | encode | 13257.6 | 1180.0 | 24805.9 | 0.09 | 1.87 | 0.0 | 0.0 | unavailable |
| blake2b-1048576 | hash | 1042713.0 | 1014199.0 | 1044453.8 | 0.97 | 1.00 | 0.0 | 0.0 | unavailable |
| sequence-16384 | encode | 232996.7 | 18378.3 | 396755.0 | 0.08 | 1.70 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | decode | 47.0 | 38.4 | 205.0 | 0.82 | 4.36 | 0.0 | 0.0 | unavailable |
| digest-65536 | encode | 979.7 | 773.3 | 1153.6 | 0.79 | 1.18 | 0.0 | 0.0 | unavailable |
| natural-127 | decode | 5.6 | 5.1 | 9.3 | 0.91 | 1.65 | 0.0 | 0.0 | unavailable |
| natural-128 | encode | 5.9 | 8.5 | 10.6 | 1.43 | 1.78 | 0.0 | 0.0 | unavailable |
| blob-32 | encode | 15.2 | 25.6 | 18.5 | 1.69 | 1.21 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | decode | 37.5 | 30.7 | 171.4 | 0.82 | 4.57 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-decode | 22074.3 | 28807.5 | 31410.7 | 1.31 | 1.42 | 2.0 | 2.0 | unavailable |
| blob-32 | owned-encode | 9.7 | 12.4 | 10.9 | 1.28 | 1.13 | 0.0 | 0.0 | unavailable |
| natural-0 | decode | 5.6 | 5.1 | 9.3 | 0.91 | 1.65 | 0.0 | 0.0 | unavailable |
| natural-16384 | encode | 6.6 | 8.7 | 11.5 | 1.32 | 1.73 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-decode | 78.5 | 135.0 | 197.7 | 1.72 | 2.52 | 2.0 | 2.0 | unavailable |
| digest-work_result_0 | owned-decode | 93.1 | 126.5 | 682.7 | 1.36 | 7.33 | 2.0 | 2.0 | unavailable |
| natural-18446744073709551615 | decode | 12.8 | 11.6 | 15.3 | 0.91 | 1.19 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | owned-encode | 7.6 | 12.4 | 18.3 | 1.64 | 2.42 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-encode | 20.1 | 22.1 | 26.0 | 1.10 | 1.30 | 0.0 | 0.0 | unavailable |
| blob-0 | decode | 11.2 | 18.9 | 32.8 | 1.69 | 2.92 | 0.0 | 0.0 | unavailable |
| blob-32 | decode | 11.1 | 18.8 | 32.7 | 1.70 | 2.96 | 0.0 | 0.0 | unavailable |
| fixed-4 | decode | 5.3 | 4.7 | 9.5 | 0.87 | 1.77 | 0.0 | 0.0 | unavailable |
| sequence-32 | decode | 132.7 | 45.8 | 163.0 | 0.35 | 1.23 | 0.0 | 0.0 | unavailable |
| digest-1024 | decode | 64.2 | 57.3 | 219.3 | 0.89 | 3.42 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-encode | 916.9 | 1047.4 | 847.2 | 1.14 | 0.92 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-encode | 19.5 | 21.2 | 22.2 | 1.09 | 1.14 | 0.0 | 0.0 | unavailable |
| blake2b-1024 | hash | 1062.5 | 1038.6 | 1084.6 | 0.98 | 1.02 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-decode | 55.1 | 104.6 | 175.2 | 1.90 | 3.18 | 2.0 | 2.0 | unavailable |
| fixed-4 | encode | 12.2 | 6.6 | 15.8 | 0.55 | 1.30 | 0.0 | 0.0 | unavailable |
| natural-16384 | decode | 7.8 | 10.1 | 11.4 | 1.29 | 1.46 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | decode | 12.8 | 11.6 | 15.5 | 0.91 | 1.21 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | encode | 11.7 | 5.7 | 16.1 | 0.49 | 1.38 | 0.0 | 0.0 | unavailable |
| sequence-16384 | decode | 57208.0 | 7106.2 | 68073.3 | 0.12 | 1.19 | 0.0 | 0.0 | unavailable |
| natural-0 | encode | 5.8 | 8.7 | 10.9 | 1.51 | 1.89 | 0.0 | 0.0 | unavailable |
| blob-1048576 | decode | 13.6 | 20.9 | 35.0 | 1.54 | 2.58 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-decode | 132.1 | 176.0 | 729.7 | 1.33 | 5.52 | 2.0 | 2.0 | unavailable |
| digest-1048576 | encode | 17788.3 | 15374.6 | 22351.2 | 0.86 | 1.26 | 0.0 | 0.0 | unavailable |
| natural-127 | encode | 5.8 | 7.1 | 10.9 | 1.23 | 1.89 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-decode | 21087.3 | 29296.2 | 31642.1 | 1.39 | 1.50 | 2.0 | 2.0 | unavailable |
| digest-65536 | decode | 65.7 | 57.8 | 223.9 | 0.88 | 3.41 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | owned-encode | 7.6 | 10.4 | 17.4 | 1.37 | 2.29 | 0.0 | 0.0 | unavailable |
| fixed-8 | encode | 14.5 | 7.6 | 17.1 | 0.53 | 1.17 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-encode | 795.5 | 719.1 | 879.8 | 0.90 | 1.11 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | encode | 65.1 | 52.5 | 240.1 | 0.81 | 3.69 | 0.0 | 0.0 | unavailable |
| blob-1024 | decode | 12.6 | 20.3 | 34.0 | 1.60 | 2.69 | 0.0 | 0.0 | unavailable |
| blob-1048576 | encode | 14725.7 | 16279.7 | 23898.5 | 1.11 | 1.62 | 0.0 | 0.0 | unavailable |
| natural-128 | decode | 6.9 | 10.3 | 10.2 | 1.48 | 1.46 | 0.0 | 0.0 | unavailable |
| sequence-1024 | decode | 3586.5 | 475.3 | 4244.0 | 0.13 | 1.18 | 0.0 | 0.0 | unavailable |

Time ratios above one mean Nim took less time in this run; no significance is implied.
Borrowed decoding validates framing/fields without copying opaque payloads.
Owned decoding includes metadata selection and final release; prepared owned encoding excludes capture.
JSON retains samples, latency percentiles, RSS, allocation observations and source/input hashes.
Mojo exposes public process malloc live bytes here; allocation call/free counts are unavailable.
These baseline measurements imply no optimization ceiling or language winner.
