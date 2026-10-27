# Consolidated application entry point

Scope: establish `src/ragnarok.nim` as the single native app entry point, with explicit shared
configuration and one optional-service startup/ownership path. Production `make` emits
`build/ragnarok`; all native networking/RPC/UI/telemetry E2E profiles compile that same source.
The existing pinned Nimony 0.6.3 nightly and protocol/dependency pins remain unchanged. This is an
application organization change; existing JAMNP-S, JIP-2/JIP-3 and HTTP contracts remain in force.

## Commands and configuration

The offline [published trace checker](current-stf-trace-command.md) accepts explicit
state configuration, candidate policy, independently anchored Genesis and consecutive
TraceStep files. It validates the full signed transitions on a private ephemeral chain
and reports exact-map agreement; listener, disk, recovery and download controls are
refused for this command.


Commands use the [named CLI](../docs/cli.md). `cli_catalog.nim` owns the shared option
metadata and grouping; `cli_defaults.nim` owns typed defaults and bounds.
`cli_commands.nim` admits strict named inputs and supplies an owned normalized representation to existing bounded handlers.
`cli_help.nim` renders overview and command-specific help from the same catalog.
Long positional command forms are rejected. Networking fields use `--net-*`;
download, trace, devnet and conformance fields use their own descriptive prefixes.
Dedicated conformance budgets retain separate defaults. Syntax inspection precedes
file IO, logging and service startup; explicit help wins over conformance environment activation.

`app/options.nim` parses shared controls atomically. Its output is cleared on any failure;
ports are bounded before narrowing and nonrepeatable controls are unique.
`--with-telemetry` requires `--telemetry-endpoint HOST:PORT --chain FILE`; `--with-rpc`
enables RPC; `--with-ui` enables UI and RPC together. Each enable switch precedes its
related settings in help, and configuration alone never enables a service. Named flags
may be interleaved and value options accept `--name=value`. Existing lifecycle markers,
exit meanings, protocol policies and owned cleanup remain unchanged. Internal component
fixtures may validate normalized configuration through `parseCanonicalOptions`; this is
not a process-input compatibility path. See the CLI guide for examples and migration.

`app/services.nim` centralizes listener startup, bounded chain capture, RPC validation and actual
certificate/socket-based telemetry setup. Its composite owner forbids copying. Both session
shapes borrow these fields only while the owner remains stable; all native callbacks finish
before service retirement. Startup errors close partially opened services, with the caller's
cleanup covering raising filesystem failures. One captured chain snapshot feeds both services.
The exporter adapter reads that exporter's enabled state instead of global CLI flags.

## Build identity

`build/ragnarok --version` prints the application version and full source revision, then
`Nimony <version> <full compiler revision>` and `Built <UTC timestamp>`. Both CLI and
`ragnarok_clientInfo` use immutable constants from `src/version.nim`, generated into ignored `build/build_info.nim` by Make.
RPC `version` is the application label, `revision` its source identity, and `compilerVersion` /
`compilerRevision` identify the validated nightly in `spec/toolchain.json`.
`buildTimestamp` is a UTC ISO 8601 instant compiled into the app, unchanged across runs/requests.
No runtime Git or compiler installation is needed to query a shipped binary.

The checked-in [`src/version.json`](../src/version.json) owns the application version
(currently `development` until release numbering is chosen). Packaging can override it with
`RAGNAROK_VERSION=0.1.0 make`. Source identity is full Git HEAD with `-dirty` when tracked or
untracked source changes exist (ignored build output does not mark it dirty). Archive packaging
can supply `RAGNAROK_REVISION=<source commit>`; without Git or an override it reports `unknown`.
Labels/revision overrides must contain 1–128 printable ASCII characters. Re-run Make after
changing packaging variables; these values are compiled into the binary, never read at runtime.
The timestamp captures build generation time in UTC. Reproducible builds may set the standard
`SOURCE_DATE_EPOCH` variable to Unix seconds; malformed or out-of-range values fail preparation.
`setup` and `check-modules` refresh metadata after verifying the compiler pin, covering production,
unit, compiler-guard and E2E builds without additional manual steps.

## Removed executable paths

`src/quic/peer.nim` is removed; callers compile `src/ragnarok.nim` directly. The mixed CLI/setup
module `src/telemetry/options.nim` is removed: parsing/setup moves under `app/`, observations
under `telemetry/observer.nim`. `tests/native/telemetry_driver.nim` is removed. IPv4/IPv6 collector
reset tests now launch a real app server, verify actual certificate/chain registration and empty
peer status, reset the collector, then authenticate/exchange with another app process. Lost-prefix
and incoming event IDs must still correlate across that reset. Existing gated real-dial reconnect
coverage preserves outgoing attempts that began before reset. No synthetic collector/peer count
or exporter-only executable is introduced into the app.

All QUIC harness defaults resolve server and client roles to `build/ragnarok`; legacy
`build/quic/nim-peer` defaults are removed. E2E overrides select isolated builds of that same
entry point (`ragnarok`, `ragnarok-integration`, `ragnarok-offload`), never a separate client.

The telemetry protocol exporter and compiled browser client remain reusable feature components;
they are not alternative native executable entry points. E2E binaries retain isolated feature
profiles and evidence names so previous positive/negative integration/offload checks remain
required; every profile builds the same app source.

## Completion checks

- `make` and application `--help` plus no-socket parser/IO/mesh/integration/offload selftests.
- Native `app_options` and `telemetry` suites; composite `app_services_copy` lowering rejection.
- Full `make check-e2e` through the consolidated entry point, including real collector resets,
  retained mesh, RPC/UI browser, CLI failures, CE matrix, service/resilience/soak and proof offload.
- Affected Python build/profile/inventory/E2E/collector harness tests, inventory and formatting.
- Build metadata generation/JSON source/provenance tests, native `rpc`, version override and
  fixed `SOURCE_DATE_EPOCH` builds, with live WebSocket identity matched to `--version`.

Local verification on 2026-10-19, macOS arm64, pinned Nimony 0.6.3: production build, `--help`,
all 129 source-module checks, native `app_options`/`telemetry`, composite Services copy rejection,
formatting and inventory passed. The affected Python harness run passed 56 tests; the additional
profile regression passed alongside its existing profile test. A real standalone QUIC exchange
without a binary override launched `build/ragnarok` for both server and client and passed.

The full E2E invocation passed all six selftests and every workload except an existing RPC
startup-error diagnostic assertion. Service-specific diagnostics were restored, then the full
owning RPC workload passed in a focused rerun against the rebuilt app, including browser UI,
development gzip serving, chain/service queries, invalid startup and concurrent QUIC progress.
The successful full-run workloads include real IPv4/IPv6 telemetry resets, CE/control matrices,
retained service/integration, mesh/recovery, endpoint soak, admission and actual proof offload.
No passing unaffected workload was rerun. Evidence remains in `build/ci/ragnarok-entry-*.log`,
`build/tests/e2e/results.json`, `build/tests/app-rpc-final/results.json` and
`build/tests/app-default-launch/results.json`; the initial E2E report retains its original failed
RPC verdict, with the successful corrected rerun recorded separately. Canonical Linux CI remains
separate evidence.

The named CLI rework passed a checked ARC/Clang ThinLTO production build and thirteen
selected native suites: CLI grammar/help/defaults, shared options/logging, disk/layout/migration,
light mode, recovery, download/ancestry controls and fuzz startup/candidate handling. The CLI
ownership witness retained the same occupied bytes across 1000 cycles. Formatting and inventory
checks passed. Real process checks passed the authenticated CE matrix and repeated cold starts,
eight retained mesh rounds with resource/retirement checks, and the RPC plus embedded UI HTTP workload.
The RPC harness now selects networking fields by flag instead of slicing a positional prefix.

Conformance retains the official environment-only launch. `fuzz` activates the built-in policy;
its four `--fuzz-*` environment equivalents also work with explicit-policy commands and override
only supplied fields. Eight public process checks passed environment-only, flags-only, mixed and
invalid-environment overrides, help isolation and graceful socket removal. The container default
passes no arguments so environment activation works in the ordinary image too; nine focused
network/packaging tooling tests passed. Evidence is retained in `build/cli-fuzz-review/`,
`build/cli-live/`, `build/cli-review/` and `build/cli-*.log`. These are local macOS checks;
canonical Linux CI and a container image rebuild remain separate evidence.

Full Python discovery ran 1538 tests with two skips. Its only two errors were the two
browser-mode subcases of the RPC deadline fixture, which still indexed the old positional
timeout. That fixture now finds `--net-timeout-ms`; all three tests in its owning module
passed in a focused rerun. The original full-run failure is preserved in
`build/tests/python/results.json`, with the corrected rerun in
`build/cli-rpc-regression.log`; passing unrelated tests were not repeated.

Next bounded work is to design the long-running node configuration/lifecycle as real import
and consensus become available without adding competing app entry points.


The canonical-only follow-up removes option alias metadata and lookup entirely. Former
spellings are tested as unknown options; all executable callers, component fixtures and
documentation use the advertised names. The checked production build, four selected native
suites (`app_cli`, `app_options`, `light_runtime_options`, `application_services`), 50 focused
Python regressions, changed-source formatting/syntax checks and real canonical RPC,
development UI and telemetry startup passed. The public executable also refused all three
removed spellings. Evidence remains under `build/cli-no-alias-*`.


CI run 40539775711 exposed an accidentally committed `{}` in `rpc-genesis.json`: the
local RPC retention check had been passed the tracked fixture and deliberately rewrote it.
All sixteen native test shards stopped at its pinned checksum, and the application startup
checks consumed the same invalid input. The fixture is restored byte-for-byte. The RPC
harness now copies supplied chains into a unique owned directory before retention mutation;
a regression test checks both the actual launch path and unchanged caller bytes.

The separate JAM Network failure was its obsolete unknown-command diagnostic expectation.
Its negative controls now require the exact public CLI rejection before listener startup;
missing conformance environment fields still require `FUZZ_START_FAILED`.

The repair passed all static fixture checks across 978 suites (54 unique files), native
`application_checkpoint_transfer` and `disk_chain`, thirteen focused RPC/network tooling
tests, and the previously failed live RPC/browser, development UI, canonical-state,
checkpoint-import and JAM Network socket checks. The live replay verifies the tracked
fixture hash after every workload. Evidence is in `build/cli-ci-*`; these local results do
not replace the new Linux CI run.
