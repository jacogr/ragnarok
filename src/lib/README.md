# Shared utilities

[Source guide](../README.md) · [Shared boundaries](../../docs/design.md#shared-boundaries)

This folder contains reusable infrastructure that does not own a particular protocol feature.
Callers retain their own domain validation, scheduling and resource policy.

| Module | Contents |
| --- | --- |
| [`logging.nim`](logging.nim) | Explicit bounded background diagnostics, lazy level/target filters and counted overload drops |
| [`json_writer.nim`](json_writer.nim) | Owned structured JSON values, escaping, object/array separators and full-width integer output |
| [`atomic_file.nim`](atomic_file.nim) | Bounded regular-file reads and atomic whole-file byte publication with explicit durability outcomes |
| [`atomic_file_writer.nim`](atomic_file_writer.nim) | Exclusive publication ownership, stable advisory lock files and explicit retirement |

The JSON writer expects callers to validate UTF-8 and enforce payload budgets. File helpers own
the POSIX read/write/sync/replace mechanics; checkpoint formats, trusted identities and canonical
adoption policy stay with their [state](../state/README.md) and [application](../app/README.md)
callers. Publication distinguishes a durable success from bytes made visible before a failed
synchronization barrier.

The [state checkpoint contract](../../spec/state-checkpoint.md) and
[application checkpoint contract](../../spec/application-checkpoint.md) describe the persistence
consumers and their failure/ownership verification.
