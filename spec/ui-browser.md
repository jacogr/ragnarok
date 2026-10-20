# Nimony browser prototype

This increment proves the existing pinned Nimony compiler can produce a shipped browser UI.
It changes no JAM protocol semantics or RPC method contracts. The page opens a WebSocket and
calls only `ragnarok_clientInfo` with empty positional parameters. Connect sends the first
request; Refresh sends another. Implementation, connected peers, uptime, response count and
the JSON response update through Nim callbacks and DOM bindings. Disconnect and reconnect
retire the old socket callbacks and request timer. A single outstanding numeric request has
a five-second deadline; stale/unsolicited IDs cannot update the page. Backend text is assigned
through `textContent`, never interpreted as HTML.

Start an existing peer command with `--with-ui`, then open `http://127.0.0.1:8888/` (or the
selected `--ui-port`). The editable RPC URL defaults to `ws://<page hostname>:19800/`; set its
port explicitly when using `--rpc-port`. This prototype does not discover port configuration,
auto-connect, poll, subscribe or reconnect automatically. The existing UI Origin policy applies.
It is a diagnostic UI, without a wallet, authentication or validator controls.

## Compiler and build

`spec/toolchain.json` remains pinned to Nimony 0.6.3 at
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`. Its nightly package omits `jorogumo`.
`spec/web-toolchain.json` records SHA-256-verified source archives for that same compiler and
its own `src/nativenif.commit` dependency, `9a9070b5ef8032ada9cd7cb20ce8532b51b10f39`.
`make web-toolchain` restores those pristine sources as siblings under `build/web-toolchain/`
and builds the missing backend. No compiler upgrade, source patch or private-runtime hook is used.
The Nim 2.2.12 executable from the already pinned formatter distribution bootstraps only the
upstream backend; its bytes are checked against the pinned archive before execution. Application
code is compiled by Nimony, not Nim 2. Source/backend/bootstrap identities govern backend reuse.

Upstream manages `nativenif` as a sibling checkout pinned by `src/nativenif.commit`, not a
Git submodule. This project currently restores both source repositories from checksum-pinned
archives under ignored `build/`; neither is a project submodule. The Nimony source revision
must equal the nightly compiler revision, and the nativenif revision must equal that source's
recorded dependency pin. These sources provide the missing backend; the Nimony compiler itself
continues to come from the pinned nightly binary distribution.

**Temporary bootstrap — remove when the pinned nightly ships `jorogumo`.** When updating the
compiler pin, check the official Linux amd64 and macOS arm64 packages for `bin/jorogumo`.
Once both supported packages include it, use that packaged binary from the same toolchain as
`nimony`, preserve backend identity in the UI compiler cache, and delete `tools/setup_web.py`,
`spec/web-toolchain.json`, its bootstrap-specific tests and the Make `web-toolchain` wiring.
Remove the two source downloads and bootstrap-only Nim invocation too; do not retain a parallel
self-build fallback. Keep the Nimony browser compilation, asset embedding and real-browser
verification, and rerun `make check-ui` on the packaged backend before removing this workaround.

`make ui-assets` invokes `nimony j --browser -d:release --mm:arc -d:ragnarokBrowser`, with the
verified backend on that subprocess's PATH. `src/ui/client.nim` contains the application;
`src/ui/static/` contains HTML/CSS. The result is `build/ui/{index.html.gz,style.css.gz,app.js.gz}` and
the existing byte-exact embedded manifest. Local builds retain readable JS/CSS; CI and
`UI_MINIFY=1` use the checksum-pinned native esbuild executable before gzip, as described in
[UI build configuration](ui.md). Ordinary builds and source checks depend on this
step. The backend executable hash separates JavaScript compiler caches. `make clean` removes
all generated code, tools, source archives and test dependencies. Build diagnostics remain in
`build/web-toolchain/bootstrap.log` and `build/ui-client/compile.log`.

The exported `ragnarokUiStart` entry selects jorogumo's host-driven runtime lifetime, and a
deferred classic script initializes once after the DOM exists. Capture-free callbacks and
thread-owned Nim scalar state bridge browser-owned WebSocket/timer/JSON objects through
`importjs`. No compatibility claim for Nim 2's JS libraries is made. The current backend emits
roughly 249 KiB of JavaScript before build-time gzip and reserves a 64 MiB linear heap;
modern browser BigInt support is required. This is a feasibility prototype, not a payload/memory optimization milestone.

For live development use `--with-ui --dev-ui-dir build/ui` and rerun `make ui-assets` after
source edits. Development overrides replace the complete asset directory, so HTML/CSS alone
without generated `app.js.gz` do not run the application. Every asset is precompressed at build
time; the server requires gzip acceptance and never serves identity bytes.
Release binaries need no runtime files.

## Verification

`make check-ui` builds the production peer and uses a real headless browser against its HTTP
and WebSocket listeners. It verifies DOM values, initial/refresh requests, disconnect/reconnect,
invalid URL handling, desktop/mobile layout without horizontal overflow, no uncaught page errors,
gzip response headers for HTML/CSS/JavaScript, and that every outbound RPC request calls only
`ragnarok_clientInfo`. The same browser check runs in the owning RPC workload under `make check-e2e`; raw WebSocket/QUIC checks remain there.
Screenshots, wire requests and diagnostics are retained under
`build/tests/ui-browser/peer/browser/` locally or `build/tests/e2e/rpc/browser/` in E2E.

Browser verification requires Node 20+ and npm. `make browser-tools` installs exact locked
Playwright packages under `build/browser/`, reuses `CHROME_BIN` or installed Chrome/Chromium,
and otherwise provisions Playwright's pinned headless Chromium (including Linux OS libraries).
Application compilation and shipped assets require neither Node nor Playwright.

Local evidence on 2026-10-19, macOS arm64: pinned backend bootstrap, production build and
`make check-ui` passed using Chrome 156.0.8078.36. Four observed JSON-RPC requests all called
`ragnarok_clientInfo`; browser page errors were empty, and desktop/mobile screenshots were
visually inspected. All 53 focused Python tests, the native UI suite, pinned formatting checks and verification
inventory passed. Tooling tests cover pristine source enforcement, bootstrap/backend integrity,
compiler command/failure propagation, embedding and Make/provenance integration.
Canonical Linux CI and broader browser support remain separate evidence.

Next bounded work: choose UI functionality/layout and add typed browser-facing RPC bindings
as needed, then measure bundle/heap costs before expanding the application.
