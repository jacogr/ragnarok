# Balsa HTTP request-head parsing

Google QUICHE at `00f72ede07a4e6c58116a6411a9f21662c4e292e` supplies Balsa for
[RPC upgrades](rpc.md), [UI](ui.md), [MCP](mcp.md) and [local management](management-rpc.md).
The pinned sources remain pristine. [The request-head owner](../src/lib/http_head.nim)
and [native adapter](../native/quic/http_parser.cc) explain parsing, ownership and framing.
Services retain their endpoint access policies and authorize bounded bodies after parsing.

## Verification

The `http_head` native suite exercises fragmented input, the head/body boundary, owned fields,
exclusive moves, ordinary repeated fields, full-width checked Content-Length, ambiguous framing
refusal and the library head limit. `rpc`, `ui`, `mcp` and `management_http` cover actual service
policies, partial reads, request retirement and connection shutdown. Balsa accepts interior HTAB
in unrelated field values without rewriting; the former Nimony tab-refusal witnesses now check
this library behavior. Selector ambiguity and application body limits remain explicit refusals.
Linux runtime evidence is recorded separately from local macOS checks and semantic compilation.
