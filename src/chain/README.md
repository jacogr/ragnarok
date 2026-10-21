# Chain snapshots and queries

[Source guide](../README.md) · [RPC and chain design](../../docs/design/rpc.md)

These modules retain immutable configured block/state views and expose bounded reads for RPC
and application consumers. They separate captured data from the authority to execute or finalize
blocks.

| Module | Contents |
| --- | --- |
| [`parameters.nim`](parameters.nim) | Owned fixed-width protocol parameters with explicit unavailable results |
| [`genesis.nim`](genesis.nim) | Configured genesis capture and immutable complete-map block snapshots |
| [`provider.nim`](provider.nim) | Bounded linear history, exact block/parent lookup and explicit advance/finalize operations |
| [`services.nim`](services.nim) | Service metadata, storage, preimage and request-history reads |
| [`reports.nim`](reports.nim) | Work reports retained in configured availability assignments and ready queues |
| [`statistics.nim`](statistics.nim) | Validated activity statistics from a retained state snapshot |
| [`beefy.nim`](beefy.nim) | BEEFY commitment reads from configured history, without a signature or finality claim |

Advancing a view checks linkage and snapshot compatibility; it does not execute a block, choose
a fork or verify consensus. Finalization records caller-certified finality. Old readers retain
their immutable views. [Application orchestration](../app/README.md) owns selected canonical
state and explicit publication; [RPC](../rpc/README.md) exposes these observations.

The [RPC contract](../../spec/rpc.md) describes query semantics, retention, publication boundaries
and verification. Configuration supplies data; missing state remains an explicit query refusal.
