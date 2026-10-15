# Optimized checked benchmark

Platform: macOS-27.0.1-arm64-arm-64bit-Mach-O
Linux CPU affinity: None; complete: True

Checked optimized builds share inputs and the noinline observation boundary.
Batch throughput and individual-operation latency samples remain separate.

| Case | Operation | Nim median ns/op | Odin median ns/op | Mojo median ns/op | Odin/Nim time | Mojo/Nim time | Nim alloc calls/op | Odin alloc calls/op | Mojo alloc calls/op |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| digest-work_result_1 | encode | 44.7 | 40.4 | 224.4 | 0.90 | 5.02 | 0.0 | 0.0 | unavailable |
| blake2b-32 | hash | 139.3 | 145.0 | 160.2 | 1.04 | 1.15 | 0.0 | 0.0 | unavailable |
| natural-18446744073709551615 | encode | 11.6 | 5.6 | 16.1 | 0.48 | 1.39 | 0.0 | 0.0 | unavailable |
| digest-1024 | encode | 112.8 | 68.2 | 278.1 | 0.60 | 2.47 | 0.0 | 0.0 | unavailable |
| blob-1024 | encode | 24.8 | 34.1 | 30.3 | 1.38 | 1.22 | 0.0 | 0.0 | unavailable |
| blob-0 | encode | 13.0 | 21.4 | 17.1 | 1.65 | 1.32 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-decode | 1434.4 | 2361.5 | 1509.1 | 1.65 | 1.05 | 2.0 | 2.0 | unavailable |
| fixed-0 | encode | 8.2 | 5.0 | 12.5 | 0.61 | 1.53 | 0.0 | 0.0 | unavailable |
| digest-1048576 | decode | 65.6 | 57.9 | 220.7 | 0.88 | 3.37 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-decode | 1558.4 | 2355.8 | 2130.5 | 1.51 | 1.37 | 2.0 | 2.0 | unavailable |
| fixed-0 | decode | 6.2 | 7.9 | 7.5 | 1.28 | 1.21 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-encode | 16843.5 | 16189.2 | 22090.9 | 0.96 | 1.31 | 0.0 | 0.0 | unavailable |
| fixed-8 | decode | 5.7 | 5.3 | 10.7 | 0.93 | 1.90 | 0.0 | 0.0 | unavailable |
| blob-65536 | decode | 13.4 | 20.8 | 34.7 | 1.55 | 2.58 | 0.0 | 0.0 | unavailable |
| sequence-32 | encode | 458.5 | 54.7 | 638.3 | 0.12 | 1.39 | 0.0 | 0.0 | unavailable |
| blob-65536 | encode | 912.6 | 829.8 | 1516.3 | 0.91 | 1.66 | 0.0 | 0.0 | unavailable |
| blob-32 | owned-decode | 59.1 | 105.8 | 177.2 | 1.79 | 3.00 | 2.0 | 2.0 | unavailable |
| digest-work_result_1 | owned-decode | 80.7 | 119.4 | 582.6 | 1.48 | 7.22 | 2.0 | 2.0 | unavailable |
| baseline | control | 3.5 | 2.5 | 6.2 | 0.72 | 1.78 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-encode | 18502.6 | 14906.9 | 22105.7 | 0.81 | 1.19 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-encode | 7.3 | 10.0 | 10.1 | 1.37 | 1.39 | 0.0 | 0.0 | unavailable |
| blake2b-65536 | hash | 65227.5 | 63468.8 | 65195.7 | 0.97 | 1.00 | 0.0 | 0.0 | unavailable |
| sequence-1024 | encode | 13228.6 | 1174.1 | 19644.2 | 0.09 | 1.48 | 0.0 | 0.0 | unavailable |
| blake2b-1048576 | hash | 1041847.2 | 1014986.1 | 1047064.8 | 0.97 | 1.01 | 0.0 | 0.0 | unavailable |
| sequence-16384 | encode | 232321.2 | 17987.9 | 315329.3 | 0.08 | 1.36 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | decode | 46.9 | 37.9 | 205.7 | 0.81 | 4.39 | 0.0 | 0.0 | unavailable |
| digest-65536 | encode | 1037.7 | 789.1 | 1144.8 | 0.76 | 1.10 | 0.0 | 0.0 | unavailable |
| natural-127 | decode | 5.7 | 5.1 | 9.3 | 0.90 | 1.63 | 0.0 | 0.0 | unavailable |
| natural-128 | encode | 6.0 | 7.3 | 10.7 | 1.21 | 1.79 | 0.0 | 0.0 | unavailable |
| blob-32 | encode | 15.3 | 25.7 | 18.6 | 1.68 | 1.22 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | decode | 37.6 | 30.7 | 172.4 | 0.82 | 4.59 | 0.0 | 0.0 | unavailable |
| digest-1048576 | owned-decode | 20709.5 | 28136.8 | 31605.3 | 1.36 | 1.53 | 2.0 | 2.0 | unavailable |
| blob-32 | owned-encode | 9.7 | 12.4 | 11.0 | 1.28 | 1.13 | 0.0 | 0.0 | unavailable |
| natural-0 | decode | 5.7 | 5.1 | 9.3 | 0.90 | 1.63 | 0.0 | 0.0 | unavailable |
| natural-16384 | encode | 6.6 | 8.9 | 11.5 | 1.34 | 1.73 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-decode | 78.7 | 135.3 | 199.8 | 1.72 | 2.54 | 2.0 | 2.0 | unavailable |
| digest-work_result_0 | owned-decode | 93.0 | 125.6 | 684.5 | 1.35 | 7.36 | 2.0 | 2.0 | unavailable |
| natural-18446744073709551615 | decode | 12.9 | 11.6 | 15.5 | 0.90 | 1.20 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | owned-encode | 7.6 | 12.3 | 18.6 | 1.62 | 2.46 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-encode | 20.1 | 22.1 | 26.2 | 1.10 | 1.31 | 0.0 | 0.0 | unavailable |
| blob-0 | decode | 11.1 | 19.0 | 33.0 | 1.71 | 2.98 | 0.0 | 0.0 | unavailable |
| blob-32 | decode | 11.1 | 18.8 | 32.7 | 1.70 | 2.96 | 0.0 | 0.0 | unavailable |
| fixed-4 | decode | 5.4 | 4.7 | 9.5 | 0.88 | 1.76 | 0.0 | 0.0 | unavailable |
| sequence-32 | decode | 133.2 | 45.7 | 164.5 | 0.34 | 1.23 | 0.0 | 0.0 | unavailable |
| digest-1024 | decode | 64.2 | 57.5 | 220.2 | 0.90 | 3.43 | 0.0 | 0.0 | unavailable |
| blob-65536 | owned-encode | 1047.2 | 774.4 | 833.7 | 0.74 | 0.80 | 0.0 | 0.0 | unavailable |
| blob-1024 | owned-encode | 19.1 | 20.9 | 22.0 | 1.09 | 1.15 | 0.0 | 0.0 | unavailable |
| blake2b-1024 | hash | 1028.8 | 1004.8 | 1051.5 | 0.98 | 1.02 | 0.0 | 0.0 | unavailable |
| blob-0 | owned-decode | 54.6 | 103.7 | 177.2 | 1.90 | 3.25 | 2.0 | 2.0 | unavailable |
| fixed-4 | encode | 12.2 | 6.6 | 19.7 | 0.55 | 1.62 | 0.0 | 0.0 | unavailable |
| natural-16384 | decode | 7.9 | 10.2 | 11.4 | 1.29 | 1.44 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | decode | 13.0 | 11.6 | 15.5 | 0.89 | 1.20 | 0.0 | 0.0 | unavailable |
| natural-72057594037927936 | encode | 11.7 | 5.7 | 16.1 | 0.49 | 1.38 | 0.0 | 0.0 | unavailable |
| sequence-16384 | decode | 57306.4 | 7118.6 | 68340.9 | 0.12 | 1.19 | 0.0 | 0.0 | unavailable |
| natural-0 | encode | 5.8 | 7.2 | 11.1 | 1.24 | 1.92 | 0.0 | 0.0 | unavailable |
| blob-1048576 | decode | 13.6 | 20.9 | 34.8 | 1.53 | 2.55 | 0.0 | 0.0 | unavailable |
| digest-1024 | owned-decode | 131.7 | 177.5 | 742.4 | 1.35 | 5.64 | 2.0 | 2.0 | unavailable |
| digest-1048576 | encode | 16305.7 | 15647.9 | 22315.6 | 0.96 | 1.37 | 0.0 | 0.0 | unavailable |
| natural-127 | encode | 5.8 | 7.7 | 11.1 | 1.32 | 1.89 | 0.0 | 0.0 | unavailable |
| blob-1048576 | owned-decode | 23031.0 | 28692.3 | 31584.7 | 1.25 | 1.37 | 2.0 | 2.0 | unavailable |
| digest-65536 | decode | 66.5 | 58.3 | 224.4 | 0.88 | 3.37 | 0.0 | 0.0 | unavailable |
| digest-work_result_1 | owned-encode | 7.6 | 12.6 | 17.4 | 1.66 | 2.29 | 0.0 | 0.0 | unavailable |
| fixed-8 | encode | 14.5 | 7.6 | 20.9 | 0.53 | 1.44 | 0.0 | 0.0 | unavailable |
| digest-65536 | owned-encode | 792.9 | 707.9 | 896.0 | 0.89 | 1.13 | 0.0 | 0.0 | unavailable |
| digest-work_result_0 | encode | 65.0 | 51.8 | 235.9 | 0.80 | 3.63 | 0.0 | 0.0 | unavailable |
| blob-1024 | decode | 12.6 | 20.4 | 33.7 | 1.61 | 2.66 | 0.0 | 0.0 | unavailable |
| blob-1048576 | encode | 16250.6 | 15542.5 | 23898.0 | 0.96 | 1.47 | 0.0 | 0.0 | unavailable |
| natural-128 | decode | 7.0 | 10.3 | 10.2 | 1.48 | 1.47 | 0.0 | 0.0 | unavailable |
| sequence-1024 | decode | 3594.6 | 476.0 | 4295.7 | 0.13 | 1.20 | 0.0 | 0.0 | unavailable |

Time ratios above one mean Nim took less time in this run; no significance is implied.
Borrowed decoding validates framing/fields without copying opaque payloads.
Owned decoding includes metadata selection and final release; prepared owned encoding excludes capture.
JSON retains samples, latency percentiles, RSS, allocation observations and source/input hashes.
Mojo exposes public process malloc live bytes here; allocation call/free counts are unavailable.
These baseline measurements imply no optimization ceiling or language winner.
