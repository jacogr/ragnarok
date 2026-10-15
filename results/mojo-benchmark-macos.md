# Optimized checked benchmark

Platform: macOS-27.0.1-arm64-arm-64bit-Mach-O
Linux CPU affinity: None; complete: True

Checked optimized builds share inputs and the noinline observation boundary.
Batch throughput and individual-operation latency samples remain separate.

| Case | Operation | Nim median ns/op | Odin median ns/op | Mojo median ns/op | Odin/Nim time | Mojo/Nim time | Nim alloc calls/op | Odin alloc calls/op | Mojo alloc calls/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| digest-work_result_1 | encode | 56.3 | 40.1 | 226.2 | 0.71 | 4.02 | 0.0 | 0.0 | unavailable |
| blake2b-32 | hash | 139.3 | 145.6 | 161.3 | 1.05 | 1.16 | 0.0 | 0.0 | unavailable |
| natural-18446744073709551615 | encode | 11.6 | 5.6 | 16.2 | 0.49 | 1.40 | 0.0 | 0.0 | unavailable |
| digest-1024 | encode | 1177.5 | 68.4 | 1912.8 | 0.06 | 1.62 | 0.0 | 0.0 | unavailable |
| blob-1024 | encode | 658.5 | 35.0 | 1661.7 | 0.05 | 2.52 | 0.0 | 0.0 | unavailable |
| blob-0 | encode | 13.2 | 21.5 | 17.5 | 1.63 | 1.33 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-decode | 31693.8 | 2351.9 | 106401.3 | 0.07 | 3.36 | 2.0 | 2.0 | unavailable |
| fixed-0 | encode | 5.9 | 5.0 | 12.5 | 0.84 | 2.11 | 0.0 | 0.0 | unavailable |
| digest-1048576 | decode | 68.8 | 58.1 | 221.2 | 0.84 | 3.21 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-decode | 31685.2 | 2333.8 | 106754.1 | 0.07 | 3.37 | 2.0 | 2.0 | unavailable |
| fixed-0 | decode | 5.9 | 7.9 | 8.4 | 1.34 | 1.42 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-encode | 667333.4 | 17208.2 | 1682508.2 | 0.03 | 2.52 | 0.0 | 0.0 | unavailable |
| fixed-8 | decode | 6.3 | 5.3 | 11.6 | 0.85 | 1.85 | 0.0 | 0.0 | unavailable |
| blob-65536 | decode | 13.1 | 20.9 | 33.8 | 1.60 | 2.57 | 0.0 | 0.0 | unavailable |
| sequence-32 | encode | 715.3 | 54.3 | 641.9 | 0.08 | 0.90 | 0.0 | 0.0 | unavailable |
| blob-65536 | encode | 40882.5 | 809.0 | 105277.5 | 0.02 | 2.58 | 0.0 | 0.0 | unavailable |
| blob-32 | owned-decode | 67.0 | 106.3 | 222.3 | 1.58 | 3.32 | 2.0 | 2.0 | unavailable |
| digest-work_result_1 | owned-decode | 117.4 | 119.7 | 706.6 | 1.02 | 6.02 | 2.0 | 2.0 | unavailable |
| baseline | control | 3.5 | 2.5 | 6.2 | 0.72 | 1.79 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-encode | 665950.0 | 16650.0 | 1684691.6 | 0.03 | 2.53 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-encode | 7.5 | 10.0 | 10.0 | 1.33 | 1.33 | 0.0 | 0.0 | unavailable |
| blake2b-65536 | hash | 65590.5 | 63774.7 | 65403.2 | 0.97 | 1.00 | 0.0 | 0.0 | unavailable |
| sequence-1024 | encode | 21633.8 | 1154.9 | 19756.6 | 0.05 | 0.91 | 0.0 | 0.0 | unavailable |
| blake2b-1048576 | hash | 1051592.6 | 1019490.7 | 1052041.7 | 0.97 | 1.00 | 0.0 | 0.0 | unavailable |
| sequence-16384 | encode | 338689.7 | 17933.9 | 315839.1 | 0.05 | 0.93 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | decode | 47.6 | 38.0 | 206.9 | 0.80 | 4.35 | 0.0 | 0.0 | unavailable |
| digest-65536 | encode | 66727.6 | 812.7 | 105300.2 | 0.01 | 1.58 | 0.0 | 0.0 | unavailable |
| natural-127 | decode | 5.7 | 5.1 | 9.4 | 0.89 | 1.64 | 0.0 | 0.0 | unavailable |
| natural-128 | encode | 5.9 | 7.5 | 10.6 | 1.26 | 1.79 | 0.0 | 0.0 | unavailable |
| blob-32 | encode | 32.0 | 25.9 | 63.1 | 0.81 | 1.97 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | decode | 40.7 | 30.8 | 177.1 | 0.76 | 4.35 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-decode | 501233.2 | 28500.0 | 1688175.0 | 0.06 | 3.37 | 2.0 | 2.0 | unavailable |
| blob-32 | owned-encode | 27.8 | 12.5 | 57.6 | 0.45 | 2.07 | 0.0 | 0.0 | unavailable |
| natural-0 | decode | 5.7 | 5.1 | 9.4 | 0.89 | 1.65 | 0.0 | 0.0 | unavailable |
| natural-16384 | encode | 6.6 | 8.9 | 11.5 | 1.35 | 1.76 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-decode | 549.5 | 136.9 | 1846.0 | 0.25 | 3.36 | 2.0 | 2.0 | unavailable |
| digest-work_result_0 | owned-decode | 131.8 | 127.5 | 816.2 | 0.97 | 6.19 | 2.0 | 2.0 | unavailable |
| natural-18446744073709551615 | decode | 12.8 | 11.6 | 15.3 | 0.91 | 1.19 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | owned-encode | 69.5 | 12.3 | 142.5 | 0.18 | 2.05 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-encode | 736.5 | 22.1 | 1820.6 | 0.03 | 2.47 | 0.0 | 0.0 | unavailable |
| blob-0 | decode | 10.6 | 19.0 | 32.8 | 1.79 | 3.08 | 0.0 | 0.0 | unavailable |
| blob-32 | decode | 10.9 | 19.2 | 32.8 | 1.76 | 3.02 | 0.0 | 0.0 | unavailable |
| fixed-4 | decode | 5.9 | 4.7 | 10.4 | 0.79 | 1.75 | 0.0 | 0.0 | unavailable |
| sequence-32 | decode | 135.1 | 45.9 | 225.5 | 0.34 | 1.67 | 0.0 | 0.0 | unavailable |
| digest-1024 | decode | 67.7 | 57.5 | 221.2 | 0.85 | 3.27 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-encode | 41967.4 | 785.3 | 105517.2 | 0.02 | 2.51 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-encode | 672.3 | 21.2 | 1659.8 | 0.03 | 2.47 | 0.0 | 0.0 | unavailable |
| blake2b-1024 | hash | 1036.3 | 1012.3 | 1057.1 | 0.98 | 1.02 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-decode | 50.7 | 104.3 | 174.3 | 2.06 | 3.44 | 2.0 | 2.0 | unavailable |
| fixed-4 | encode | 8.8 | 6.6 | 19.2 | 0.75 | 2.19 | 0.0 | 0.0 | unavailable |
| natural-16384 | decode | 7.8 | 10.2 | 11.2 | 1.31 | 1.44 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | decode | 12.8 | 11.7 | 15.3 | 0.91 | 1.19 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | encode | 11.5 | 5.6 | 16.2 | 0.49 | 1.41 | 0.0 | 0.0 | unavailable |
| sequence-16384 | decode | 56551.5 | 7109.1 | 98796.0 | 0.13 | 1.75 | 0.0 | 0.0 | unavailable |
| natural-0 | encode | 5.6 | 7.8 | 10.6 | 1.39 | 1.88 | 0.0 | 0.0 | unavailable |
| blob-1048576 | decode | 13.2 | 21.0 | 33.7 | 1.59 | 2.56 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-decode | 656.5 | 177.3 | 2549.8 | 0.27 | 3.88 | 2.0 | 2.0 | unavailable |
| digest-1048576 | encode | 1063133.2 | 14958.4 | 1682908.2 | 0.01 | 1.58 | 0.0 | 0.0 | unavailable |
| natural-127 | encode | 5.6 | 8.7 | 10.6 | 1.55 | 1.89 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-decode | 497916.6 | 28216.8 | 1687725.0 | 0.06 | 3.39 | 2.0 | 2.0 | unavailable |
| digest-65536 | decode | 68.8 | 58.1 | 221.3 | 0.84 | 3.21 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | owned-encode | 66.9 | 12.1 | 136.1 | 0.18 | 2.04 | 0.0 | 0.0 | unavailable |
| fixed-8 | encode | 10.6 | 7.5 | 20.6 | 0.71 | 1.94 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-encode | 42104.2 | 737.1 | 105236.7 | 0.02 | 2.50 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | encode | 74.0 | 52.0 | 233.8 | 0.70 | 3.16 | 0.0 | 0.0 | unavailable |
| blob-1024 | decode | 12.2 | 20.4 | 32.7 | 1.67 | 2.67 | 0.0 | 0.0 | unavailable |
| blob-1048576 | encode | 656158.4 | 14616.6 | 1682400.0 | 0.02 | 2.56 | 0.0 | 0.0 | unavailable |
| natural-128 | decode | 6.9 | 8.4 | 10.3 | 1.22 | 1.50 | 0.0 | 0.0 | unavailable |
| sequence-1024 | decode | 3554.4 | 475.5 | 6197.3 | 0.13 | 1.74 | 0.0 | 0.0 | unavailable |

Time ratios above one mean Nim took less time in this run; no significance is implied.
Borrowed decoding validates framing/fields without copying opaque payloads.
Owned decoding includes metadata selection and final release; prepared owned encoding excludes capture.
JSON retains samples, latency percentiles, RSS, allocation observations and source/input hashes.
Mojo exposes public process malloc live bytes here; allocation call/free counts are unavailable.
These baseline measurements imply no optimization ceiling or language winner.
