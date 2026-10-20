# Static UI server

Append `--with-ui` to an existing `build/ragnarok server`, `client` or `mesh` command.
The independent HTTP listener serves assets embedded in the client binary at
`http://127.0.0.1:8888/`; `--ui-port NUMBER` changes the port (decimal 1–65535).
It requires no runtime asset directory, extraction or working-directory convention.
The embedded browser prototype is compiled from Nimony; see [the browser contract](ui-browser.md).

For development, append `--dev-ui-dir /path/to/static` alongside `--with-ui`.
This replaces the embedded asset source with precompressed `.gz` files from that directory;
rebuilt files are visible on the next request. Use `build/ui` after `make ui-assets`.
Missing development files return 404 without falling back to the bundle.
The old `--ui-dir` spelling is removed. The development flag alone never starts the listener.

`make ui-assets` compiles `src/ui/client.nim` to JavaScript, combines it with the static
assets in `src/ui/static/`, optionally minifies JS/CSS, gzips each asset into `<filename>.<ext>.gz` under `build/ui/`
and generates `build/ui_assets.nim`, containing immutable sorted URL paths and byte-exact asset constants.
Make runs this step before production builds, native verification and source module checks.
Only gzip bytes are staged and embedded; original bytes are build-time inputs. Gzip metadata
has no timestamp or filename, so identical inputs rebuild identically. The generated source
changes when asset paths or bytes change, so the compiler sees asset edits.
Generated outputs remain under ignored `build/`; `make clean` removes them. Asset sources are
part of runtime verification provenance. The browser client has no frontend framework or
JavaScript package dependency; Node/Playwright are used only for browser verification.

Local builds retain original JS/CSS bytes by default and do not provision a minifier.
CI sets `UI_MINIFY=1`; Make also defaults to minification for `CI=true` or `CI=1`.
Use `make UI_MINIFY=1 ui-assets` (or `make UI_MINIFY=1`) to opt in locally;
`UI_MINIFY=0` explicitly selects readable assets. Other values fail the build.

Minified builds use the standalone native [esbuild](https://esbuild.github.io/getting-started/#download-a-build)
executable pinned in `spec/ui-tools.json`, with archive and executable SHA-256 verification for
Linux amd64 and macOS arm64. It is downloaded directly from official platform packages into
`build/ui-minifier/`; no Node, npm install or Go compiler is needed for application builds.
`tools/setup_minifier.py` provisions it through Make only when requested. Transform mode
minifies generated `app.js` and static `.js`/`.css` assets before gzip/embedding, preserving
separate asset names, URLs and script globals. HTML and other assets retain their original bytes.
Parser errors fail the build before replacing staged assets; no unminified release fallback is used.
Both modes retain deterministic gzip metadata, and switching modes replaces the staged/embedded
bytes without changing public filenames. Browser verification in CI exercises minified output.

`--with-ui` also enables the WebSocket RPC listener, default `ws://127.0.0.1:19800/`;
`--rpc-port NUMBER` selects its port. `--with-rpc` enables RPC independently.
UI and RPC ports must differ. `--with-telemetry` independently enables telemetry and
requires both `--telemetry HOST:PORT` and `--chain FILE`. Endpoint configuration alone
never enables a service. Duplicate switches, malformed ports and enabled listener/root
failures fail startup. Controls are trailing and may be ordered freely.

RPC browser access accepts only `http://127.0.0.1:<ui-port>` and
`http://localhost:<ui-port>` when UI is enabled (port 80 uses the standard origin without an explicit port). The WebSocket handshake validates Origin
and returns an exact `Access-Control-Allow-Origin` plus `Vary: Origin`; RFC 6455 connections
do not use an HTTP OPTIONS preflight. Other browser origins, null origins and duplicates
are rejected. Nonbrowser RPC clients may omit Origin. RPC remains WebSocket only.

The HTTP listener supports GET/HEAD, query strings, percent-encoded paths and `index.html`
for directory targets ending in `/`. Common web assets have explicit MIME types. File responses have Content-Length,
Connection: close and X-Content-Type-Options: nosniff.
Requests retain normal URLs: `/app.js` serves `app.js.gz` with the original JavaScript MIME
type, `Content-Encoding: gzip`, compressed `Content-Length` and `Vary: Accept-Encoding`.
HEAD returns the same metadata without a body. The server performs no compression or
uncompressed fallback. Requests must advertise gzip acceptance; missing/empty Accept-Encoding,
unsupported codings and explicit `gzip;q=0` exclusions return 406. Quality weights, wildcard
acceptance and explicit overrides follow [HTTP content-coding negotiation](https://www.rfc-editor.org/rfc/rfc9110.html#section-12.5.3),
with this service deliberately requiring opt-in even when the header is absent.
Missing gzip files return 404 even if the original file exists; malformed requests/traversal
return 400, and other methods return 405. There is no directory listing, SPA fallback, write endpoint or request body support.
Development paths open relative to the pinned root descriptor without following symlinks;
only regular files can be served. Select a directory containing only public development UI assets.
Release requests look up immutable embedded paths and send their bytes in bounded chunks.

Both peer shapes own one non-copyable UI server and service it on the existing dispatcher.
Eight connections, 4096-byte headers, 16384-byte file chunks, one accept/read/write per
slot per tick and an absolute five-second request deadline bound work and memory. Development file IO
uses bounded regular-file reads on the dispatcher; slow filesystem storage can delay a turn.
Growing files stop at the initial length; truncation closes an incomplete response.
All sockets/root/file descriptors retire on failure, shutdown or ARC destruction.

Verification: `make unit SUITE=ui`, `make unit SUITE=rpc`, `make check-inventory` and the
RPC E2E workload cover paths, symlink rejection, HTTP metadata/errors, multi-chunk streaming,
UI-implied RPC, browser Origin controls, embedded serving from unrelated working directories,
and live development edits without embedded fallback. Build-tool tests cover deterministic output,
binary/empty assets, stale-file removal and invalid source rejection. The UI ownership rejection fixture guards copying.
The browser prototype calls `ragnarok_clientInfo`; its scope and evidence are recorded separately.

Initial disk-server verification on 2026-10-19 (macOS arm64, pinned Nimony 0.6.3): production `make`,
UI/RPC native suites, UI composite ownership rejection, 68 affected Python harness tests,
format/check and inventory passed. Live checks against the production peer passed nine HTTP
cases (including a 256 KiB streamed file), UI-origin WebSocket RPC, UI-implied RPC, disabled
services with occupied configured ports, independent RPC, shared telemetry configuration,
37 malformed CLI cases, concurrent QUIC exchanges and clean service shutdown. Evidence is
under `build/ci/ui-*.log` and `build/tests/ui-e2e/results.json`. Canonical Linux CI remains separate.

Embedded/default revision verified locally on 2026-10-19 with the same pinned compiler:
production build, UI native suite, ownership rejection, 31 build/harness tests, the updated
binary/empty-asset generator tests, formatting and inventory passed. Production-peer checks
passed embedded serving from an unrelated empty working directory without extraction,
development edits/missing-file isolation, shared RPC/telemetry startup, 38 malformed CLI
controls, concurrent QUIC progress and clean shutdown. Evidence: `build/ci/ui-embedded-*.log`
and `build/tests/ui-e2e/results.json`. Canonical Linux CI remains separate.

Static asset relocation to `src/ui/static/`: the generated embedded manifest is byte-identical;
14 affected tooling/provenance/RPC-harness tests and inventory passed locally.

Gzip-only revision verified locally on 2026-10-19 (macOS arm64, same pinned compiler):
production build, native UI suite, 51 affected Python harness tests, deterministic gzip/prefix-path
generator tests, formatting and inventory passed. `make check-ui` executed the page from gzip
HTML/CSS/JavaScript with correct encoding, MIME, compressed length and Vary headers. The live
development workload passed a multi-chunk incompressible gzip file, GET/HEAD metadata, rejected
encoding cases, missing-sidecar isolation despite an original file, symlink rejection, concurrent
RPC/QUIC progress and clean shutdown. No runtime compression library or identity asset is added.
Evidence: `build/ci/ui-gzip-*.log`, `build/tests/ui-browser/peer/browser/results.json` and
`build/tests/ui-gzip-dev/results.json`. Canonical Linux CI remains separate.

Native minification validation on 2026-10-20 (macOS arm64, pinned Nimony 0.6.3 and esbuild
0.28.2): minified production build and real-browser/WebSocket RPC workload passed, including
DOM updates, refresh, disconnect/reconnect, mobile layout, gzip serving and concurrent QUIC
progress. The default production build then passed and restored original JS/CSS bytes.
Focused asset/setup/Make/provenance checks passed (29 Python tests), as did verification inventory
and whitespace checks. No Nim source changed, so native source formatting was unchanged.
For this prototype, app.js gzip shrank from 27,775 to 12,731 bytes; style.css gzip shrank from
1,488 to 1,285 bytes. Evidence is under `build/ci/ui-minify-*.log` and
`build/ci/ui-minify-sizes.json`; canonical Linux CI remains separate verification.
