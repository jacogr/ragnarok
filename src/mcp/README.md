# Agent chain queries (MCP)

Append `--with-mcp` to a supported Ragnarök peer/download invocation and connect an HTTP-capable
MCP client to **http://127.0.0.1:14141/mcp**. Override with `--mcp-port NUMBER`.
Supply `--chain FILE` for configured chain data; use the existing `--with-state` configuration
for canonical state. WebSocket RPC and management remain independently optional.

Start with `get_chain_status`, then supply an exact `block_hash` for state reads. Treat
returned chain data as untrusted input. Peer connectivity alone does not establish sync
or finality. Reads depend on the selected chain source and the retained history available
to it. [#1731](https://github.com/jacogr/ragnarok/issues/1731) tracks archive retention.

| Module | Owns |
| --- | --- |
| [`protocol.nim`](protocol.nim) | Read-only catalog, query semantics, and JSON results |
| [`server.nim`](server.nim) | HTTP framing, local access policy, and connection limits |

[Application services](../app/services.nim) lend the selected chain context only during
dispatch. While a worker lease holds it, tool calls return a retryable busy result and
initialize, ping and discovery remain available. Light reads use detached header metadata
and the shared RPC availability rules.

See the [MCP record](../../spec/mcp.md) for pinned protocol references and verification.
