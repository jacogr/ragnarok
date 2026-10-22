# Controlled resident-memory pressure

Use `make probe-storage-resident-pressure` on Linux first. It requires systemd, cgroup v2,
readable memory/PSI/IO counters and noninteractive sudo for newly owned transient services.
The small proof runs a successful one-MiB worker and a bounded96 MiB worker inside one
64 MiB/no-swap unit, requiring a local cgroup OOM kill and verified service retirement.
It provisions no compiler or native dependency.

Then run `make bench-storage-resident-pressure`. Make provisions the pinned checked
ARC/Clang release/LTO profile. Existing native fixture producers close before consumers
start; every completed reopen checks the producer's exact root/generation, complete map,
retained views and final ARC release. Exclusive selected files are fingerprinted after
all attempts, including OOM and bounded stalls.

On amd64 Ubuntu, this target supplies a build-owned signed HTTPS source list to the normal
bounded Make host-tools APT calls. Host source files remain unchanged; other targets/hosts
retain their source policy. This avoids the observed Azure HTTP mirror stall.

The panel runs journal and managed layouts at32,768 and131,072 entries, with16 publications.
Two passes reverse case and treatment order. Each case has unrestricted controls before
and after four treatments:

| Treatment | memory.high | memory.max | memory.swap.max |
| --- | ---: | ---: | ---: |
| Soft pressure | 128 MiB | 512 MiB | 0 |
| Tight hard cap | 128 MiB | 128 MiB | 0 |
| Larger hard cap | 128 MiB | 256 MiB | 0 |
| Swap permitted | 128 MiB | 256 MiB | 256 MiB |

Swap is permitted only when256 MiB of existing host swap is free. Missing swap leaves its
rows explicitly unavailable; no host swap, swappiness or global cache policy is changed.
Per-file eviction advice targets only each closed synthetic namespace before every attempt.
Success of that advice is not a cold-cache verdict: inspect actual native input blocks,
per-device cgroup IO counters and reclaim/swap evidence.

Each unique transient service runs its observer and one native child as the repository user.
The parent/compiler/producers remain outside. Unit memory includes observer, charged file
cache and kernel memory, so it differs from native wait4 peak RSS. Sampled anonymous/file
and swap maxima are approximate, and null if exec/exit left no usable proc sample; kernel memory.peak is exact for the unit's lifetime.
Raw local events, memory.stat, PSI and per-device IO remain alongside derived observations.
Device counters are kept separately because stacked block devices can double-count bytes.
Buffered IO can occur with zero major page faults. Shared host counters remain context.

A local max/oom/oom_kill event delta plus SIGKILL establishes a local cgroup OOM observation.
An unrelated signal stays unclassified. A native child stopped by the35-second observation
deadline is a bounded stall, not a successful reopen or inferred OOM. Unrestricted controls
must always complete. Unit RuntimeMaxSec and explicit finally cleanup protect detached
services even when the outer timeout runner stops; only generated owned units may be stopped.

Results are under `build/tests/storage-resident-pressure/`: `results.json`, `summary.md`,
`observations.csv`, raw per-unit receipts and native logs. Failed/partial runs retain evidence
and remove successful public summaries. The explicit `storage-pressure` workflow-dispatch
scope runs the enforcement probe before native setup and retains artifacts on failure.
No performance speed panel, PR label, push or merge implicitly requests this experiment.

Use the observations to distinguish transient buffering/copy costs from retained graph memory,
completed reclaim/swap operation and hard-cap failure. Timings on shared CI are descriptive;
this is not an optimization speedup claim or proof of out-of-core operation. Record actual
conclusions in the [feature contract](../spec/storage-resident-pressure.md) before item3.
