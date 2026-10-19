# Static UI server

Append `--with-ui` to an existing `build/ragnarok server`, `client` or `mesh` command.
The independent HTTP listener serves assets embedded in the client binary at
`http://127.0.0.1:8888/`; `--ui-port NUMBER` changes the port (decimal 1–65535).
It requires no runtime asset directory, extraction or working-directory convention.
The checked-in index remains a placeholder for the future UI.

For development, append `--dev-ui-dir /path/to/static` alongside `--with-ui`.
This replaces the embedded asset source with files from that directory; edits are visible
on the next request. Missing development files return 404 without falling back to the bundle.
The old `--ui-dir` spelling is removed. The development flag alone never starts the listener.

`make ui-assets` stages the static distribution from `src/ui/static/` into `build/ui/` and
generates `build/ui_assets.nim`, containing immutable sorted URL paths and byte-exact asset constants.
Make runs this step before production builds, native verification and source module checks.
The generated source changes when asset paths or bytes change, so the compiler sees asset edits.
Generated outputs remain under ignored `build/`; `make clean` removes them. Asset sources are
part of runtime verification provenance. A future frontend build can supply the distribution;
no frontend framework or JavaScript dependency is introduced for the current placeholder.

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
Missing files return 404, malformed requests/traversal return 400, and other methods return
405. There is no directory listing, SPA fallback, write endpoint or request body support.
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
Future work: replace the placeholder with UI assets that call the existing RPC methods.

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
