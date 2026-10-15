# Mojo retained-service allocation observation

2026-10-15. This is a shared CI measurement correction, not a native language implementation
increment. Protocol behavior, dependency pins, SDK versions and native binaries are unchanged.

## Failure and evidence

The maintainer supplied the [Linux CI failure](https://github.com/jacogr/ragnarok/actions/runs/38675797856/job/116228983004):
all sixteen waves completed for all three servers; Mojo then failed the idle allocation check.
Its twelve post-warmup observations range from 1,910,688 to 2,001,856 bytes: **91,168 bytes**.
The exact allocating call behind the Linux step has not been identified. That series alone does
not prove either a leak or a benign cache; the corrected Linux workflow still needs execution.

The harness applied a language-allocation ceiling to three different observations:

| Candidate | Actual counter | Retained-engine idle ceiling | After destruction |
| --- | --- | --- | --- |
| Nim | ARC language allocator | 64 KiB range | 64 KiB above startup |
| Odin | Tracked application allocator | 64 KiB range | Exactly zero |
| Mojo | Public process malloc, including SDK, LSQUIC and TLS | 16 MiB range | 64 KiB above startup |

The C helper's [public malloc observation](../interoperability/mojo/os.c) explicitly includes
native libraries. LSQUIC documents that [malo pool pages](../vendor/lsquic/src/liblsquic/lsquic_malo.c)
remain allocated until destruction; its [packet/page freelists](../vendor/lsquic/src/liblsquic/lsquic_mm.c)
also retain storage in the engine. Zero live connections/application slots is not an empty C heap.
Neither source establishes which allocation caused this particular Linux increase.

A pre-change [32-wave macOS reproduction](mojo-service-ci/macos-32-wave-before.json) passed the
original idle check. Its heap stepped from 3,184,848 to 3,226,064 bytes while serving, then returned
to 2,365,472 after destruction versus a 2,340,432 startup baseline (**25,040 bytes retained**).
This directly demonstrates substantial releasable engine-lifetime storage in this workload;
it does not substitute for a Linux allocator trace. A second local run across all three servers
reproduced an over-64-KiB Mojo idle range (**84,992 bytes**) while ending at the same 25,040-byte
shutdown delta. See the [96-wave service matrix](mojo-service-ci/services-32-wave-macos.json).

## Correction and limits

The shared checker now requires the candidate explicitly and reports the actual counter scope,
selected ceiling and whether engines remain alive. Mojo's retained-engine process heap uses the
**existing 16 MiB aggregate RSS growth budget**, independently of the RSS check. This is an explicit
aggregate policy, not a newly inferred cache size or a 64 KiB application-leak guarantee.
Nim/Odin retain their application-counter ceilings. The lifecycle soak destroys endpoints before
sampling and retains the original 64 KiB gate for **all three** candidates.

The persistent-service test previously checked shutdown allocation markers only for Nim/Odin.
It now requires exactly one Mojo cleanup observation and checks its **64 KiB post-destruction**
ceiling, matching the existing mesh/integration/offload shutdown policy. An application leak that
survives engine destruction cannot use the larger live-engine budget to bypass that gate.

RSS, descriptors, raw fixed thread counts, minimum sample counts, warmup extent, admission,
stream retirement, timeouts, rejection, cancellation and healthy exchanges remain checked.
All retained profiles use the scoped policy, including the offload harness's former duplicate.
Mojo still lacks an application-only allocator counter: small leaks hidden inside a live engine
are less precisely detectable than with Nim/Odin counters. Finite tests do not establish leak freedom.

## Reproduce

Use the pinned toolchains and existing native builds from the normal CI build steps:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_quic_soak_harness.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_benchmark_harness.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/ergonomics/test_tools.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_quic_service.py --mojo --skip-build --rounds 32
python3 tools/format.py --check
```

The harness regression suite replays the supplied Linux series, rejects the same series under
Nim/Odin application scopes, checks inclusive ceiling boundaries and over-budget failures,
unknown candidates, minimum coverage, endpoint destruction and missing/duplicate shutdown markers.
The existing Linux workflow already runs these tests and preserves resource artifacts.

## Ergonomics attribution

This incident demonstrates an **infrastructure/measurement scope defect** in shared parity tooling.
The exact Linux allocation's origin remains unknown; it is not attributed to Mojo language/compiler
friction or claimed as a confirmed decoder/networking ownership defect. No native compiler attempt
was needed. This is not an equivalent three-language implementation task or a controlled cohort.
Development time and comparative repair/intervention/regression metrics are N/A; no handoff journal
covered this investigation from its beginning. Historical comparison metrics remain unchanged.

## Local validation

macOS 27.0.1 arm64; Nim 2.2.12 ARC, Odin `dev-2026-10:84bc3fc21`,
Mojo `1.1.0 (8189361e)`, Python 3.14.2, Apple clang 21.0.0. Native sources and binaries
were reused; the service artifact retains binary SHA-256 fingerprints and the source commit.
The Linux CI target remains Ubuntu 24.04 x86-64 with Python 3.12 and the same pinned candidates.

| Check | Observed local result |
| --- | --- |
| Allocation/marker harness regressions | 16 tests passed |
| Existing benchmark evidence harness | 11 tests passed |
| Existing ergonomics tooling integrity | 12 tests passed |
| Persistent service | All 3 servers × 32 waves passed; 130 accepted/retired connections each |
| Service shutdown | Nim +16 bytes; Odin zero; Mojo +25,040 bytes |
| Formatting | `python3 tools/format.py --check`: 126 source files passed |

The application-only idle ranges remained zero for Nim/Odin. The Mojo service's post-warmup
process heap range was 84,992 bytes, RSS range 147,456 bytes, descriptor range zero, with nine
fixed SDK threads. These observed values are separate from the policy ceilings.

The [related profile observations](mojo-service-ci/related-profiles-macos.json) also passed:

| Native profile | Exact extent and pairing |
| --- | --- |
| Destroyed-endpoint soak | Mojo server / Nim client: 16 sessions, warmup 8; strict 64 KiB gate |
| Retained IPv6 mesh | Nim / Mojo: 12 waves, warmup 4 |
| Peer-loss recovery | Mojo keeper / Odin victim: 12 deaths, warmup 4, plus final healthy exchange |
| Admission saturation | Mojo: 12 waves, warmup 4; 16 connections / 64 application slots |
| Codec/crypto integration | Mojo: 12 waves, warmup 4; rotating three-language clients |
| Bandersnatch offload | Mojo: 10 waves, warmup 2; 128 verifications/job, rotating clients, joined shutdown |

These used the existing imported harness functions, sequentially, with the already generated
`build/quic/fixtures` certificates. Reproduce the same focused scope after the normal native builds:

```sh
PYTHONPATH=interoperability PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import test_quic as q
import test_quic_soak as soak
import test_quic_mesh as mesh
import test_quic_resilience as resilience
import test_integration as integrated
import test_quic_offload as offload
from mojo_support import runtime_threads
folder = q.BUILD / 'fixtures'
q.THREAD_BASELINES['mojo'] = runtime_threads(q.BUILD / 'mojo-peer')
soak.pairing('mojo', 'nim', folder, 16, 8)
mesh.pairing(('nim', 'mojo'), folder, 12, 4)
resilience.disruption(('mojo', 'odin'), folder, 12, 4)
resilience.overload('mojo', folder, 12, 4)
q.THREAD_BASELINES['mojo'] = runtime_threads(integrated.BUILD / 'mojo-peer')
integrated.service('mojo', folder, integrated.corpus()[0], 12, 4, True)
q.THREAD_BASELINES['mojo'] = runtime_threads(offload.BUILD / 'mojo-peer')
offload.exercise('mojo', folder, offload.corpus()[0], 10, 2, 128, True)
PY
```
