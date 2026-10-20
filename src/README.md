# Source guide

[Project overview](../README.md) · [Design](../docs/design.md) ·
[Development and verification](../docs/development.md)

JAM protocol logic is implemented in Nim with the pinned Nimony compiler. Narrow maintained
C/Rust bridges under [`native/`](../native/) provide cryptographic primitives and transport
integration. The current executable is a development proof peer; full client operation remains
future work.

[`ragnarok.nim`](ragnarok.nim) is the shared native application entry point for production
and E2E builds; [`version.nim`](version.nim) exposes embedded build identity from
[`version.json`](version.json) and generated metadata. [`app/`](app/) owns validated options
and telemetry/RPC/UI startup.

## Modules

| Path | Purpose | Further reading |
| --- | --- | --- |
| [`app/`](app/) | Shared application configuration and optional service ownership | [Application design](../docs/design/app.md) |
| [`bandersnatch/`](bandersnatch/) | Typed release-reference IETF VRF/RingVRF adapter and domain policy | [Crypto guide](../docs/crypto.md) |
| [`chain/`](chain/) | Chain configuration, genesis capture and immutable query/publication views | [RPC and chain design](../docs/design/rpc.md) |
| [`codec/`](codec/) | Canonical codecs, consensus-facing types and immutable owned snapshots | [Codec guide](../docs/codec.md) |
| [`crypto/`](crypto/) | Blake2b-256, Ed25519, Keccak-256 and signing contexts | [Crypto guide](../docs/crypto.md) |
| [`lib/`](lib/) | Shared utilities, including the structured JSON writer | [Shared boundaries](../docs/design.md#shared-boundaries) |
| [`pvm/`](pvm/) | Program decoding, machine snapshots and bounded execution foundations | [PVM design](../docs/design/pvm.md) |
| [`quic/`](quic/) | Nonblocking LSQUIC adapter, authenticated CE 143 peer and bounded proof offload | [Networking guide](../docs/networking.md) |
| [`rpc/`](rpc/) | Optional WebSocket JSON-RPC queries and bounded subscriptions | [RPC contract](../spec/rpc.md) |
| [`state/`](state/) | Serialized state storage, Merklization and transition foundations | [State design](../docs/design/state.md) |
| [`telemetry/`](telemetry/) | Optional bounded JIP-3 telemetry delivery | [Telemetry contract](../spec/telemetry.md) |
| [`ui/`](ui/) | Embedded gzip static server and Nimony browser prototype | [UI contract](../spec/ui.md) · [Browser prototype](../spec/ui-browser.md) |

Module contracts in [`spec/`](../spec/) record precise behavior, evidence and remaining gates.
The [implementation scope](../docs/design/scope.md) and [M1 codec progress](../docs/m1.md)
distinguish implemented foundations from complete client milestones.

## Development proof peer

`make` builds `build/ragnarok` with integration and bounded proof offload enabled.
The version lives in [`version.json`](version.json); packaging can override it with
`RAGNAROK_VERSION=0.1.0 make`. `build/ragnarok --version` prints the version, application and
compiler Git revisions, and embedded UTC build timestamp. RPC exposes the same identity. See the
[networking guide](../docs/networking.md) for peer commands, certificates and fixtures. The
options below extend an existing `server`, `client` or retained `mesh` invocation; they do not
start a complete JAM node.

### Telemetry

Append `--with-telemetry --telemetry HOST:PORT --chain PATH` with an explicit JIP-4 chain file
to enable the implemented JIP-3 subset. It reports local node information, periodic peer/status
observations, handshake outcomes and disconnections through bounded nonblocking TCP delivery
with reconnects. Telemetry is disabled without `--with-telemetry`.

The chain file supplies telemetry network identity; it does not initialize chain execution or
connect bootnodes. See [telemetry usage, scope and verification](../spec/telemetry.md) for the
full invocation and event limitations.

### WebSocket JSON-RPC

Append `--with-rpc` to expose `ws://127.0.0.1:19800/`; `--rpc-port NUMBER` changes its port.
RPC is disabled unless `--with-rpc` or `--with-ui` is specified. `ragnarok_clientInfo` reports
client diagnostics; `--chain PATH` supplies protocol parameters and can seed a read-only genesis view when an explicit header/state pair is present.

The modules support chain/state/service queries and bounded subscriptions, with dispatcher
publication boundaries for future import and finality integration. The CLI remains genesis-only;
there is no live block importer or consensus finality source. Available methods, missing-state
behavior and configuration-derived placeholders are detailed in the [RPC contract](../spec/rpc.md).
This is partial JIP-2 support.

### Browser UI

Append `--with-ui` to serve the embedded browser prototype at `http://127.0.0.1:8888/`;
`--ui-port NUMBER` changes its port. This also enables WebSocket RPC. The page calls
`ragnarok_clientInfo` and displays the response; its RPC URL is editable for nondefault ports.

Assets are compiled from Nimony and gzipped at build time. CI minifies JS/CSS with a pinned
native esbuild executable; local builds skip it unless `UI_MINIFY=1` is set. The server requires gzip acceptance
and serves no uncompressed fallback. For development, use `--dev-ui-dir build/ui` alongside
`--with-ui` and rebuild assets with `make ui-assets`. See the [UI contract](../spec/ui.md) and
[browser prototype](../spec/ui-browser.md) for build details and verification.

## Verification

Tests live under [`tests/`](../tests/): native application suites in `unit/`, shared support in
`support/`, native drivers and negative fixtures in `native/`, and independent references and
tooling checks alongside them. [`tests/fixtures/`](../tests/fixtures/README.md) documents fixture
provenance. [`vectors/`](../vectors/) holds project fixtures and [`vendor/`](../vendor/) pins
upstream sources.

Use `make check` for full verification, or select an affected group from the
[development guide](../docs/development.md). The [testing guide](../docs/testing.md) describes
native suites and retained independent references.
