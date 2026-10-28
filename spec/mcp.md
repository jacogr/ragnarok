# Read-only MCP chain queries

Tracking: [#1732](https://github.com/jacogr/ragnarok/issues/1732).

## Contract and references

This feature targets MCP **2025-11-25** [lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) and
[Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).
It adds an observational interface; the repository's pinned JAM/Gray Paper interpretation and
existing chain/RPC query contracts remain authoritative. MCP does not execute or finalize blocks.

Append `--with-mcp` to a supported server/client/mesh/download invocation to enable
`http://127.0.0.1:14141/mcp`; `--mcp-port NUMBER` overrides **14141**. Port configuration alone
does not enable MCP. Activation enables neither WebSocket RPC, browser UI nor management.
Invalid/duplicate settings and enabled port collisions fail parsing; bind failure rolls back startup.
The endpoint follows the bounded lifetime of the underlying command, not a new node daemon.

## Protocol and tools

The server supports `initialize`, `ping`, `tools/list` and `tools/call`. Initialization negotiates
2025-11-25, declares only tools, and returns shared build version metadata. It does not request
sampling, roots or elicitation. Transport is stateless: no session IDs or per-client initialization
records are allocated. Clients initialize and send `notifications/initialized` before ordinary work;
valid notifications are acknowledged with HTTP 202. Requests receive one JSON response. GET and
DELETE return 405 (Allow: POST); optional SSE, tasks, subscriptions, resources and prompts are absent.
Each HTTP connection closes after its response; clients reconnect without repeating initialization.
Subsequent requests should include `MCP-Protocol-Version: 2025-11-25`; explicit other revisions are
rejected with HTTP 400. Missing version headers are accepted for initialization and stateless clients.

| Tool | Named arguments | Value |
| --- | --- | --- |
| `get_chain_status` | none | Chain identity, best/finalized descriptors, state/retention observations and peer count |
| `get_parameters` | none | Existing configured parameter object, including explicit zero derivation placeholders |
| `get_block` | `block_hash` | Exact block's posterior state root; no full block-body claim |
| `list_services` | `block_hash` | Bounded complete service-ID list; oversized results fail rather than truncate |
| `get_service` | `block_hash`, `service_id` | Canonical encoded metadata, or null for absence |
| `get_storage` | `block_hash`, `service_id`, `key` | Storage bytes, or null for absence |
| `get_preimage` | `block_hash`, `service_id`, `preimage_hash` | Hash-verified preimage bytes, or null for absence |

Hashes/bytes use canonical padded Base64. Service IDs are input JSON integers in 0..4294967295;
storage keys are at most 4096 decoded bytes. All numeric query payload values are emitted as decimal
**strings**, avoiding agent-side floating-point truncation. MCP envelope IDs and schema numeric limits
remain ordinary JSON numbers. Text content repeats exactly the structuredContent object. Every state
query echoes its explicit block hash and configured chain identity. Absent values remain distinct from
present empty bytes. State lookup cannot silently switch to a different head. Query refusals return
`isError: true`; invalid MCP envelopes/tool names/argument shapes use JSON-RPC errors.

The fixed read-only adapter invokes the existing RPC query implementation synchronously, with no
WebSocket hop, arbitrary method escape hatch or subscription state. It shares typed validation and
query budgets. Tool metadata advertises read-only/idempotent behavior; no signing, private keys,
filesystem access, management operations or state mutation is exposed. Returned chain bytes are
untrusted data, never agent instructions.

## Ownership, availability and limits

Services retains fixed configuration and a configured seed only in listener-only operation. For
canonical operation it borrows the actual selected ChainView during one dispatch activation; all
aliases retire before publication or worker admission. MCP's native socket owner retains only bytes.
During CPU/proof/disk leases it answers tool calls with a retryable busy error without copying or
retiring any canonical graph alias. Initialize, ping and discovery remain available.

Chain status explicitly identifies full/light mode; light finality remains null.
Light mode borrows only the actor's already detached header metadata while idle, preserving the
separate proof graph and trust boundary. Existing light RPC semantics determine supported metadata
queries and explicit refusals for complete-state/service reads. Light state is never presented as a
complete state map, nor is its partial root recomputed as a complete JAM root.

There are four nonblocking connection slots, a five-second absolute connection deadline, at most
4096 header bytes, 16384 body bytes, 2048 JSON tokens, 16 parser levels and 131072 reply bytes.
Each tick accepts at most one connection and performs one bounded read/write per slot. Duplicate
JSON fields, malformed UTF-8, ambiguous framing, transfer encodings and pipelined suffixes are refused.
Host must exactly match the selected loopback endpoint (`127.0.0.1:PORT` or `localhost:PORT`). All
Origin-bearing requests are refused with 403: this first local-agent endpoint has no browser origin
allowlist or CORS. Both JSON and event-stream Accept types are required, even though replies use JSON.
No authentication is added; access is trusted local-process access. No public bind or remote deployment
is supported. Slow or disconnected clients cannot extend deadlines or retain graph handles.

Peer connectivity is not proof of synchronization. Available state depends on the selected configured
seed/import path; finality requires an explicit trusted source. Current bounded history and explicitly
selected finalized anchors are queryable; unknown/evicted blocks remain unavailable.
[#1731](https://github.com/jacogr/ragnarok/issues/1731) independently owns archive/configurable retention.
MCP does not interpret journal leftovers as history, backfill blocks or retain an independent archive.

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
Interop CI runs the same Make target and uploads only these result/message/log files, excluding
TLS fixture keys and dependency environments. Failed/incomplete cases must fail the group.

This SDK gate complements the self-contained native/E2E checks. It does not test public deployment,
archive history, subscriptions, signing or consensus/finality validation.

Observed locally on 2026-10-28 (macOS ARM64, Python 3.14): `make check-mcp-interop` passed
with SDK 1.26.0 and the unmodified server implementation. The three scenarios completed six SDK
sessions, 92 MCP messages, 86 correlated replies and 56 tool calls. Notification acknowledgments
are separate HTTP 202 responses. The 68 focused SDK-harness, CI and inventory safeguards passed;
workflow YAML parsing and inventory preflight also passed. Linux/Python 3.12 remains separate CI
execution evidence. Detailed results and message traces are retained under `build/tests/mcp-interop/`.
