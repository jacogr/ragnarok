# Explicit LSQUIC adapters

Both QUIC candidates use small project-maintained adapters over the same pinned
LSQUIC/BoringSSL build and the same C ABI. No external Nim networking package
or dependency source patch is required. Nim remains on the pinned 2.2.12 compiler
with ARC; Odin's compiler pin is unchanged.

| Component | Nim | Odin |
| --- | --- | --- |
| Transport/TLS engine | Shared pinned native build | Shared pinned native build |
| C ABI and certificate extraction | `transport_bridge` / `cert_fields` | Same |
| Readiness/completion backend | Standard `selectors`, nonblocking POSIX UDP | `core:nbio`, nonblocking UDP |
| Native adapter/policy code | `nim/quic/transport.nim`, `peer.nim` | `odin/quic/peer.odin` |
| JAM identity and CE 143 framing | Implemented in Nim | Implemented in Odin |
| Application buffers | ARC-owned bounded sequences | Explicit bounded allocations |
| Callback ownership | Stack peer/transport until synchronous native close | Stack peer until I/O cancellation drain and native close |

The C bridge contains engine/TLS ABI details and raw stream operations. It has
no JAM SAN formula, expected-key comparison, CE selector, E4 message parser,
fixture lookup or response validation. Those remain independent native-language
implementations. Sharing this narrow ABI avoids comparing a patched third-party
wrapper with a project-owned adapter.

## Nim ownership and I/O

The adapter creates a nonblocking loopback UDP socket and registers read
readiness with a standard selector: kqueue on macOS, epoll on Linux. The same
thread waits until UDP readiness or a bounded LSQUIC deadline, drains at most
64 datagrams per cycle, and progresses transport callbacks. Stream-local
application deadlines share that thread. No worker, timer thread or thread per
stream is created.

The C user pointer borrows a stable `Transport` within a stable stack `Peer`.
A live peer/transport owner must not be copied, moved or accessed concurrently
while the C bridge borrows its address. Static C callbacks forward identity/stream events to that peer and use the
adapter's owned receive buffer. UDP receives and sends are synchronous,
nonblocking syscalls; borrowed packet/DER pointers never survive their call.
C callback signatures preserve the bridge's read-only byte types and calling
convention, checked by the generated C compilation against its headers.

Each stream owns bounded receive/write buffers through native close. Partial
reads/writes retain lengths and offsets; would-block stays distinct from FIN
and reset. Closing/resetting a stream settles its terminal count once, and the
final close callback releases its buffers through ARC. Neither streams nor
selectors hold a closure/reference back to the peer, so there is no async-frame
or timer closure cycle to patch.

Shutdown marks the peer/adapter as stopping, unregisters UDP readiness, closes
the selector/socket and destroys the native transport while both stack owners
are still alive. Native destruction delivers final stream-close callbacks
synchronously. No queued Nim receive/timer callback remains to drain. Setup
failure also retires all previously created resources. The selector teardown
selftest covers 256 idle/ready registration retirements on the actual backend.

## Dependency and build migration

[The pins](../spec/quic-proof-pins.json) now have schema version 2 and exactly
four native source entries:

- `iftech/lsquic`, `fd0d75c6584eb4c20dfa8b4b865bfe3daf5a2e52`.
- `vacp2p/boringssl`, `88341070936d28e08f82db1326c73d67962cd043`.
- LSQUIC's pinned ls-qpack and ls-hpack submodules.

These are the same native revisions used by the earlier proof. The engine/TLS
repositories are the existing forks; this round changes the language adapters
and dependency graph, not the native revision selection.

Chronos, nim-lsquic and their Nim package closure are removed from the fetched
and compiled dependency set. The three local source patches and their build
transformations are removed; the runner asserts that the patch list is empty.
The compiler invokes no dependency `--path` or global Nimble installation.

Fresh native archives are kept under `build/quic/native-sources`; native CMake
builds are `native-bssl` and `native-lsquic`, and the Nim cache is
`nim-adapter-cache`. This keeps old modified wrapper trees and caches out of the
new build. Old ignored `build/quic/sources`, `bssl`, `lsquic` and `nimcache`
directories are unused and may be removed when their historical diagnostics
are no longer needed. They are not consulted by either adapter.

Run [the proof](quic-proof.md) and [the soak](quic-soak.md) with the existing
commands. The Linux workflow builds the same adapters from fresh native sources
and runs both native I/O selftests. See [the verification report](../results/quic-adapters.md).

## Limits

This is a bounded IPv4 loopback proof and finite lifecycle regression. The
adapters are explicitly ours to maintain; passing these tests does not certify
all LSQUIC paths or a full reusable client transport. Persistent-engine
multi-peer service, IPv6, independent JAM peers and deeper C/TLS allocation
instrumentation remain M3 work. The maintainer reported on 2026-10-14 that Linux CI passes for this adapter
revision. Earlier Linux reports still describe the older wrapper implementation.
