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


The [CLI guide](../docs/cli.md) describes public commands and setup.
[Named admission](../src/app/cli/commands.nim) and [options](../src/app/options.nim)
own validation and enable rules. [Services](../src/app/services.nim) owns startup
and cleanup for optional listeners and configured state.

## Build identity

The [build identity module](../src/version.nim) owns the immutable CLI and RPC metadata
interface. Run `build/ragnarok --version` to inspect a built executable.

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


CI job 122337219655 exposed one remaining caller dependency on the old RPC mutation:
`parameter_checks` expected its chain to have become `{}` after the live workload. It now
writes that incomplete configuration explicitly before its refusal assertion. A nonmutating
live-check stub verifies the owning parameter-check function still constructs all five
negative startup attempts independently. All five RPC unit tests and the complete owning
RPC E2E workload passed locally, including browser and development UI, configured parameters,
shared telemetry, service queries and invalid startup. The tracked genesis fixture stayed
unchanged. Evidence is in `build/cli-ci-rpc-parameter-unit.log` and
`build/cli-ci-rpc-complete/`; a fresh full Linux run is requested separately.


## Foreground startup defaults

The CLI defaults increment makes `ragnarok server` a usable foreground development listener:
UDP 34100, a generated persistent Ed25519 TLS identity under `--data-dir/network`, isolated
development ALPN, and no deadline until interrupted. Other workload modes retain their finite
10-second default. Optional UI/RPC/MCP use loopback ports 8418/9418/14141; the browser imports the
shared RPC default. `docs/cli.md` lists every listener and remote endpoint port selection.
Port, TLS paths, ALPN, deadline and workload remain independently overridable.
The standard transport still owns protocol checks; this does not implement a production validator.

Process-input normalization supplies mode/layout-specific disk paths, chooses paged layout for
light disk state, resolves a default private management socket, and selects `./chain.json` for
state/telemetry when omitted. Component parsing remains a strict already-normalized boundary.
Neither paths nor configuration controls activate services. Full/light database namespaces and
physical schemas remain separate. Remote identities, light authority and execution policies are
not invented. Startup creates selected parent directories only after syntax validation.

[Startup](../src/app/startup.nim) owns first-use identity publication. The
[entry point](../src/ragnarok.nim) retires services and transport through ordinary
cleanup after a foreground signal.

Completion checks cover pure defaults/overrides and refusal, default identity creation/reuse and
partial-bundle refusal, a real bare server with graceful signal shutdown, a pinned client exchange,
help without filesystem effects, disk startup/restart and representative existing workload checks.


Local completion evidence: the checked production build, six selected native suites
(`app_cli`, `startup_identity`, `app_options`, `disk_storage_options`,
`light_runtime_options`, `quic_protocol`), 52 focused transport/RPC/telemetry Python tests,
and 19 E2E-plan/CI-scheduling tests passed. The registered startup E2E workload passed nine
checks, including real successive pinned clients, signal/deadline cleanup and journal,
managed and paged database creation/restart, plus all three loopback listener defaults and
immediate UI/RPC restart after client use. UI/RPC listeners set SO_REUSEADDR, matching MCP. The original authenticated transport matrix,
repeated cold starts and CLI refusal controls also passed. Inventory and pinned formatting
passed; tracked fixture inputs are unchanged. Evidence is in `build/startup-defaults-*`,
`build/startup-owned-e2e/` and `build/startup-transport/`.

The permanent startup workload is part of the existing testnet E2E group. Its artifact rules
retain logs and result summaries, excluding the generated keys and certificates. Default
`data/` runtime material is excluded from Git and Docker build contexts. These are local
macOS results; Linux CI remains separate evidence.

After incorporating master’s MCP work through `b841e82b`, the production build, `app_cli`,
`app_options`, `ui` and `rpc` native suites, inventory, changed-source formatting, six transport
harness tests and five E2E-plan tests passed again. The nine startup checks and CLI refusal
controls passed against that build. The real browser workload also passed, including its initial
shared-default RPC endpoint and user-selected endpoint override.

Review follow-up: persistent listeners settle malformed, cancelled and timed-out requests as
stream-local rejections, independently of soak fixture selection. The shared stream lifecycle
tick now applies the existing incomplete-request deadline to ordinary listeners and drives the
standalone cancellation workload. Native callback/engine errors remain fatal; one-shot exchanges
retain their existing failure verdicts. Selftests check single settlement, later healthy work,
one-shot failure and preservation of an existing fatal flag. The live startup workload now has
ten checks: five malformed request modes, missing-FIN timeout and authenticated cancellation each
leave the listener available for subsequent healthy clients. Production build and selftests passed;
The original 16-case authenticated transport matrix, 12 repeated cold starts and CLI refusal
controls passed as well. Evidence is in `build/startup-isolation-*`.
