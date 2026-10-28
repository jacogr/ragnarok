# Agent chain queries (MCP)

Append `--with-mcp` to a supported Ragnarök peer/download invocation and connect an HTTP-capable
MCP client to **http://127.0.0.1:14141/mcp**. Override with `--mcp-port NUMBER`.
Supply `--chain FILE` for configured chain data; use the existing `--with-state` configuration
for canonical state. WebSocket RPC and management remain independently optional.

The server targets MCP 2025-11-25 and exposes seven read-only tools: chain status, parameters,
block state roots, service listing, service metadata, storage values and preimages. Start with
`get_chain_status`, then supply an exact `block_hash` for state reads. Query payload integers
are decimal strings; hashes and bytes use padded Base64. Unknown finality/history remains explicit.
Light mode exposes available detached metadata and refuses complete-state reads.

`protocol.nim` adapts the fixed tool catalog to existing synchronous chain queries. `server.nim`
owns bounded nonblocking HTTP sockets and serialized bytes; Services supplies one temporary query
context and enforces worker exclusion. Browser requests are refused; the endpoint trusts local
processes and supports no public bind.

See the [feature contract](../../spec/mcp.md) for limits, protocol details and verification.
