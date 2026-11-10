# Read-only MCP chain queries

Tracking: [#1732](https://github.com/jacogr/ragnarok/issues/1732).

## Contract and references

This feature targets MCP **2025-11-25** [lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) and
[Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).
It adds an observational interface; the repository's pinned JAM/Gray Paper interpretation and
existing chain/RPC query contracts remain authoritative. MCP does not execute or finalize blocks.

The [source guide](../src/mcp/README.md) covers setup. The
[query adapter](../src/mcp/protocol.nim) owns tool behavior and the
[HTTP listener](../src/mcp/server.nim) owns transport and access policy.

Tool discovery metadata follows the pinned
[MCP schema](https://modelcontextprotocol.io/specification/2025-11-25/schema#listtoolsrequest).
The native and official SDK regressions exercise empty metadata, string/numeric progress tokens,
and cursor rejection followed by successful requests.

Observed on 2026-10-28 (macOS ARM64): the added official SDK regression first failed against the
unchanged server with `This fixed catalog has no cursor`. After the fix, `make unit SUITE=mcp`,
`make check-mcp-interop` (three scenarios, six sessions, 116 messages and 110 correlated replies),
68 focused Python safeguards and pinned formatting passed locally. Linux CI remains separate.

## Completion evidence

Required local checks: `make unit SUITE=mcp`, `make unit SUITE=mcp_services`,
`make unit SUITE=app_options`, affected RPC/application/light consumers, formatting and inventory.
The MCP native suite covers initialization, schemas, malformed envelopes, read-only allowlisting,
exact block/root reads, integer precision, HTTP framing/access policy and real loopback IO. Services
checks cover disabled startup, MCP-only configured/canonical reads, busy exclusion, restart and rollback.
The advancing application scenario checks RPC/MCP head agreement after actual canonical adoption;
light-runtime scenarios check mode, absent finality and updated proof coverage. The registered E2E
`mcp` workload initializes a real executable, discovers its catalog and reads its configured head/root
using fresh HTTP client connections. A source-owned compiler guard rejects socket-owner copying. Record observed results after execution;
these checks establish implemented scope, not full MCP-client ecosystem interoperability.

Observed on 2026-10-28 with pinned Nimony 0.6.3 `358b9bce4`, ARC, Clang, checked release,
on macOS ARM64 at initial implementation `67fc9a65`: all six scoped native suites above passed; application_services retained its
1000-cycle unchanged-allocation witness. `make build`, the registered real-process MCP workload,
format/inventory checks and the 462-module/entry-point smoke compilation passed. The owner guard
failed lowering with the exact expected `'=dup' is not available for type <McpServer>` diagnostic.
The 26 targeted Python E2E/inventory/native-requirement safeguards passed. Linux CI remains
separate exact-head evidence. Archive lookup extensions remain dependent on the supported storage
query boundary from #1731; they are not provided by this tranche.

After merging master `a0dcebe4`, the CLI default conflict was resolved by preserving both standalone
PVM settings and MCP port 14141. The CLI suite, formatting/inventory, 464 production modules plus
the entry point, executable build and real-process MCP workload passed again. MCP transport,
query adapter, canonical service integration and light metadata code are unchanged from the native
suite evidence above; unchanged suites were not repeated.

## Official SDK interoperability

`make check-mcp-interop` provisions the unmodified official Python
[MCP SDK v1.26.0](https://github.com/modelcontextprotocol/python-sdk/tree/v1.26.0) in
`build/mcp-interop-python/` using the complete hash-locked closure in
`tools/mcp-interop-requirements.txt`. This test-only SDK pin implements protocol 2025-11-25;
it changes no runtime dependency, compiler, Gray Paper or JIP pin. Make also builds the peer and
the driver generates disposable native TLS fixtures under ignored `build/`.

The SDK's public `ClientSession` and `streamable_http_client` send actual initialize, initialized,
ping, list and tool-call messages over loopback to the real executable. Three independent peer
scenarios cover configured service state, canonical complete state and missing chain configuration;
each uses two freshly initialized SDK clients. Every advertised tool is called, result schemas are
validated, raw service/preimage values are checked against independent frozen fixtures, decimal
precision and empty/null distinctions are preserved, and protocol errors arrive as SDK `McpError`
while chain lookup failures remain `isError` results. Successful concurrent ping/discovery after
errors verifies continued session usability.

Public HTTPX observation hooks record actual requests and replies without rewriting messages or
patching the SDK. Trace validation requires lifecycle order, negotiated headers, notification
acknowledgment, unique request IDs and exactly one correlated response per request. Each peer,
session, connection, message size and wait is bounded; cleanup kills/joins failed processes.
`build/tests/mcp-interop/results.json` records SDK/protocol/environment, actual executable hash,
requirements/driver/fixture hashes and per-scenario verdicts; per-session JSONL and peer logs retain failure context.
E2E / MCP CI runs the same Make target and uploads only these result/message/log files, excluding
TLS fixture keys and dependency environments. Failed/incomplete cases must fail the group.

This end-to-end SDK gate also checks interoperability with an independent MCP implementation.
It complements the self-contained native and raw HTTP checks. It does not test public deployment,
archive history, subscriptions, signing or consensus/finality validation.

Observed locally on 2026-10-28 (macOS ARM64, Python 3.14): `make check-mcp-interop` passed
with SDK 1.26.0 and the unmodified server implementation. The three scenarios completed six SDK
sessions, 92 MCP messages, 86 correlated replies and 56 tool calls. Notification acknowledgments
are separate HTTP 202 responses. The 68 focused SDK-harness, CI and inventory safeguards passed;
workflow YAML parsing and inventory preflight also passed. Linux/Python 3.12 remains separate CI
execution evidence. Detailed results and message traces are retained under `build/tests/mcp-interop/`.

Request-head syntax and header limits follow the [stock HTTP parser](http-parser-adoption.md).
