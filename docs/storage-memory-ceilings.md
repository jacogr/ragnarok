# Storage under child-local address-space ceilings

Use `make bench-storage-memory-ceilings` to collect bounded fresh-native reopen experiments.
Make provisions the pinned checked ARC/Clang release/LTO profile. Results are separate from
storage speed samples and existing whole-process/lifetime resource panels.

The runner builds the existing native fresh-reopen workload and prepares four exclusive synthetic
namespaces: journal and managed backends, each with32,768 and131,072 distinct entries and16
publications. Each producer closes before any consumer starts. The native consumer checks its
exact producer root, generation17, every authored key/value, retained views after close and final
ARC release. Parent-side hashing verifies every selected file remains byte-identical.

Each namespace receives five declared trajectories:

1. An unrestricted native reopen under the inherited address-space limits.
2. A128 MiB child soft address-space ceiling.
3. A512 MiB child soft address-space ceiling.
4. A1 GiB child soft address-space ceiling.
5. Another unrestricted native reopen, including after refused/signalled capped attempts.

The compiler, producer and parent remain uncapped. Each capped request first requires a separately
started Linux probe: apply and read back the finite soft limit without raising inherited bounds,
touch a fixed1 MiB positive mapping, and observe refusal of a mapping whose size equals the
entire cap. The negative mapping is never touched. This proves a bounded allocation control in
that probe process; the native launcher separately records its own inherited/applied limits.
The hard address-space ceiling is preserved. No host/cgroup setting is written.

## Availability and termination

Darwin records unsupported caps and still runs both native controls per namespace. A Linux host
may also report unavailable probes because an inherited bound is already stricter or the positive
mapping cannot succeed. Unavailable caps retain their planned rows and explicit reasons; they are
never zero-resource or successfully constrained observations. Successful probes permit all three
requested caps; native loader/allocation/assertion refusal may still occur.

| Outcome | Meaning |
| --- | --- |
| `completed` | Exit zero plus independently reparsed native complete-map/lifetime assertions |
| `nonzero-exit` | Actual native/loader exit; cause remains unclassified |
| `signal` | Actual signal termination; SIGKILL does not by itself prove OOM |
| `unavailable` | Cap not executed because its prerequisite probe did not establish enforcement |

Failed unrestricted controls, changed selected bytes, observer errors, malformed native output,
input drift, timeouts or late artifact-write errors fail the panel. The maintained process-group
timeout runner kills descendants. Disposable launchers suppress core dumps. Failure removes public
Markdown/CSV success while preserving raw logs and failed/partial result receipts.

## Read the evidence

`build/tests/storage-memory-ceilings/` contains `results.json`, `summary.md`, `observations.csv` and
per-stage logs. Native child resources include the small exec launcher startup; producer setup,
parent hashing and the uncapped observer are excluded. The OS cache remains alive and may be
warmed by producers or fingerprints. Linux process status/fault snapshots describe the parent at
the named boundary; child lifetime resources come independently from the fresh observer.

Linux PSI and visible current cgroup memory files are read-only context. Their raw values and
namespace mapping are retained, or availability is explicit. Cgroup limits are local observations;
ancestor bounds may be stricter. Shared counters include unrelated work and descendants. Their
changes do not attribute this child's exit to OOM, paging or device reads.

Setup-free `make summary-storage-memory-ceilings SUMMARY_OUTPUT=build/ceiling-status.md` validates
the report and appends control/completed/unavailable/nonzero/signal counts. Missing or malformed
reports return failure. The existing Perf Storage CI job retains this evidence beside the original
speed and six resource panels, with the same opt-in labels and timeout. Publication does not
request CI.

To compare two reports from identical recorded inputs and binary:

```sh
python3 tools/compare_storage_memory_ceilings.py \
  --baseline build/baseline/storage-memory-ceilings/results.json \
  --candidate build/tests/storage-memory-ceilings/results.json \
  --output build/storage-memory-ceiling-comparison.md
```

Both reports must be complete, clean-source, validated and match source/build/interpreter/host,
filesystem, inherited bounds, probe support, current cgroup limits, physical namespace and outcomes.
The comparison presents independent child peaks without subtracting them or claiming a speedup.

Address-space refusal is distinct from a resident-memory ceiling or induced paging. This bounded
panel does not establish out-of-core operation. Controlled resident memory/cgroup experiments,
page packing and hardware/filesystem/device power-loss qualification remain separate work.
Complete protocol serialization remains owned by the state workstream; no new M1 completion is
claimed. See the [feature contract](../spec/storage-memory-ceilings.md) and
[resource interpretation guide](storage-resource-measurements.md).

## Configured file limits versus allocator exhaustion

Known regular files larger than a caller's physical byte ceiling now return `LimitExceeded`
before the reader grows its detached buffer. The reader still enforces actual byte counts and
one excess byte if the file grows after stat. Native one-MiB-heap regressions cover both layouts,
and real post-stat growth witnesses preserve that final read-loop check.

A file byte ceiling is not a heap/RSS budget. A file that fits its declared ceiling may still
exhaust memory during buffering or complete-graph reconstruction. The pinned allocator's OS
page-mapping failure aborts outside ordinary exception recovery; this change does not make those
failures catchable or cure the original large128 MiB constrained opens. See the
[allocation-failure evidence](../spec/storage-allocation-failures.md) for the exact observed
fail-stop path, bounded fix and remaining Linux qualification scope.
