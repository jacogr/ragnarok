# Current native download routing

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive, with the existing
pinned CE128 wire and TLS identity contracts unchanged. No runtime/dependency/protocol pin changes.

`CurrentDownloadStream`, `CurrentDownloadSession` and `CurrentDownloadPeers` provide distinct
native routing for CurrentBlockDownload. Their nominal input, generation and attempt types do not
accept legacy receivers or certificates. The existing scalar peer scheduler still governs bounded
round-robin selection, cooldown and actual terminal host acknowledgment.

One fixed-address peer catalog pins caller-selected TLS public identities before routing a locally
opened stream to an exact current attempt. Bounded read/write work, partial offsets, total transfer
deadlines, native handle plus receiver/generation matching, unexpected/reset events and actual close
retain the qualified routing lifecycle. Callbacks copy only exact framed bytes; they never decode,
hash, execute or adopt. Retiring a peer closes its engine and flushes actual stream-close callbacks
before removing the borrowed session/attempt association. Cancellation/deadline alone is not close.

A session cannot grant managed preparation or discard the receiver until the native stream barrier
has retired. Explicit current preparation, exact collection, original-history ancestry resumption,
queued status and host-reported terminal outcome remain separate turns. Collection queues only a
real current update; Services installation and acknowledgment still determine actual adoption.
There is no synchronous preparation entry point. Defaults and unrelated selected errors expose no
successful token, peer result or nested failure payload. All three native composites explicitly
reject duplication independently of nested ownership hooks and hide mutable callback state.

The native suite supplies independent actual wire responders and both freshly generated TLS
identities. It covers bounded normal and byte-at-a-time request/response work, pinned identity
rejection, empty/oversized replies, exact no-FIN expiry, native-close preparation/discard barriers,
zero primitive hashing during callbacks, signed current worker execution and complete independent
state roots, unchanged parent after collection and deferred actual adoption. Run
`make unit SUITE=pvm_current_download_native`. Source-owned privacy, legacy-receiver nominal,
actual composite duplication and runtime extraction guards remain required. Existing legacy routing
and dependency trees are unchanged; their prior evidence remains applicable.

The production dispatcher and command still use legacy routing until subsequent current layers
explicitly select this adapter. Local macOS evidence does not establish exact-head Linux CI,
sustained load, exhaustive interleavings or complete JAM/ThinVRF parity.

Local macOS ARC/Clang validation passed: six real TLS scenarios; three private-state, three actual
composite duplication and one legacy-receiver nominal compiler rejection; five generic-result and
selected-child runtime extraction guards; focused semantic checking, inventory and changed-source
pinned formatter idempotence. Generic runtime probes use scalar payloads to avoid the pinned
compiler's non-nil reference/nested-default construction limitation; genuine successful attempt
construction is independently exercised through actual admitted TLS/current execution.
