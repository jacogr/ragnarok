# Application entry and services

[Design overview](../design.md). The [application contract](../../spec/application.md) records
scope, verification and remaining work.

`src/ragnarok.nim` is the sole native application entry point for production and E2E builds.
It reads process arguments once, parses an owned `app/options.Options`, and dispatches bounded
peer/mesh lifecycles, explicit bounded child downloads and no-socket selftests. Configuration is passed
explicitly; transport, telemetry, RPC and UI modules do not inspect command-line globals. The current commands remain
bounded development entry points with supported child admission, execution and publication.
The long-running node, complete validation, consensus and validator lifecycles remain open.

`app/options.nim` validates trailing service switches/configuration atomically. Private fields
have read-only accessors; a failed/default result cannot start a session. Endpoint configuration
alone does not enable services, and UI implies RPC. Canonical state requires `--with-state` and
a chain file. Mutation budgets default to 1,000 writes and 100,000 value bytes, with independent
overrides. State activation does not enable listeners. Repeated parses have independent ownership.

`app/services.nim` owns one non-copyable aggregate of RPC, UI, telemetry and an optional canonical application chain. It captures one
bounded chain-file snapshot for RPC parameter/genesis setup and telemetry registration, starts
the listeners, then configures telemetry from the actual bound transport/certificate. Both peer
shapes call this same startup path. Individual native callbacks borrow fields of its stable stack
owner; every transport/dispatcher ends its borrows before aggregate cleanup. Explicit close and
destruction handle partial startup and disabled fields without retaining descriptors or strings.

Complete-state services select memory by default or an explicit disk backend/path. Disk startup
validates the configured genesis/profile identity and restores the bounded local view before RPC
starts. Queued disk adoption has a Publishing stage: one native worker owns exclusive graph access
while the host polls scalar state, then the host installs the confirmed durable successor and resumes
RPC. Shutdown joins before input/canonical retirement. External checkpoint imports keep their own
trust boundary and create a fresh disk path exclusively. See [disk operation](../disk-storage.md)
and [the feature contract](../../spec/disk-state-store.md).

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
complete finalized success. The download dispatcher supplies network acquisition and managed
asynchronous preparation for this supported path. See [the handoff contract](../../spec/application-chain.md).

`app/download_command.nim` owns stable Services and dispatcher lifetimes for the explicit
`download` command. `app/download_policy.nim` loads a bounded, complete versioned policy file;
no gas, stage, retry or network budget is inferred. Up to sixteen explicitly pinned loopback peers
supply a finite sequence of up to 64 children, default one, with asynchronous preparation outside
callbacks and success only after actual deferred adoption. The authenticated catalog remains
stable across children. Explicit session rearming requires consumed adoption and retired
stream/input/worker leases; final shutdown joins before outer aliases retire. One shared deadline
and per-child stage/retry budgets preserve confirmed partial progress. See the
[startup contract](../../spec/application-download-startup.md) and
[progress contract](../../spec/application-download-progress.md) for configuration and bounds.

Explicit [ancestor discovery](../../spec/state-ancestor-context.md) can retain a
prepared exact-parent report prefix while missing lookup context is acquired.
Worker collection ends canonical/RPC exclusion before child connections drain;
resumption retains the original input generation and attempt deadline, then grants
a fresh managed lease to complete lookup checks and execute. Fetched historical
headers never become canonical history or complete historical state.

`app/preparation_worker.nim` provides one reusable native execution thread and one outstanding
input lease. Services manages that lease by pausing RPC before submission and guarding canonical
access until collection or joined shutdown. UI and unrelated QUIC work remain available; RPC
sockets and queues resume afterward. Existing external ARC aliases must remain untouched throughout
the lease. The worker returns the existing opaque finalized certificate for explicit host adoption.
The download dispatcher enters Preparing only after native stream retirement, polls endpoints during
execution, and retains cancelled input until collection or joined close. Successful collection queues
only a genuine certificate for a later adoption turn. The [worker integration contract](../../spec/application-download-worker.md)
records deadlines and remaining load/persistence work; the [managed lease](../../spec/application-preparation-lease.md)
records the exclusion boundary.

`telemetry/observer.nim` translates transport events to the exporter without CLI knowledge.
Protocol component implementations, the browser program and component tests remain separate
modules. Process-level networking/collector checks launch the application; there is no legacy
peer CLI wrapper or standalone synthetic telemetry driver. E2E feature profiles compile this
same entry point with their existing integration/offload definitions and isolated caches.

`src/version.nim` shares immutable build identity between `--version` and RPC client information.
Make reads `src/version.json` and generates the source revision, validated compiler pin and UTC
build timestamp before compilation. Shipped binaries query no external version files, Git
repository or compiler process.

Explicit checkpoint recovery can seed Services from an independently trusted sealed
head and complete map, with one retained head and finality unset. Full chain profile
agreement is checked before listeners open; the selected checkpoint is never its
own trust source. See [the recovery contract](../../spec/application-recovery.md).
