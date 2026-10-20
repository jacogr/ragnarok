# Application entry and services

[Design overview](../design.md). The [application contract](../../spec/application.md) records
scope, verification and remaining work.

`src/ragnarok.nim` is the sole native application entry point for production and E2E builds.
It reads process arguments once, parses an owned `app/options.Options`, and dispatches bounded
peer/mesh lifecycles, explicit one-child downloads and no-socket selftests. Configuration is passed
explicitly; transport, telemetry, RPC and UI modules do not inspect command-line globals. The current commands remain
the development proof peer, providing the future client entry point without claiming full node
execution, block import, consensus or validator operation.

`app/options.nim` validates trailing service switches/configuration atomically. Private fields
have read-only accessors; a failed/default result cannot start a session. Endpoint configuration
alone does not enable services, and UI implies RPC. Canonical state requires `--with-state`,
a chain file and both explicit mutation budgets; it does not enable listeners. Repeated parses
have independent ownership.

`app/services.nim` owns one non-copyable aggregate of RPC, UI, telemetry and an optional canonical application chain. It captures one
bounded chain-file snapshot for RPC parameter/genesis setup and telemetry registration, starts
the listeners, then configures telemetry from the actual bound transport/certificate. Both peer
shapes call this same startup path. Individual native callbacks borrow fields of its stable stack
owner; every transport/dispatcher ends its borrows before aggregate cleanup. Explicit close and
destruction handle partial startup and disabled fields without retaining descriptors or strings.

`app/chain.nim` owns the canonical complete state and selected history independently of
optional listener lifetime. It inherits an explicitly supplied head's store policy and accepts
opaque finalized successors through state-owned adoption. Enabled RPC joins only an identical
retained history, state ownership, parameter tuple and finality selection; subscriber work
starts after all handles agree. Configured seed provisioning requires an explicit complete-state
policy. Services can opt into that policy, share the exact seed with RPC and retire
canonical ownership on close/restart. Both executable peer shapes select this path from
validated state options. `app/handoff.nim` retains one finalized candidate or one unacknowledged
adoption outcome; both peer loops attempt at most one candidate per service tick before RPC/UI
work. Producers acknowledge completion explicitly, and shutdown retires either alternative.
`app/candidate.nim` prepares from an owned block through existing admission and PVM stages,
using the retained head's parent/map/parameters and explicit stage policies, then queues only
complete finalized success. Network acquisition and asynchronous execution scheduling remain
application integration work. See [the handoff contract](../../spec/application-chain.md).

`app/download_command.nim` owns stable Services and dispatcher lifetimes for the explicit
`download` command. `app/download_policy.nim` loads a bounded, complete versioned policy file;
no gas, stage, retry or network budget is inferred. One pinned loopback peer may supply one
child, with preparation outside callbacks and success only after actual deferred adoption.
The [startup contract](../../spec/application-download-startup.md) records the command,
configuration schema and remaining production boundaries.

`app/preparation_worker.nim` provides one reusable native execution thread and one outstanding
input lease. Plain ARC requires every alias of the captured chain/input graph to remain untouched
until collection or joined shutdown. It returns the existing opaque finalized certificate for host
adoption. Concurrent Services/RPC dispatcher integration still requires ownership isolation; see
the [exclusive worker contract](../../spec/application-preparation-worker.md).

`telemetry/observer.nim` translates transport events to the exporter without CLI knowledge.
Protocol component implementations, the browser program and component tests remain separate
modules. Process-level networking/collector checks launch the application; there is no legacy
peer CLI wrapper or standalone synthetic telemetry driver. E2E feature profiles compile this
same entry point with their existing integration/offload definitions and isolated caches.

`src/version.nim` shares immutable build identity between `--version` and RPC client information.
Make reads `src/version.json` and generates the source revision, validated compiler pin and UTC
build timestamp before compilation. Shipped binaries query no external version files, Git
repository or compiler process.
