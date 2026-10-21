# Storage workstream boundary

This folder belongs to the standalone storage workstream. State/checkpoint, PVM and application
work continue independently using their existing store and checkpoint APIs.

- Do not modify this folder as part of state/checkpoint or other consumer work, and do not import,
  adopt or integrate its trie into those implementations until the maintainer explicitly authorizes
  a separately scoped integration task. Merging the standalone storage PR does not lift this gate.
- Storage work stays within this folder and its dedicated tests/specification. Do not change state,
  PVM, checkpoint or application implementations to prepare integration without that authorization.
- Do not add adapters, alternate execution paths or anticipatory cross-workstream refactors.
  Status sharing and design discussion do not authorize implementation across the boundary.
- “Future integration” in documentation records a deferred dependency. Before starting it, agree
  the owner, current contracts and validation scope with the maintainer and the other workstream.

See [the module guide](README.md) and [feature contract](../../spec/full-state-trie.md).

## Authorized in-memory StateStore tranche

The maintainer explicitly authorized db #1, coordinated with idle state #5, to integrate only
`full_state_trie.nim` into `src/state/store.nim` in three stacked PRs. Preserve StateStore's public
API, sorted iteration, retained values/forks and atomic publication; validate existing consumers.
This narrow authorization supersedes the earlier isolation gate for that task only. Disk adoption,
canonical durable heads, startup configuration and unrelated state/PVM work remain gated.
See [the integration contract](../../spec/state-store-incremental.md).
