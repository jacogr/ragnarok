# Restart after a storage process crash

A process crash interrupts a caller without running its normal close or ownership cleanup.
On restart, use the selected layout's strict open path. Preserve the files and the original
operation receipt when investigating a failure. Visible bytes may include work whose caller never
received success; reopening and validating those bytes does not retroactively confirm an earlier
application adoption.

| Interrupted work | Restart behavior |
| --- | --- |
| Complete journal append | Strict replay can admit the complete visible successor after validating identity, frames, graph and configured limits. |
| Incomplete final append | Strict open refuses the tail. Explicit recovery still requires the exact independently selected complete-prefix generation and root. |
| Explicit recovery | Truncation may already be visible even though the recovery caller died. Strict reopen admits only a complete prefix; the same independent exact token can finish confirmation. |
| New legacy identity | An existing complete identity can reopen as generation-zero repository metadata. This is not an authenticated complete JAM state. Creation never overwrites the file. |
| New managed directory before CURRENT | Staged files alone grant no selected state. Preserve the namespace; retrying initialization over it is refused. |
| Managed CURRENT replacement | Strict open validates exactly the visible selected epoch. Never select a snapshot or journal by scanning filenames. |
| Compaction before CURRENT replacement | The old selected epoch remains authoritative. Staging remains forensic evidence until explicit bounded cleanup. |
| Compaction after CURRENT replacement | The complete new epoch remains selected. Old-file deletion is separate cleanup and never implies rollback. |
| Migration destination | The source remains independently owned and unchanged. An existing destination is never overwritten; strict open may admit it only when its complete CURRENT is visible. |
| Explicit staging/retired cleanup | Some bounded removals may already be visible. Strict reopen preserves remaining evidence, and explicit idempotent cleanup can finish only its allowed names. |
| Process dies while holding a lease | The kernel releases that process's descriptor references. A competing owner must still return Busy while a stopped child actually retains the lease. |

There is no repair CLI. Direct recovery APIs are separately explicit; startup does not invent a
rollback token. Storage context remains opaque and moves with the selected complete head. Historical
root availability does not grant chain/finality or checkpoint-import trust. The stricter application
maintenance-failure policy and confirmed-prefix reporting are documented in the
[managed-storage guide](managed-storage.md) and [I/O failure guide](storage-io-failures.md).

## What the process-crash checks establish

The native tests stop a real child immediately after a selected successful SDK operation. A private
fixed-size receipt identifies its exact operation and ordinal; the parent requires the owned child's
SIGSTOP, then sends SIGKILL and verifies its signal termination and reap. Normal completion is a
different positive control. Missing hooks, unmarked stops, early exits, invalid controls and expired
monotonic deadlines cannot pass as crash witnesses. No normal child close or ARC retirement runs
after the witnessed stop.

The matrices cover complete/partial journal writes, all publication barriers, multi-publication
prefixes, opaque context, managed replacement and retention, creation, independently authorized
repair, source-preserving migration and bounded cleanup. Exact authored bytes/maps, explicit historical
extraction, strict restart, retained readers and real cross-process contention constrain the results.
The [verification contract](../spec/storage-crash-recovery.md) records the current merged baseline,
exact GP pin, suites and scope. Run a focused case with `make unit SUITE=<name>`.

SIGKILL leaves the host kernel, filesystem and page cache alive. These checks establish process-crash
restart behavior; they do not certify sudden hardware power loss, storage-device write ordering,
filesystem failure or production-scale layout performance. Those need separately scoped environments
and evidence. M1 and complete protocol state-serialization scope remain unchanged.

The grouped **Perf Storage** job remains the separate checked comparison of memory, journal and
managed storage. Its [performance guide](storage-performance.md) explains workload boundaries,
selected-file metrics and timing variability; successful timing never grants recovery authority.
