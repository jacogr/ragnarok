# Stock HTTP request-head parsing

RPC WebSocket upgrades, UI HTTP, MCP Streamable HTTP and Unix-socket management use the
unmodified Nimony head scanner and parser. There is no compatibility layer or custom generic
HTTP admission policy. Socket ownership, dispatcher scheduling, deadlines, application routing,
Host/Origin access checks and request-body budgets remain with each existing service. Telemetry's
binary TCP protocol and QUIC are unaffected.

The compiler/library pin remains `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` in
[toolchain.json](toolchain.json). Public APIs are
[`std/http/httpparse`](https://github.com/nim-lang/nimony/blob/63fed6cb4b2f59d34c9fbb18f1796e671e2024e4/lib/std/http/httpparse.nim)
and [`std/http/httpmsg`](https://github.com/nim-lang/nimony/blob/63fed6cb4b2f59d34c9fbb18f1796e671e2024e4/lib/std/http/httpmsg.nim).
No upstream source patches or dependency upgrades are included. Revisit compatibility only for
an observed supported-client issue, and report relevant limitations upstream then.

## Library behavior

The listeners use `HeadScanner` across partial reads and `parseRequestHead` on the resulting
head. Limits come directly from the library: this pin provides `MaxHeadLen` of 16 KiB and a
100-field ceiling. Supported request-line versions and LF/CRLF handling also come from the
library; there is no added HTTP/1.1-only or CRLF-only filter.

Leading optional whitespace retains stock support. Interior/trailing HTAB in field values is
rejected by this pin, with no tab rewriting. Content-Length uses the library's checked integer
interpretation, including leading zeroes; former local four/five-digit spelling limits are gone.
Ordinary duplicate fields use library behavior. Fields interpreted by the existing application
or handshake policies must remain unambiguous; unrelated extension fields acquire no new policy.
The library rejects ambiguous Content-Length/Transfer-Encoding framing and decimal overflow.

A fresh `HttpMsg` and its vocabulary belong to one synchronous parse attempt. Services inspect
it only after a complete successful parse. Neither the message nor borrowed input survives a
dispatcher turn; failed messages retire through the library's destructor. No HTTP I/O runtime,
worker pool or scheduler is imported.

MCP and management require Content-Length and bound its decoded value before body arithmetic
or dispatch. UI permits only absent or zero length and refuses Transfer-Encoding. RPC refuses
both body-framing headers. Host, Origin, MCP version/media types and management transport
restrictions remain service policy. See [RPC](rpc.md), [UI](ui.md), [MCP](mcp.md) and
[management](management-rpc.md). Syntax errors can precede a service-specific error when a
request violates both sets of rules. Library-unsupported methods are syntax errors; recognized
methods outside a service route retain its method refusal.

## Verification

The `rpc`, `ui`, `mcp` and `management_http` native suites cover their protocol and transport
owners. Focused additions cover stock tab refusals, LF/version acceptance, normalized lengths,
ordinary repeated fields, application selector ambiguity, heads above the former 4 KiB cap and
scanner resumption across packet boundaries. Formatting and verification inventory must pass
before publication. Linux runtime evidence remains separate from macOS results and Linux Smoke.
