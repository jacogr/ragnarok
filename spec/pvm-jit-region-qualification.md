# Retained native region qualification

Candidate `e987b44772a3e0d2886033dc614595a7c50b97d5` versus exact master
`5e873ba53fa36320ed27701e5a64a9ffdbb85d7d`, [run 40808153188](https://github.com/jacogr/ragnarok/actions/runs/40808153188).
Pinned October 28 Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` on both sides.
Each architecture is a separate same-runner cohort. Never pool CPU models or pair rows across runs.

Independent audits per architecture pass 70 measured processes/910 complete checked calls/115 positive/refusal controls/16 private fresh builds/eight equal-image pairs, all source/compiler/input/image hashes, CPU/gas/register/page/permission/source snapshots and ordered host events. Native x86 has 15 gates, ARM 9, plus two policy controls each. No hardware counters were collected.

Tables use CPU milliseconds forward / reverse, warm medians samples 3..12. Public calls include fresh invocation memory and immutable publication. Reference is PolkaVM interpreted call-only. Owner construction, cold calls, retained-core reset/publication and reference restoration/teardown are reported separately. Returned observation lifetimes and module construction are distinct contracts; do not present these lifecycle totals as an identical ownership API.

The larger x86 three-block models and x86 shift folding were deferred after paired regressions and restored out. Final x86 runtime above the accepted lower parent is byte-identical to that parent. Retained runtime changes are bounded x86 one/two-block execution, ARM scalar price matching, ARM-only shift folding and guarded ARM loads across widths. Individual experiments and tradeoffs remain in their owning contracts; this table measures the complete retained stack against master, not each isolated change.

## Linux x86-64: AMD EPYC 9V74 80-Core Processor

| Workload | Master JIT | Retained JIT | Our checked interpreter | Retained core JIT | PolkaVM interpreted call | Retained/reference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 3.173/3.200 | 2.635/2.651 | 3.129/3.402 | 2.529/2.512 | 4.946/4.980 | 0.533/0.532 |
| Minimal100k | 5.094/5.028 | 5.008/5.002 | 5.027/4.997 | 5.003/5.051 | 6.209/6.211 | 0.806/0.805 |
| Memory fill100k | 3.760/3.762 | 3.671/3.614 | 3.863/3.825 | 2.974/3.045 | 3.912/3.900 | 0.938/0.927 |
| Pinky | 91.428/80.082 | 78.406/79.661 | 91.328/90.666 | 80.306/79.280 | 103.433/104.478 | 0.758/0.762 |
| Sieve10m | 320.899/294.866 | 264.939/262.581 | 343.189/326.790 | 264.897/265.667 | 395.103/367.632 | 0.671/0.714 |
| DOOM initialization | 415.915/416.890 | 419.540/416.997 | 418.098/417.678 | 405.152/403.301 | 674.344/672.705 | 0.622/0.620 |
| DOOM gameplay | 50.325/46.899 | 44.433/45.285 | 46.454/46.966 | 39.917/38.969 | 44.998/46.959 | 0.987/0.964 |

| Workload | Master owner | Retained owner | Master cold | Retained cold | Reference cold call |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 3.219/3.193 | 3.082/3.072 | 11.074/11.235 | 10.830/10.802 | 5.205/5.440 |
| Minimal100k | 0.017/0.016 | 0.016/0.016 | 5.161/5.159 | 5.179/6.549 | 6.201/6.208 |
| Memory fill100k | 0.055/0.067 | 0.055/0.055 | 10.904/10.707 | 9.008/10.296 | 4.001/3.981 |
| Pinky | 0.740/0.750 | 0.731/0.677 | 86.887/84.296 | 83.608/84.858 | 104.977/103.524 |
| Sieve10m | 3.476/3.209 | 3.175/3.054 | 326.572/319.025 | 270.096/267.139 | 394.616/384.949 |
| DOOM initialization | 8.296/11.028 | 11.043/8.369 | 454.271/462.416 | 466.271/458.963 | 672.701/659.846 |
| DOOM gameplay | 11.270/11.114 | 8.334/8.386 | 82.844/80.529 | 71.498/70.101 | 47.758/47.736 |

| Workload | Core reset | Core execution/hosts | Core publication | Core total lifecycle |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 0.036/0.034 | 2.529/2.512 | 0.009/0.008 | 2.577/2.556 |
| Minimal100k | 0.003/0.003 | 5.003/5.051 | 0.003/0.003 | 5.013/5.058 |
| Memory fill100k | 0.148/0.151 | 2.974/3.045 | 0.036/0.037 | 3.157/3.236 |
| Pinky | 0.022/0.022 | 80.306/79.280 | 0.141/0.140 | 80.476/79.451 |
| Sieve10m | 0.040/0.036 | 264.897/265.667 | 0.288/0.287 | 265.240/265.988 |
| DOOM initialization | 5.475/5.390 | 405.152/403.301 | 0.011/0.011 | 410.452/408.531 |
| DOOM gameplay | 4.428/4.472 | 39.917/38.969 | 0.012/0.012 | 44.571/44.211 |

| Reference DOOM phase | Restoration | Call | Teardown | Total invocation lifecycle |
| --- | ---: | ---: | ---: | ---: |
| init | 7.639/8.063 | 674.344/672.705 | 1.182/1.413 | 683.203/682.121 |
| tick | 7.502/8.034 | 44.998/46.959 | 1.024/1.298 | 54.087/56.486 |

Native counts below aggregate the thirteen public calls. Core source-attempt/node observations are per final reused call; they are software counters, not hardware instruction counts. No eviction policy is changed.

| Workload | Core attempts/nodes | Public fragments | Public logical native operations | Public native calls | Published code bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 1,166,742/13,938 | 184 | 9,156,925 | 1,962,277 | 21,663 |
| Minimal100k | 2,000,035/68 | 0 | 0 | 0 | 0 |
| Memory fill100k | 1,200,349/487 | 31 | 3,900,859 | 1,300,208 | 2,212 |
| Pinky | 32,055,270/7,852 | 335 | 156,172,295 | 28,051,881 | 37,060 |
| Sieve10m | 123,322,753/13,793 | 184 | 912,289,194 | 195,560,110 | 21,663 |
| DOOM initialization | 203,298,231/36,204 | 1,024 | 62,653,474 | 13,957,895 | 94,821 |
| DOOM gameplay | 15,523,334/10,029 | 462 | 21,853,912 | 5,674,903 | 41,648 |

Report SHA256 (applications, native):

- `9c6c1a71d1de3dbd734506f7bbfa3994653dac01d18449783706411331e043c1`
- `b46e8e291b69531026a46732d9b2083a1207de159fba4e64ec3391c488cbe52c`

## Linux ARM64: aarch64

| Workload | Master JIT | Retained JIT | Our checked interpreter | Retained core JIT | PolkaVM interpreted call | Retained/reference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 2.990/2.995 | 2.944/2.944 | 3.516/3.511 | 2.782/2.776 | 6.034/6.101 | 0.488/0.483 |
| Minimal100k | 5.901/5.898 | 5.487/5.448 | 6.182/6.234 | 5.509/5.506 | 5.544/5.540 | 0.990/0.984 |
| Memory fill100k | 4.399/4.429 | 4.395/4.391 | 4.398/4.398 | 3.593/3.595 | 3.759/3.735 | 1.169/1.176 |
| Pinky | 86.623/86.321 | 85.369/85.076 | 95.523/95.386 | 84.838/84.913 | 87.503/87.570 | 0.976/0.972 |
| Sieve10m | 292.466/293.917 | 281.896/281.837 | 340.145/348.268 | 287.224/286.698 | 336.692/333.475 | 0.837/0.845 |
| DOOM initialization | 318.509/316.077 | 321.912/323.440 | 528.838/526.451 | 326.756/329.373 | 623.781/627.280 | 0.516/0.516 |
| DOOM gameplay | 45.963/45.952 | 40.892/40.368 | 48.988/48.839 | 36.079/35.992 | 39.998/40.000 | 1.022/1.009 |

| Workload | Master owner | Retained owner | Master cold | Retained cold | Reference cold call |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 2.749/2.949 | 2.980/2.843 | 10.378/10.688 | 10.647/10.514 | 6.134/6.207 |
| Minimal100k | 0.040/0.015 | 0.018/0.018 | 6.058/6.106 | 5.670/5.644 | 5.589/5.600 |
| Memory fill100k | 0.054/0.054 | 0.054/0.054 | 8.845/8.680 | 8.403/8.039 | 3.804/3.865 |
| Pinky | 0.711/0.740 | 0.699/0.715 | 90.901/90.766 | 89.934/89.530 | 88.081/87.770 |
| Sieve10m | 2.987/2.954 | 3.020/3.022 | 301.867/303.253 | 290.858/290.083 | 337.151/333.643 |
| DOOM initialization | 8.448/8.417 | 8.419/8.539 | 346.910/340.034 | 348.920/348.743 | 629.030/625.647 |
| DOOM gameplay | 8.460/8.482 | 8.505/8.457 | 63.744/63.678 | 58.954/58.280 | 40.479/40.155 |

| Workload | Core reset | Core execution/hosts | Core publication | Core total lifecycle |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 0.051/0.053 | 2.782/2.776 | 0.014/0.014 | 2.847/2.845 |
| Minimal100k | 0.002/0.002 | 5.509/5.506 | 0.002/0.002 | 5.513/5.512 |
| Memory fill100k | 0.184/0.191 | 3.593/3.595 | 0.047/0.050 | 3.822/3.837 |
| Pinky | 0.028/0.031 | 84.838/84.913 | 0.105/0.145 | 84.991/85.085 |
| Sieve10m | 0.055/0.054 | 287.224/286.698 | 0.260/0.286 | 287.538/287.039 |
| DOOM initialization | 6.435/6.518 | 326.756/329.373 | 0.025/0.029 | 333.065/336.005 |
| DOOM gameplay | 5.706/5.378 | 36.079/35.992 | 0.027/0.032 | 41.780/41.439 |

| Reference DOOM phase | Restoration | Call | Teardown | Total invocation lifecycle |
| --- | ---: | ---: | ---: | ---: |
| init | 2.669/2.573 | 623.781/627.280 | 0.325/0.295 | 626.673/630.084 |
| tick | 2.268/2.442 | 39.998/40.000 | 0.100/0.165 | 42.368/42.602 |

Native counts below aggregate the thirteen public calls. Core source-attempt/node observations are per final reused call; they are software counters, not hardware instruction counts. No eviction policy is changed.

| Workload | Core attempts/nodes | Public fragments | Public logical native operations | Public native calls | Published code bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 1,166,742/13,938 | 799 | 12,574,098 | 2,722,478 | 368,828 |
| Minimal100k | 2,000,035/68 | 5 | 9,100,155 | 1,300,039 | 1,300 |
| Memory fill100k | 1,200,349/487 | 55 | 9,101,517 | 3,900,377 | 6,048 |
| Pinky | 32,055,270/7,852 | 666 | 213,860,481 | 38,430,574 | 160,816 |
| Sieve10m | 123,322,753/13,793 | 828 | 1,292,546,194 | 282,056,663 | 374,776 |
| DOOM initialization | 203,298,231/36,204 | 1,024 | 2,279,324,677 | 16,389,373 | 159,840 |
| DOOM gameplay | 15,523,334/10,029 | 918 | 122,792,155 | 26,044,044 | 173,996 |

Report SHA256 (applications, native):

- `11939e73298369a3167db384bb18aba1da0f07872e985792715e5f07a7b7e429`
- `f6bc00048aea836516ea057cd0ac05085a149fa2b76bd22fa5417285c4893577`

## Retention verdict and remaining limits

Keep the retained scope and its checked fallback paths. The final native qualifiers and application
comparisons pass on both Linux architectures at the measured head. All seven public workloads run
in both process orders. Across both architectures this is 140 measured processes, 1,820 complete
checked calls, 230 positive/refusal controls and 32 fresh builds with 16 equal-image pairs. This
selected performance workflow passed; it is not a claim that every repository CI group was run.

Against the exact master above, x86 short sieve improves about 17% in both orders and long sieve
about 11–17%. Gameplay improves about 3–12%, with visible order variation; Pinky's master samples
also vary substantially by process order. Initialization is essentially unchanged. Minimal has zero
native fragments: it remains a useful guard against changes outside the intended native workload.

ARM gameplay improves about 11–12%, minimal about 7–8%, and long sieve about 4%. Pinky improves
about 1.4%. Memory fill is unchanged. ARM initialization is about 1–2% slower in this final cohort,
so the retained stack is not a universal speedup. The isolated ARM load-width trial was neutral on
initialization and materially improved gameplay; the smaller ARM pair trial and its long-sieve
tradeoff are documented separately. Do not attribute aggregate timing differences to one mechanism
or infer hardware causes from code placement or simulated counters.

The public API is the headline. In this cohort ARM public gameplay is still 1–2% slower than the
reference call alone, while x86 public gameplay is near parity or slightly faster. Reference
restoration and teardown add separate measured costs as shown above. Our immutable returned
snapshots, retained core and reference instance lifetimes differ; choose the comparison scope
explicitly instead of substituting a faster core number for a public invocation.

Publication after the measured head may change documentation only. Preserve this exact measured
head and the report hashes above as provenance. Source, native witnesses, helpers, compiler pins,
inputs and build flags must remain identical before reusing this receipt. Review is requested from
review #1; merge decisions remain with the maintainer and merge #1.

Next bounded work, after review, is guarded native reads on x86-64: minimal currently has no native
coverage, and ARM's width expansion demonstrates a measured useful path. Larger x86 region
selection remains an investigation, not a retained optimization: its 40–44% initialization benefit
came with reproducible gameplay regressions. x86 pair folding likewise remains deferred after
minimal regressions. Same-source, byte-identical image controls did not reproduce the large penalty;
no CPU-level explanation has been established. No new experiment is started under this receipt.

Related contracts: [x86 bounded regions](pvm-x86-three-blocks.md),
[ARM scalar matching](pvm-arm-scalar-charge.md),
[ARM shift pairs](pvm-native-shift-pairs.md), and
[ARM guarded loads](pvm-arm-load-widths.md).
