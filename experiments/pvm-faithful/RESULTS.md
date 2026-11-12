<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Fresh interpreter comparison

The measurements do not support replacing the current interpreter wholesale. The fresh control
improves some cold calls, while the saved master is faster on most reused workloads. Cold module
admission is a more focused next investigation; these timings alone do not identify its root cause.

Native evidence: [CI run 43233000249](https://github.com/jacogr/ragnarok/actions/runs/43233000249),
exact tested revision `5721cb657a9db7784b50da552b2fe8853fd53df9`.
Both jobs passed all 22 workloads, both interpreter/JIT-alias roles, source-bound differential
checks, 90 refusal controls, actual SIMD and Rust node-layout checks, reference/reference controls
and both process orders. Production and reference implementation files were unchanged.

- [ARM64 artifact](https://github.com/jacogr/ragnarok/actions/runs/43233000249/artifacts/13949919903),
  ZIP SHA256 `3137de4a374086aed3c7611cb19499695ef1c197ae7b3a89ff7d0e02edb39348`.
- [x86 artifact](https://github.com/jacogr/ragnarok/actions/runs/43233000249/artifacts/13952510479),
  ZIP SHA256 `1442bcf9ff9e7bf648d83a97b7b0bc5fbf0cabb8d6d710cb07cc33b3dbee2d7a`.

The x86 reference/reference controls vary by roughly 11% at the extremes. Small apparent
improvements should not drive a replacement decision. No production replacement was performed.

Each number is implementation / interpreted PolkaVM. Lower is faster. Ranges show the two process orders, not confidence intervals.
Master uses saved CI run 43197869445; it was not rerun. Fresh results use a standalone mutable function-pointer interpreter. JIT explicitly aliases it.

Cold = sample 0, including admission and restoration. Reused = median of samples 3–12. Complete raw CPU/wall samples and refusal logs remain in the native artifacts.

## arm64 identity

Fresh source: `5721cb657a9db7784b50da552b2fe8853fd53df9`.
Master CPU details: `{"CPU architecture": "8", "CPU implementer": "0x41", "CPU part": "0xd49", "CPU revision": "0", "CPU variant": "0x0"}`.
Fresh CPU details: `{"CPU architecture": "8", "CPU implementer": "0x41", "CPU part": "0xd49", "CPU revision": "0", "CPU variant": "0x0"}`.
Same CPU-model details.

## x86_64 identity

Fresh source: `5721cb657a9db7784b50da552b2fe8853fd53df9`.
Master CPU details: `{"cpu family": "25", "model": "17", "model name": "AMD EPYC 9V74 80-Core Processor", "stepping": "1", "vendor_id": "AuthenticAMD"}`.
Fresh CPU details: `{"cpu family": "25", "model": "17", "model name": "AMD EPYC 9V74 80-Core Processor", "stepping": "1", "vendor_id": "AuthenticAMD"}`.
Same CPU-model details.

## Reused cpu_ns

| Workload | Master ARM64 | Fresh ARM64 | Master x86 | Fresh x86 |
| --- | ---: | ---: | ---: | ---: |
| arithmetic-10000 | 0.781–0.791x | 1.139–1.139x | 0.668–0.668x | 1.203–1.311x |
| memory-aligned-1000 | 0.850–0.859x | 1.636–1.642x | 0.725–0.735x | 1.567–1.568x |
| memory-crossing-1000 | 0.374–0.377x | 1.146–1.158x | 0.264–0.264x | 0.904–0.907x |
| hosts-aligned-1000 | 0.922–0.927x | 1.084–1.088x | 0.931–0.934x | 0.880–0.887x |
| hosts-crossing-1000 | 0.662–0.667x | 0.970–1.020x | 0.646–0.647x | 0.874–0.879x |
| arithmetic-1 | 1.166–1.200x | 1.026–1.026x | 1.029–1.068x | 0.991–1.012x |
| arithmetic-16 | 1.131–1.132x | 1.071–1.071x | 0.996–1.015x | 1.000–1.028x |
| bits-mixed-1000 | 0.961–0.962x | 1.614–1.663x | 0.735–0.741x | 1.629–1.672x |
| sparse-aligned-1000 | 0.339–0.351x | 1.368–1.462x | 0.319–0.322x | 1.317–1.332x |
| sparse-crossing-1000 | 0.221–0.222x | 1.052–1.111x | 0.177–0.178x | 0.893–0.903x |
| blocks-alternating-1000 | 0.832–0.836x | 1.063–1.066x | 0.689–0.750x | 2.010–2.257x |
| sieve-1000 | 0.940–0.970x | 1.139–1.161x | 0.798–0.822x | 1.300–1.315x |
| sieve-10000 | 0.958–0.966x | 1.213–1.219x | 0.774–0.776x | 1.302–1.333x |
| sieve-100000 | 0.966–0.971x | 1.232–1.249x | 0.687–0.739x | 1.444–1.456x |
| sieve-10000000 | 0.986–0.987x | 1.269–1.285x | 0.684–0.692x | 1.337–1.363x |
| minimal-1000 | 1.066–1.151x | 1.657–1.658x | 0.719–0.720x | 1.483–1.492x |
| minimal-100000 | 1.051–1.054x | 1.667–1.668x | 0.652–0.699x | 1.478–1.493x |
| memset-1000 | 1.096–1.124x | 1.146–1.156x | 0.857–0.971x | 1.228–1.315x |
| memset-100000 | 1.023–1.026x | 1.209–1.216x | 0.687–0.747x | 1.182–1.269x |
| pinky-1 | 1.019–1.019x | 1.482–1.490x | 0.779–0.788x | 1.415–1.437x |
| doom-init | 0.505–0.507x | 1.223–1.225x | 0.419–0.422x | 1.156–1.176x |
| doom-tick | 0.577–0.580x | 1.455–1.459x | 0.487–0.509x | 1.391–1.447x |

## Reused wall_ns

| Workload | Master ARM64 | Fresh ARM64 | Master x86 | Fresh x86 |
| --- | ---: | ---: | ---: | ---: |
| arithmetic-10000 | 0.780–0.791x | 1.140–1.140x | 0.665–0.665x | 1.206–1.314x |
| memory-aligned-1000 | 0.847–0.855x | 1.655–1.656x | 0.716–0.724x | 1.601–1.603x |
| memory-crossing-1000 | 0.368–0.371x | 1.148–1.161x | 0.252–0.252x | 0.905–0.907x |
| hosts-aligned-1000 | 0.922–0.927x | 1.085–1.089x | 0.931–0.933x | 0.880–0.886x |
| hosts-crossing-1000 | 0.661–0.665x | 0.971–1.020x | 0.644–0.645x | 0.874–0.879x |
| arithmetic-1 | 1.556–1.673x | 1.148–1.192x | 1.319–1.494x | 1.119–1.179x |
| arithmetic-16 | 1.326–1.357x | 1.163–1.190x | 1.026–1.152x | 1.116–1.168x |
| bits-mixed-1000 | 0.961–0.963x | 1.628–1.677x | 0.730–0.737x | 1.655–1.700x |
| sparse-aligned-1000 | 0.333–0.346x | 1.377–1.460x | 0.301–0.304x | 1.326–1.340x |
| sparse-crossing-1000 | 0.214–0.216x | 1.055–1.108x | 0.166–0.167x | 0.893–0.901x |
| blocks-alternating-1000 | 0.827–0.831x | 1.068–1.070x | 0.678–0.742x | 2.077–2.348x |
| sieve-1000 | 0.977–0.980x | 1.155–1.171x | 0.791–0.818x | 1.307–1.320x |
| sieve-10000 | 0.959–0.969x | 1.217–1.224x | 0.772–0.775x | 1.303–1.333x |
| sieve-100000 | 0.967–0.971x | 1.232–1.250x | 0.687–0.739x | 1.444–1.456x |
| sieve-10000000 | 0.986–0.987x | 1.269–1.285x | 0.684–0.692x | 1.337–1.363x |
| minimal-1000 | 1.067–1.152x | 1.664–1.664x | 0.716–0.717x | 1.491–1.499x |
| minimal-100000 | 1.051–1.054x | 1.667–1.668x | 0.652–0.699x | 1.478–1.494x |
| memset-1000 | 1.106–1.133x | 1.162–1.166x | 0.853–0.972x | 1.230–1.321x |
| memset-100000 | 1.023–1.026x | 1.210–1.216x | 0.687–0.747x | 1.182–1.269x |
| pinky-1 | 1.019–1.019x | 1.482–1.491x | 0.779–0.789x | 1.415–1.437x |
| doom-init | 0.505–0.507x | 1.223–1.225x | 0.419–0.422x | 1.156–1.176x |
| doom-tick | 0.577–0.580x | 1.456–1.460x | 0.487–0.509x | 1.391–1.448x |

## Cold cpu_ns

| Workload | Master ARM64 | Fresh ARM64 | Master x86 | Fresh x86 |
| --- | ---: | ---: | ---: | ---: |
| arithmetic-10000 | 0.763–0.764x | 1.039–1.095x | 0.582–0.632x | 0.802–0.989x |
| memory-aligned-1000 | 1.257–1.308x | 1.323–1.324x | 1.155–1.301x | 1.223–1.280x |
| memory-crossing-1000 | 0.429–0.533x | 1.094–1.103x | 0.264–0.322x | 0.861–0.915x |
| hosts-aligned-1000 | 0.852–0.972x | 1.053–1.067x | 0.723–0.988x | 0.835–0.874x |
| hosts-crossing-1000 | 0.657–0.682x | 0.961–0.992x | 0.661–0.686x | 0.742–1.015x |
| arithmetic-1 | 0.728–0.856x | 0.562–0.581x | 0.715–0.791x | 0.414–0.444x |
| arithmetic-16 | 0.812–0.927x | 0.646–0.665x | 0.537–0.596x | 0.395–0.421x |
| bits-mixed-1000 | 0.831–0.842x | 1.308–1.320x | 0.700–0.737x | 1.383–1.418x |
| sparse-aligned-1000 | 2.110–2.406x | 1.136–1.718x | 1.720–1.867x | 0.993–1.018x |
| sparse-crossing-1000 | 1.939–1.947x | 1.051–1.115x | 1.492–1.499x | 0.904–1.055x |
| blocks-alternating-1000 | 1.039–1.189x | 0.720–0.850x | 0.746–0.803x | 0.971–1.428x |
| sieve-1000 | 2.589–2.595x | 1.347–1.370x | 2.263–2.605x | 1.120–1.132x |
| sieve-10000 | 1.412–1.427x | 1.046–1.070x | 1.813–1.958x | 1.134–1.252x |
| sieve-100000 | 1.170–1.177x | 1.085–1.131x | 1.206–1.255x | 1.339–1.497x |
| sieve-10000000 | 0.998–0.999x | 1.270–1.280x | 0.699–0.704x | 1.281–1.343x |
| minimal-1000 | 1.248–1.344x | 0.987–1.149x | 1.244–1.250x | 0.851–0.997x |
| minimal-100000 | 1.065–1.073x | 1.687–1.695x | 0.720–0.722x | 1.431–1.472x |
| memset-1000 | 1.171–1.205x | 1.190–1.312x | 1.252–1.404x | 0.960–0.962x |
| memset-100000 | 1.059–1.061x | 1.215–1.226x | 0.717–0.722x | 1.091–1.167x |
| pinky-1 | 1.023–1.023x | 1.471–1.474x | 0.736–0.769x | 1.393–1.406x |
| doom-init | 0.539–0.541x | 1.220–1.228x | 0.453–0.455x | 1.111–1.198x |
| doom-tick | 1.021–1.029x | 1.438–1.443x | 0.869–0.970x | 1.312–1.365x |

## Cold wall_ns

| Workload | Master ARM64 | Fresh ARM64 | Master x86 | Fresh x86 |
| --- | ---: | ---: | ---: | ---: |
| arithmetic-10000 | 0.764–0.767x | 1.011–1.068x | 0.580–0.631x | 0.778–0.957x |
| memory-aligned-1000 | 1.259–1.310x | 1.328–1.330x | 1.163–1.307x | 1.230–1.232x |
| memory-crossing-1000 | 0.424–0.529x | 1.094–1.103x | 0.255–0.312x | 0.859–0.913x |
| hosts-aligned-1000 | 0.853–0.971x | 1.053–1.063x | 0.722–0.989x | 0.832–0.871x |
| hosts-crossing-1000 | 0.657–0.681x | 0.961–0.992x | 0.659–0.682x | 0.740–1.016x |
| arithmetic-1 | 0.698–0.831x | 0.514–0.540x | 0.672–0.760x | 0.338–0.368x |
| arithmetic-16 | 0.788–0.914x | 0.605–0.626x | 0.481–0.542x | 0.317–0.340x |
| bits-mixed-1000 | 0.828–0.843x | 1.311–1.322x | 0.693–0.731x | 1.393–1.428x |
| sparse-aligned-1000 | 2.115–2.427x | 1.135–1.726x | 1.723–1.870x | 0.994–1.019x |
| sparse-crossing-1000 | 1.944–1.954x | 1.052–1.097x | 1.494–1.501x | 0.902–1.055x |
| blocks-alternating-1000 | 1.009–1.163x | 0.715–0.851x | 0.723–0.777x | 0.944–1.438x |
| sieve-1000 | 2.591–2.597x | 1.340–1.364x | 2.266–2.608x | 1.116–1.128x |
| sieve-10000 | 1.412–1.428x | 1.045–1.068x | 1.814–1.959x | 1.132–1.249x |
| sieve-100000 | 1.170–1.177x | 1.084–1.130x | 1.199–1.255x | 1.339–1.497x |
| sieve-10000000 | 0.998–0.999x | 1.270–1.281x | 0.699–0.704x | 1.281–1.343x |
| minimal-1000 | 1.252–1.358x | 0.964–1.124x | 1.249–1.253x | 0.828–0.975x |
| minimal-100000 | 1.065–1.073x | 1.686–1.695x | 0.716–0.722x | 1.430–1.473x |
| memset-1000 | 1.173–1.211x | 1.164–1.280x | 1.257–1.410x | 0.930–0.936x |
| memset-100000 | 1.059–1.062x | 1.214–1.224x | 0.717–0.722x | 1.090–1.167x |
| pinky-1 | 1.023–1.023x | 1.472–1.474x | 0.736–0.769x | 1.393–1.405x |
| doom-init | 0.539–0.541x | 1.220–1.228x | 0.453–0.455x | 1.111–1.198x |
| doom-tick | 1.021–1.029x | 1.438–1.443x | 0.869–0.970x | 1.311–1.365x |

## Reference/reference controls

Each control uses two separate reference processes; these numbers are not constructed from duplicated samples.

arm64: reused CPU ratios span 0.988–1.032x; median 1.000x.
x86_64: reused CPU ratios span 0.891–1.119x; median 1.005x.

## Interpretation limits

The control preserves the relevant interpreter architecture, not identical compiler output. ARC versus atomic Arc, configuration wrappers, one extra immutable blob handle, error representation and per-unit AVX2 targeting are disclosed in [PORTING.md](PORTING.md). Cold wrapper differences matter especially for tiny programs.
No production replacement or optimization was made as part of this experiment.
