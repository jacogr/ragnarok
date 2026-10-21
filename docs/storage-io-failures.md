# Storage I/O failures and restart

Storage reports syscall failures separately from the logical state it can prove. Keep the original
files and the actual operation receipt when diagnosing a failure. A failed receipt can coexist
with bytes already visible on disk; strict reopen determines which complete physical head is
admissible. Defaults, disk formats, full/light separation and independent checkpoint-import trust
are unchanged.

| Boundary | Observed behavior | Follow-up |
| --- | --- | --- |
| Read or write interrupted after real progress | Resume the same descriptor and remaining extent on `EINTR`; positive progress comes from the kernel. | Accept success only after complete validation and required barriers. |
| Write returns zero | Stop immediately with an I/O failure; never spin or fabricate progress. | Retain the failed append and reopen strictly. |
| Durability barrier interrupted | Retry `fsync` on the same live descriptor. | A permanent refusal remains an uncertain result. |
| Nonblocking lease interrupted | Retry the same `flock` flags; actual contention still returns `Busy`. | Retire the attempted owner; do not bypass the lease. |
| Descriptor close reports an error | Disarm ownership and report the error without retrying the descriptor number. | Another resource may already own that number. |
| Initialization barrier refused | Expose no live owner; preserve any created files. | Creation remains absent-only. Inspect the existing target and use strict reopen if complete. |
| Ordinary append refused | Poison the live owner after uncertain progress. | Strict reopen rejects an incomplete tail; do not infer a durable publication from attempted writes. |
| Explicit repair truncation interrupted | Retry the same independently validated extent only. | Recovery still requires the exact independent generation/root token. |
| Explicit repair barrier refused | Expose no repaired live owner, even if truncation became visible. | Strict reopen or the same explicit token must independently confirm the remaining complete prefix. |
| Managed manifest rename refused | Keep the old `CURRENT`, preserve successor staging and poison the failed owner. | Strict reopen selects the old complete epoch. Explicit bounded staging cleanup may permit a later retry. |
| Manifest visible but final barrier refused | Return uncertainty and expose no candidate owner. | Strict reopen follows the visible validated `CURRENT`; never select an epoch by scanning filenames. |
| Retired-file unlink refused after confirmed replacement | Return a successful replacement with a separate cleanup error. | Keep the confirmed new epoch; explicit retired-epoch cleanup is idempotent. |
| Explicit staging unlink or sync refused | Report cleanup failure without changing selected state. Some removals may already be visible. | Strict reopen preserves remaining staging; retry only the bounded explicit cleanup. |
| Migration destination write or sync refused | Expose no failed destination owner; retain the locked source unchanged. | Preserve source bytes/context/history. An existing destination is never overwritten by retry. |

The direct storage APIs expose these receipts. The application maintenance policy is stricter:
a maintenance failure disables further mutation for that Services lifetime, including when the
child was already confirmed. Restart and confirmed-prefix reporting are described in the
[managed-storage operations guide](managed-storage.md). There is no repair CLI.

## Verification scope

The native observer calls real SDK operations except at explicitly armed, bounded refusal points.
Tests require every configured refusal to execute. Genuine short reads/writes, strict reopen,
complete authored maps, held readers and exact file bytes provide independent witnesses. The
close test actually retires and reuses each descriptor number before returning `EINTR`; the
replacement must remain open. This models one allowed close-error outcome, not a universal claim
about all kernels.

Focused suites added for the later I/O boundaries are:

| Suite | Contract checked |
| --- | --- |
| `storage_truncate_recovery` | No truncation during strict startup; interrupted exact-token repair and permanent truncation refusal. |
| `storage_interrupted_locks` | Resumed acquisition/unlock, real competing-owner `Busy` and lease release after refused unlock. |
| `storage_manifest_refusal` | Actual rename refusal, exact staged evidence, strict old-epoch restart and explicit retry. |
| `storage_retirement_refusal` | Both retired-file unlinks, separate cleanup receipts and strict confirmed-epoch restart. |
| `storage_close_reuse` | All two legacy and three managed descriptor retirements without retrying a reused number. |
| `storage_bootstrap_barriers` | Every actual initialization sync, failed-owner exclusion and exact forensic preservation. |
| `storage_migration_io` | Every destination write/sync, unchanged locked contextual source and both retained complete maps. |
| `storage_staging_cleanup_io` | Every bounded staging unlink/sync, restart preservation and untouched farther epochs. |
| `storage_short_reads` | Real eight-byte progress before interruption/refusal and one-byte physical ceiling rejection. |

Use `make unit SUITE=<name>` for an individual suite. Earlier write, barrier, compaction and repair
matrices are recorded in the [physical storage verification contract](../spec/storage-traversal.md).
The [performance guide](storage-performance.md) explains the separate checked memory/journal/managed
comparison and its grouped **Perf Storage** summary.

These deterministic syscall tests do not certify power-loss behavior, filesystem/device durability,
production-scale layout tuning or complete protocol state-transition serialization. The documented
[M1 boundary](../spec/storage-records.md) remains unchanged; application context stays opaque to the
storage migration and I/O layers.
