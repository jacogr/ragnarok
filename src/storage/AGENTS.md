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
