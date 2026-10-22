# Current download dispatcher

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive. Existing CE128,
TLS identity, scheduler, ARC and dependency pins remain unchanged.

`CurrentDownloadLoop` composes the current-only peer catalog/session/receiver with one stable
exclusively borrowed Services owner. Its limits contain explicit current candidate and reception
policies; legacy composition/certificates cannot configure this dispatcher. Native reception,
stream retirement, worker submission, exact collection, current enqueue, durable host publication
and consumed adoption remain separate turns. Only the actual current Services result can mark
Adopted. Empty peers retry within the existing bounded schedule. Missing/lost preparation or
handoff authority never implies successful installation. Successful acknowledgment alone permits
explicit next-child rearming against the newly installed parent.

The original total attempt clock includes preparation. Observing the deadline makes even Done work
unwanted before collection. Cancelling retains every graph/input/RPC lease until exact collection
or joined close. Current disk publication can span ticks and retain Publishing until real IO
confirmation and any managed maintenance ends; queued work is not retried/cancelled as an ordinary
network attempt after durable publication has begun. Close joins publication/preparation before
retiring captured input, ancestry or callback owners and never adopts an uncollected prepared job.

RPC proof integration adds explicit exclusion before canonical configuration access, before callback
polling and after Services.tick (which may admit a native proof). During active proof work the loop
keeps its input/ancestry/callback aliases stable and performs only the permitted Services turn.
The authored clock continues; a later ordinary turn still observes the original attempt deadline.
Close joins active proof work through Services.stopStateProofs, preserving RPC request cancellation
and its exact lease, before any retained current graph alias can retire. A legacy handoff remains
another producer's work and is never consumed by this dispatcher.

Run `make unit SUITE=pvm_current_download_loop`. Native witnesses cover genuine current TLS and
full independent state, empty-peer retry, Done deadline/cancellation, joined shutdown, lost handoff,
all four disk-layout/RPC combinations with strict complete-map reopen, and real selected-state
proof completion/configuration exclusion/pause/join. The proof close witness retains an actual
current receiver context while the proof owns its graph. Source-owned private/nominal/actual
duplication guards, adoption/ancestry/forgotten-close failures and an identical-binary configured-close
positive control qualify public lifetime boundaries. Local macOS evidence does not establish
exhaustive scheduling, sustained load, Linux CI or complete JAM/ThinVRF parity. Explicit current
policy decoding and production command selection follow in separate layers.

Local ARC/Clang checks passed: the ten-scenario native suite, four compiler and four runtime guards,
matching configured-close positive control, focused semantic checking, inventory and pinned formatter
idempotence. Existing legacy/dependency sources are unchanged. Test lease assertions use a helper to
avoid teaching the pinned compiler stale facts across pointer-owned dispatcher mutation; actual
runtime assertions and the implementation's canonical access contracts remain enforced.
