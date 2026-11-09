# Static UI server

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
Linux amd64/arm64 and macOS arm64. It is downloaded directly from official platform packages into
`build/ui-minifier/`; no Node, npm install or Go compiler is needed for application builds.
`tools/setup_minifier.py` provisions it through Make only when requested. Transform mode
minifies generated `app.js` and static `.js`/`.css` assets before gzip/embedding, preserving
separate asset names, URLs and script globals. HTML and other assets retain their original bytes.
Parser errors fail the build before replacing staged assets; no unminified release fallback is used.
Both modes retain deterministic gzip metadata, and switching modes replaces the staged/embedded
bytes without changing public filenames. Browser verification in CI exercises minified output.

Linux ARM64 uses the official `@esbuild/linux-arm64` package at the same pinned version.
Both `aarch64` and `arm64` host spellings select its archive and executable checksums.
This closes the ordinary minified `make setup`/`make unit` failure on ARM CI; it does not
disable minification or skip setup prerequisites. Host-selection coverage follows every
supported application-toolchain host and alias, so a new native platform requires matching
minifier support. The package SHA-512 registry integrity and archive/executable SHA-256 values
were independently checked. Native Linux ARM64 [qualification](https://github.com/jacogr/ragnarok/actions/runs/42459287541)
passed on 2026-11-08: ordinary minified `make unit SUITE=pvm_artifact`, cached native tool reuse,
production JS/CSS/gzip byte checks and malformed-JavaScript refusal all succeeded.

Content-coding negotiation follows [RFC 9110 §12.5.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-12.5.3).
The UI requires explicit gzip acceptance even when the request omits Accept-Encoding.

The [UI source guide](../src/ui/README.md) covers activation and the
[listener](../src/ui/server.nim) owns HTTP delivery and development root rules.
The [WebSocket server](../src/rpc/server.nim) owns browser Origin checks.

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
