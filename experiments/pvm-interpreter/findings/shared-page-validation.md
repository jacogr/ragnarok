# shared-page-validation

Keep: immutable page identity avoids redundant metadata dereferences, improving all six reused initialization calls by 0.65–1.98% (median0.79%) while gameplay and small kernels remain broadly flat.

Checked macOS arm64 CPU durations. Baseline commit `bb7530f67413b98379f2e582febe6381cc6f487d`; candidate overlay
`684ad0ba7072322dbbeffffc61e9377546f722485932dfea325532ed2ce81f6e`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -0.17% | +0.13% | -1.21…+3.30% |
| sieve | -0.08% | +0.54% | -0.55…+0.11% |
| minimal | +0.02% | +0.14% | -0.12…+0.30% |
| memset | -0.04% | +0.25% | -0.26…+0.65% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 739.202 | 733.885 | -0.72% | -0.87% |
| init cold/1 | 763.947 | 713.017 | -6.67% | -6.53% |
| init reused/0 | 718.402 | 713.536 | -0.68% | -0.56% |
| init reused/1 | 718.188 | 713.279 | -0.68% | -0.88% |
| init reused/2 | 721.678 | 716.995 | -0.65% | -0.66% |
| init reused/3 | 719.798 | 705.560 | -1.98% | -2.06% |
| init reused/4 | 720.656 | 710.159 | -1.46% | -1.39% |
| init reused/5 | 717.096 | 710.722 | -0.89% | -0.87% |
| tick cold/0 | 31.414 | 31.557 | +0.46% | +0.39% |
| tick cold/1 | 31.250 | 30.953 | -0.95% | -0.27% |
| tick reused/0 | 28.867 | 28.582 | -0.99% | +0.19% |
| tick reused/1 | 28.785 | 28.791 | +0.02% | -0.07% |
| tick reused/2 | 28.733 | 28.927 | +0.68% | +0.60% |
| tick reused/3 | 29.003 | 28.977 | -0.09% | -0.64% |
| tick reused/4 | 28.977 | 28.991 | +0.05% | +0.30% |
| tick reused/5 | 28.931 | 29.035 | +0.36% | +0.23% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 85.489 / 85.046 | 85.730 / 85.415 | 116.894 / 116.540 | 92.025 / 91.032 | 0.932x / 0.938x |
| sieve | 3.203 / 3.202 | 3.211 / 3.199 | 3.309 / 3.302 | 5.960 / 5.966 | 0.539x / 0.536x |
| minimal | 5.210 / 5.074 | 5.098 / 5.101 | 7.203 / 7.212 | 5.854 / 5.850 | 0.871x / 0.872x |
| memset | 3.723 / 3.653 | 3.832 / 3.612 | 3.402 / 3.390 | 3.810 / 3.805 | 1.006x / 0.949x |
| init | 718.402 / 718.188 | 713.536 / 713.279 | 1328.632 / 1314.735 | 662.056 / 657.428 | 1.078x / 1.085x |
| tick | 28.867 / 28.785 | 28.582 / 28.791 | 84.176 / 83.978 | 33.593 / 34.185 | 0.851x / 0.842x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.382 | 18.322 | 12.126 | 622.410 | 54.242 | 33.277 | 0.006 |
| init/0/candidate | 7.387 | 18.157 | 12.694 | 624.880 | 54.672 | 25.904 | 0.007 |
| init/1/candidate | 7.403 | 18.089 | 11.904 | 625.438 | 53.971 | 25.527 | 0.006 |
| init/1/baseline | 7.403 | 18.122 | 12.018 | 621.861 | 54.600 | 33.475 | 0.007 |
| tick/0/baseline | 7.333 | 18.074 | 11.229 | 28.392 | 0.378 | 0.097 | 0.006 |
| tick/0/candidate | 7.306 | 17.989 | 11.565 | 28.096 | 0.377 | 0.096 | 0.006 |
| tick/1/candidate | 7.390 | 18.281 | 11.216 | 28.310 | 0.383 | 0.097 | 0.006 |
| tick/1/baseline | 7.211 | 18.158 | 11.195 | 28.293 | 0.382 | 0.096 | 0.006 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 785.151 | 777.272 | -1.00% |
| init/1 | 804.139 | 753.320 | -6.32% |
| tick/0 | 71.775 | 72.466 | +0.96% |
| tick/1 | 70.728 | 70.769 | +0.06% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.

## Interpretation and ownership evidence

Retain the metadata identity shortcut. All six reused init call pairs improve0.65–1.98%
(median0.79%); measured lifecycle median improves0.87%. Resumption medians fall from
33.28–33.58ms to25.53–25.90ms. This is a modest, consistent host-path improvement, not a broad
kernel speedup. Gameplay call/lifecycle medians are +0.03%/+0.21%. Small kernel medians stay
within0.17%; small lifecycle medians stay within0.55%, with all distributions preserved above.
No mappings, data layout, allocation policy, copy payloads, gas or guest control flow change.

Eight native and eight ASan groups pass, including six new late permission refusals and distinct
owners holding equal bytes. The entire mapping pass still finishes before delta allocation;
unchanged immutable identity supplies the same index/access fact without dereferencing fields.
All200timed processes and4negative controls pass; exact runtime/fixture/image seals remain stable.

A separate checked native diagnostic (clocks discarded) observes1590nonempty host deltas during
initialization: among6,813,150mapped-page comparisons, only2026page owners differ. These are
structural observations, not hardware counters. The same diagnostic counts6,945,985publication
metadata visits versus9253dirty candidates and8293actually changed pages over1621callbacks.
Gameplay has4285metadata visits,336dirty candidates and273changed pages at its sole callback.
See publication-work-probe.json and the archived instrumenter; this motivates the next isolated
working-set experiment without attributing CPU causes from counts alone.
