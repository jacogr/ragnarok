# Controlled Linux resident-memory and paging experiments

## Scope and decision

The maintainer requested item2 before choosing item3's storage layout/retention work. Add OS
measurement tooling on the current allocation-diagnosis stack, without changing production
storage, compiler/stdlib sources, build flags, selected bytes, roots or allocator policy.
The existing131,072-entry ordinary Linux controls peaked at347,557,888 RSS bytes for journal
and423,833,600 for managed. Address-space ceilings identified allocating callers but did not
establish resident limits, reclaim, swap or block reads.

Use the same checked ARC/Clang release/LTO fresh-native workload and synthetic namespaces,
with separately closed producers and exact complete-map/root/generation/lifetime checks.
Two passes reverse backend/case/treatment order. Unrestricted controls bracket each case;
treatments cover soft128 MiB/high with512 MiB/max, hard128 and256 MiB/no swap, and
256 MiB/max with256 MiB/swap permitted where existing host swap is available. Each fresh
private unit has a unique generated identity, runs as the repository user, and reads back
actual cgroup controls. Memory limits include observer, native process, charged file cache
and kernel memory: they are not identical to child RSS. Ancestor limits remain visible.

## Isolation and termination

Use systemd's transient-service API, never edit a parent cgroup or global VM policy. The outer
owner remains outside each constrained group. A small Python observer inside the unit starts
one native child, raises only that child's OOM victim preference, samples its actual membership
and gauges, and collects exact wait4 RSS/fault/block counters. A child-owned pre-exec membership receipt
preserves the actual inherited cgroup identity even if that PID exits before live sampling. OOMPolicy=continue and observer-only OOMScoreAdjust=-1000 preserve
observer evidence when a constrained child dies. Every child raises and reads back its own
score1000 before exec, so workloads remain eligible victims. Both raw adjustments and the
child PID/membership receipt are checked. Immunity does not bypass the cgroup memory limit. Only local max/oom/oom_kill event deltas plus
SIGKILL establish the classified local cgroup OOM outcome; unrelated signals stay unclassified.

The observer has a35-second child timeout, systemd RuntimeMaxSec45/TimeoutStopSec5, and outer
65-second command supervision. Detached systemd services are not descendants of the outer
process group: a finally block stops only the exact owned UUID service and checks inactivity.
No shared unit name, slice, host swap setting, swappiness, global cache drop or compiler hook
is authorized or used. The preflight touches one MiB successfully and requires a bounded
96 MiB worker to be locally OOM-killed inside its own64 MiB/no-swap unit. Missing cgroup,
systemd, privilege, kernel fields or limit enforcement fails explicitly before native setup.

## Evidence and interpretation

Retain raw memory.current/peak/high/max, memory.swap.current/max, memory.events.local,
memory.stat, memory.pressure and io.stat before/after each native child. Kernel memory.peak
covers the unit's lifetime including its observer; wait4 supplies exact native-child peak RSS.
Sampled anonymous/file/swap/process gauges are approximate maxima with explicit sample counts. Exec/exit snapshots with missing Vm fields are unavailable;
a child with no usable samples has null sampled gauges, while exact wait4/kernel peaks remain.
Reclaim/fault/stall/device counters are monotonic deltas, never byte-gauge subtraction.

Before each attempt, hash only the exclusive closed synthetic namespace, then advise eviction
only for its regular owned files with POSIX_FADV_DONTNEED. The advisory is not a cold-cache
verdict. Fingerprints afterward must remain identical. Cgroup block bytes include native
loader/library/storage activity and observer overhead; they are not device latency or proof
that every logical storage read reached hardware. Major faults can remain zero with buffered
read IO. Swap allowance without observed swap use does not establish paging. Host swap
availability is recorded, never manufactured; unsupported swap treatments remain explicitly
unavailable, not zero measurements or successful constrained reopens.

Success requires strict before/after native controls, exact input/binary provenance, raw-receipt
reparsing, selected-byte preservation, scoped cleanup and complete planned coverage. Expected
constrained OOM and observer-enforced35-second treatment deadlines are observations, not
successful reopens. Timed-out unrestricted controls fail the panel. Failed/partial logs survive without
stale successful summaries. Conclusions must distinguish completed pressure/reclaim runs,
local-OOM bounds and actual swap/IO evidence before recommending item3's next optimization.

Primary contracts: [systemd resource controls](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html),
[transient services](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html),
and [Linux cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html).
Controlled pressure does not prove out-of-core operation or device power-loss durability.
Complete full/light protocol serialization remains a separate workstream; no new M1 claim.


Linux IO parsing follows `blkcg_print_one_stat`: it prints a device name but omits all
read/write fields when rbytes/wbytes/rios/wios are all zero. This exact zero-elision is admitted;
partially present base fields remain errors. Optional latency/cost gauges stay in raw text and
are excluded from cumulative deltas, since gauges and windowed counters may decrease.
Discard metrics are not inferred from omitted read/write fields. See
[the kernel implementation](https://github.com/torvalds/linux/blob/master/block/blk-cgroup.c).
