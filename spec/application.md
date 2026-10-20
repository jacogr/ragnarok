# Consolidated application entry point

Scope: establish `src/ragnarok.nim` as the single native app entry point, with explicit shared
configuration and one optional-service startup/ownership path. Production `make` emits
`build/ragnarok`; all native networking/RPC/UI/telemetry E2E profiles compile that same source.
The existing pinned Nimony 0.6.3 nightly and protocol/dependency pins remain unchanged. This is an
application organization change; existing JAMNP-S, JIP-2/JIP-3 and HTTP contracts remain in force.

## Commands and configuration

Existing `server`, `client`, `mesh`, bounded fixture modes and no-socket selftest flags retain
arguments, exit codes, lifecycle markers and cleanup. `build/ragnarok --help` lists the command
shapes and service flags. These commands are development workloads, not a complete node loop.

`app/options.nim` parses command-line input once into private owned configuration. Its output is
cleared on any failure; ports are bounded before narrowing and all trailing controls are unique.
`--with-telemetry` requires explicit `--telemetry HOST:PORT --chain FILE`; `--with-rpc` enables
RPC; `--with-ui` enables UI and RPC together. Existing default ports remain 19800/8888, with
`--rpc-port`, `--ui-port` and `--dev-ui-dir` configuring enabled services. Configuration alone
never enables a listener/exporter. UI/RPC port collisions, malformed controls and service flags
on nonnetwork commands fail before startup. No service module re-reads process arguments.

`app/services.nim` centralizes listener startup, bounded chain capture, RPC validation and actual
certificate/socket-based telemetry setup. Its composite owner forbids copying. Both session
shapes borrow these fields only while the owner remains stable; all native callbacks finish
before service retirement. Startup errors close partially opened services, with the caller's
cleanup covering raising filesystem failures. One captured chain snapshot feeds both services.
The exporter adapter reads that exporter's enabled state instead of global CLI flags.

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

Next bounded work is
to design the long-running node configuration/lifecycle as real import and consensus become
available, replacing proof-workload positional controls without adding competing app entry points.
