# Application entry and services

[Design overview](../design.md) · [CLI guide](../cli.md) · [Source map](../../src/app/README.md)

The [entry point](../../src/ragnarok.nim) owns process configuration and shutdown.
[Services](../../src/app/services.nim) owns optional listeners and coordinates the
canonical or light state owner. Transport callbacks retire before that aggregate.
The [chain owner](../../src/app/chain.nim) selects complete state independently of
listener lifetime. RPC publication joins the same selected view.

The dispatcher coordinates execution, proof and disk work through explicit leases.
A worker retains exclusive ownership until exact collection or joined close.
UI and local management can use detached observations during exclusion.
[Preparation worker](../../src/app/preparation_worker.nim) · [RPC lease](../../src/rpc/server.nim)

The [download command](../../src/app/download/command.nim) drives bounded acquisition
and deferred adoption. [Node activation](../../src/app/node_command.nim) supplies
operator-selected local finality and a Common Era clock. Peers supply claims and bytes,
while the state and execution owners admit a child and publish its successor.

## Bounded development validators

The [author](../../src/app/block/author.nim) returns signed candidate bytes.
The [Tiny host](../../src/app/devnet_command.nim) drives native transport, candidate
validation, journal publication and replay. See [Tiny devnet](../../spec/tiny-devnet.md)
for qualification scope.
