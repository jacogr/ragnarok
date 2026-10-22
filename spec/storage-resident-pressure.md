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
one native child, raises only that child's OOM victim preference, records its actual inherited membership
and collects exact wait4 RSS/fault/block counters. A child-owned pre-exec membership receipt
preserves the actual inherited cgroup identity even if that PID exits before parent inspection. OOMPolicy=continue and observer-only OOMScoreAdjust=-1000 preserve
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

Retain raw memory.current/peak/high/max, memory.swap.current/peak/max, memory.events.local,
memory.stat, memory.pressure and io.stat before/after each native child. Kernel memory.peak
covers the unit's lifetime including its observer; wait4 supplies exact native-child peak RSS.
Kernel memory.swap.peak is also read at both boundaries. Optional memory.stat pswpin/pswpout
counters supply exact unit page-in/out deltas when available; absence remains null.
The observer performs no procfs sampling while memory is constrained: kernel allocations for
proc reads themselves can return ENOMEM. It waits in wait4 under a prearmed35-second alarm,
then reads counter receipts only after the native process exits. Alarm ownership is restored
on every path. Reclaim/fault/stall/device counters are monotonic deltas; peaks are lifetime
high-water marks, never gauge subtraction. The unit includes observer startup/resume overhead.


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

## Qualified Linux results and item3 recommendation

[Linux run39803656520](https://github.com/jacogr/ragnarok/actions/runs/39803656520) passed
on clean implementation `0c36419979294e72c1630caf33415550acb3b25a`, including this observer
and its dependent panel. The `storage-resident-pressure-1` artifact retains the native binary,
raw receipts, selected-byte fingerprints, JSON/CSV and complete per-attempt table. Host:
Linux7.0.0-1017-azure x86_64/glibc2.39, AMD EPYC7763, Ubuntu Clang18.1.3; pinned Nimony
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, checked ARC/release/speed/Clang LTO.
The panel validated all48 planned attempts:34 completed, four confirmed local cgroup OOM
kills and ten35-second bounded stalls. All16 unrestricted controls passed. No swap rows
were unavailable. All completed reopens checked generation17, exact producer root, complete
map, retained view after close and final ARC baseline544 bytes. All selected file fingerprints
remained unchanged after every outcome, and all owned services retired.

Both passes gave the same treatment outcomes:

| Entries/backend | Unrestricted native RSS | Open/closed retained Nim | Soft high128/max512, no swap | High128/max128, no swap | High128/max256, no swap | High128/max256, swap256 |
| --- | ---: | ---: | --- | --- | --- | --- |
| 32,768 journal | 89.9–90.3 MiB | 18.7 MiB | completed | completed | completed | completed, zero swap peak |
| 32,768 managed | 104.2–104.4 MiB | 18.7 MiB | completed | completed | completed | completed, zero swap peak |
| 131,072 journal | 331.3–331.4 MiB | 74.2 MiB | deadline | local OOM kill | deadline | completed |
| 131,072 managed | 390.0–404.0 MiB | 74.2 MiB | deadline | local OOM kill | deadline | deadline |

The two larger no-swap soft-pressure treatments spent32.7–34.3 seconds in full memory
stall before the deadline; the max256 treatment retains high128, so this does not establish
failure under an isolated256 MiB hard cap without soft pressure. Tight max128/no-swap rows
had exactly one local OOM kill each. Expected treatment failures are recorded observations;
they do not count as successful constrained reopens.

Large journal swap rows completed with native RSS130.2/130.4 MiB, unit lifetime memory
peaks128.2 MiB and swap peaks242.6/244.7 MiB. Raw unit counters show238,316/243,738
swap pages in and249,764/246,800 out. The unit's `8:0` read bytes were
1,032,421,376/1,054,187,520 and write bytes1,023,045,632/1,010,909,184. Large managed
swap rows reached the full256 MiB swap peak and the deadline in both passes, with
140,204/141,792 pages in,184,420/189,488 out and22.6–24.1 seconds of full memory stall.
These are actual paging/reclaim/IO observations, with substantial repeated traffic. Native
RSS and unit peaks use distinct accounting and sampling boundaries and must not be subtracted.

The artifact was independently reparsed after download: all422 recorded source hashes and
the retained native binary SHA256 matched; all raw kernel/native receipts, plan order, controls,
byte preservation and cleanup validated. Only build-path comparison was relocated to the
recorded Linux root for validation on macOS; imported commands were never executed. Native
binary SHA256: `5415b8269d05447147efbd465cc3db69de3b1a5f762d4a372f72530906376c95`.
The later qualification commits change prose only; covered source/build inputs remain identical.
Local checks cover70 focused Python tests, inventory and workflow YAML syntax.

For item3, first reduce transient read-buffer growth and owned byte-sequence duplication,
using the ordinary allocating callers established by the allocation-diagnosis layer. Preserve
validation, exact selected bytes/roots, complete maps and retained-view ownership. Re-run
this same panel after each bounded change and compare peak memory, paging/reclaim and strict
completion, then decide whether retained graph layout needs further work. The gap between
retained Nim bytes and RSS includes allocator/runtime/loader overhead and does not quantify
copy bytes by itself. Actual swap lets journal complete this fixture but does not establish
acceptable storage latency, managed completion, or out-of-core storage: both readers still
materialize the full graph. No item3 optimization is implemented by this experiment.
