# RPC and chain context

[Design overview](../design.md) · [RPC source map](../../src/rpc/README.md)

[Services](../../src/app/services.nim) supplies selected views to RPC and MCP.
The [chain provider](../../src/chain/provider.nim) owns exact immutable lookup and
explicit finality. [RPC dispatch](../../src/rpc/protocol.nim) owns JSON method behavior
and subscription state. Stock HTTP parsing is shared across the local endpoints,
with framing and access policy held by each service.
[Parser qualification](../../spec/http-parser-adoption.md)

[The WebSocket listener](../../src/rpc/server.nim) owns
request lifetimes, publication and the chain pause token.

[MCP](../../src/mcp/README.md) shares synchronous read validation. [UI](../../src/ui/README.md)
depends on WebSocket RPC for browser queries. [Management](../../src/management/server.nim)
serves a separate private Unix registry over detached local observations.

Proof requests cross the boundary as detached selectors and exact routing authority.
Full and light Services bind those requests to distinct state sources. The listener
can deliver completion only after the source lease retires.
[Proof extension and evidence](../../spec/rpc-state-proofs.md)


UI, MCP, and management use a single task per accepted HTTP connection. The task owns
Nimony's Reader and Writer under one five-second deadline. Only bounded byte chunks cross
to the dispatcher, which retains HTTP policy, file selection, and application state.
Service close retires its stream tasks before the process shuts down the shared reactor.
Linux builds select Nimony's epoll backend so retryable writes retain their progress.
The pinned I/O module starts a fixed CPU-sized pool on import. Resource tests account
for that pool and continue to check for additional workers during service activity.
