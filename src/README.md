# Source guide

[Project overview](../README.md) · [Design](../docs/design.md) ·
[Development and verification](../docs/development.md)

JAM protocol logic is implemented in Nim with the pinned Nimony compiler. Narrow maintained
[C/Rust bridges](../native/README.md) provide cryptographic primitives and transport integration.
The current executable is a development proof peer; full client operation remains future work.

Modules are grouped by feature family, with another subfolder when two or more modules
share a subfamily. For example, checkpoint codecs live at `app/checkpoint/codec.nim` and
current accumulation stages at `state/accumulation/current/`. Standalone modules stay
beside their related family folders. The PVM folder retains its existing layout.

## Folders

Each folder's README describes its modules, usage, contracts and verification.

| Directory | Summary |
| --- | --- |
| [`app/`](app/README.md) | Application configuration, services, selected state, downloads and checkpoint orchestration |
| [`bandersnatch/`](bandersnatch/README.md) | Typed VRF/RingVRF primitives and owned native handles |
| [`chain/`](chain/README.md) | Immutable configured block/state views and bounded chain queries |
| [`codec/`](codec/README.md) | Canonical encodings, nominal protocol values and owned snapshots |
| [`crypto/`](crypto/README.md) | Hash/signature primitives and protocol transcript composition |
| [`lib/`](lib/README.md) | Shared JSON output and bounded atomic file utilities |
| [`pvm/`](pvm/README.md) | Program decoding, immutable machine memory and bounded execution |
| [`quic/`](quic/README.md) | Nonblocking transport, authenticated peer sessions and download dispatch |
| [`mcp/`](mcp/README.md) | Optional read-only MCP tools for agent chain queries |
| [`rpc/`](rpc/README.md) | Optional WebSocket JSON-RPC queries and subscriptions |
| [`state/`](state/README.md) | Complete-state snapshots, transitions and execution composition |
| [`storage/`](storage/README.md) | Incremental complete-state trie and standalone persistence primitives |
| [`telemetry/`](telemetry/README.md) | Optional bounded JIP-3 telemetry delivery |
| [`ui/`](ui/README.md) | Embedded static server and Nimony browser prototype |

## Entry point and build identity

[`ragnarok.nim`](ragnarok.nim) is the shared native application entry point for production and
E2E builds. `make` builds `build/ragnarok` with integration and bounded proof offload enabled.
Run `build/ragnarok --help` for commands. The [application guide](app/README.md) describes
orchestration and optional services.

[`version.nim`](version.nim) exposes the application version from [`version.json`](version.json)
and generated build metadata. `RAGNAROK_VERSION=0.1.0 make` overrides the version for packaging.
`build/ragnarok --version` reports application/compiler revisions and the embedded UTC timestamp;
RPC exposes the same identity.

## Scope and verification

Feature contracts in [`spec/`](../spec/README.md) record precise behavior, evidence and remaining
gates. The [implementation scope](../docs/design/scope.md) and [M1 codec progress](../docs/m1.md)
distinguish implemented foundations from complete client milestones.

Tests live under [`tests/`](../tests/README.md). Use `make check` for full verification or select
an affected group from the [testing guide](../docs/testing.md).
