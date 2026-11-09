# Nimony browser prototype

The [browser console](../src/ui/client.nim) owns presentation and the
[browser RPC client](../src/ui/rpc.nim) owns calls and subscription lifetimes.
See the [UI source guide](../src/ui/README.md) for setup.

## Compiler and build

`spec/toolchain.json` remains pinned to Nimony 0.6.3 at
`29b96c31be1647665e5c57f2788e1c8cfeeddc9c`. Its nightly package omits `jorogumo`.
`spec/web-toolchain.json` records SHA-256-verified source archives for that same compiler and
its own `src/nativenif.commit` dependency, `ec471df7e83d6938bd482b4f4dd5c8d2ef210c1f`.
`make web-toolchain` restores those pristine sources as siblings under `build/web-toolchain/`
and builds the missing backend. Compiler updates keep both source pins in step; sources remain
pristine and no private-runtime hook is used.
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

For live development use `--with-ui --ui-dev-dir build/ui` and rerun `make ui-assets` after
source edits. Development overrides replace the complete asset directory, so HTML/CSS alone
without generated `app.js.gz` do not run the application. Every asset is precompressed at build
time; the server requires gzip acceptance and never serves identity bytes.
Release binaries need no runtime files.

## Verification

`make check-ui` builds the production peer and uses a real headless browser against its HTTP
and WebSocket listeners. It verifies DOM values, initial/refresh requests, disconnect/reconnect,
invalid URL handling, desktop/mobile layout without horizontal overflow, no uncaught page errors,
gzip response headers for HTML/CSS/JavaScript, overlapping Refresh calls, and that the visible
console sends only `ragnarok_clientInfo`. The isolated compiled RPC fixture additionally runs
two real `subscribeBestBlock` streams alongside one-shot calls against the native server
using the frozen genesis fixture. Its deterministic browser peer verifies out-of-order/duplicate
replies, uint32 subscription IDs, interleaved updates, unsubscribe errors/ACKs, terminal updates,
independent deadlines, reentrant callbacks, capacity backpressure and reconnect cleanup. The same browser check runs in the owning RPC workload under `make check-e2e`; raw WebSocket/QUIC checks remain there.
Screenshots, wire requests and diagnostics are retained under
`build/tests/ui-browser/peer/browser/` locally or `build/tests/e2e/rpc/browser/` in E2E.

Browser verification requires Node 20+ and npm. `make browser-tools` compiles `tests/browser/rpc_client.nim` with the same pinned backend and
minification selection as production, without embedding it in shipped assets. It installs exact locked
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

Browser RPC multiplexing validated locally on 2026-10-20 (macOS arm64, pinned Nimony 0.6.3):
default and minified browser runs passed. The console issued overlapping Refresh calls; an
isolated fixture opened two actual subscribeBestBlock streams and interleaved clientInfo and
unsubscribe calls against the native server's frozen genesis view. The controlled peer passed
out-of-order/duplicate replies, colliding request/subscription numbers, full uint32 selectors,
independent deadlines, shared-handler IDs on local failures, reentrant scheduling/reconnect,
capacity/backpressure, terminal notifications and stale-event cleanup. No subscription controls
were added to the console. Asset/Make/provenance tests, inventory and pinned formatting passed.
Evidence: `build/ci/ui-rpc-*.log` and the `rpc-client.json` / `rpc-live-subscriptions.json` browser
artifacts under `build/tests/ui-browser/peer/browser/`. Linux CI remains separate verification.
