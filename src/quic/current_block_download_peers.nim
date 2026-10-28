# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed-address outgoing transport catalog pins authenticated peers before routing scheduled downloads.
## Callers keep borrowed sessions stable and explicitly close this owner before destruction.

import ./transport as quic_transport
import ./protocol as quic_protocol
import ./current_block_download_session as quic_current_block_download_session
import ./current_block_download_stream as quic_current_block_download_stream
import ../app/download_schedule as app_download_schedule
import ../app/current_block_download as app_current_block_download
import ../codec/bounded as codec_bounded

type
  CurrentDownloadPeerKey* = distinct array[32, byte] ## Exact expected Ed25519 identity; never a block/state hash.
  CurrentDownloadPeerError* {.pure.} = enum ## Every refusal leaves native ownership with its existing owner.
    Uninitialized, None, InvalidPolicy, Busy, MissingPeer, InvalidPeer, DuplicatePeer,
    DuplicateIdentity, Capacity, InvalidEndpoint, TransportFailure, NotAuthenticated,
    InvalidAttempt, NoBindingFailure, BindingFailure
  CurrentDownloadPeerResult*[T] = object ## Defaults/refusals carry a reason alone; successful payload extraction is guarded.
    case status: CurrentDownloadPeerError
    of None:
      completed: T
    else:
      discard # Failed/default results never retain a successful child.
  PeerSlot = object ## Its transport/callback address stays fixed throughout connect, stream and close callbacks.
    transport: Transport
    expected: CurrentDownloadPeerKey
    id: DownloadPeerId
    known, registered, checked, verified, stopping, pending, bound, failed: bool
    session: nil ptr CurrentDownloadSession
    attempt: nil CurrentDownloadSessionAttempt
    handle: NativeStream
    limits: CurrentDownloadStreamLimits
    started: CurrentDownloadTick
    lastError: CurrentDownloadPeerError
    binding: CurrentDownloadSessionFailure
  CurrentDownloadPeers* = object ## Each known identity reserves one fixed slot for this catalog's entire lifetime.
    slots: array[16, PeerSlot]
    limit, count: int
    configured, draining: bool

proc `=copy`*(destination: var CurrentDownloadPeers, source: CurrentDownloadPeers) {.
    error: "CurrentDownloadPeers owns native transports and callback addresses".}
  ## Composite ownership must not rely on fields silently inheriting exclusive native lifetimes.
proc `=dup`*(source: CurrentDownloadPeers): CurrentDownloadPeers {.error.}
  ## Duplicating the catalog would duplicate borrowed callback targets and engine retirement obligations.
proc requireRetired(catalog: CurrentDownloadPeers) {.requires: catalog.count == 0.} =
  ## Keep the explicit-close obligation as a runtime/compiler contract, including optimized destructor lowering.
  discard
proc `=destroy`*(catalog: CurrentDownloadPeers) =
  ## Close is explicit so native callbacks retire while every borrowed session is still alive.
  requireRetired(catalog)
  `=destroy`(catalog.slots)

proc `==`*(left, right: CurrentDownloadPeerKey): bool =
  ## Compare the fixed identity bytes explicitly under the pinned compiler's array contracts.
  let first = array[32, byte](left)
  let second = array[32, byte](right)
  for index in 0..<32:
    if first[index] != second[index]: return false # Stop on the first unequal identity byte.
  true
func error*[T](outcome: CurrentDownloadPeerResult[T]): CurrentDownloadPeerError =
  ## Inspect a reason without authorizing payload extraction.
  outcome.status
func value*[T](outcome: CurrentDownloadPeerResult[T]): T {.inline,
    requires: outcome.status == CurrentDownloadPeerError.None.} =
  ## Only actual successful lookup can expose a selected binding failure.
  outcome.completed
func count*(catalog: CurrentDownloadPeers): int =
  ## Count currently owned native endpoints, excluding retired fixed identity reservations.
  catalog.count
proc find(catalog: CurrentDownloadPeers, id: DownloadPeerId): int =
  ## Search at most sixteen stable identity reservations.
  for index in 0..<catalog.limit:
    if catalog.slots[index].known and catalog.slots[index].id ==
        id: return index # Never return an unregistered/default identity.
  -1
proc ready(slot: PeerSlot): bool =
  ## A lifetime success counter alone cannot authorize a closed or unauthenticated connection.
  slot.registered and not slot.stopping and not slot.failed and slot.verified and
    slot.transport.transportStatus == 1 and slot.transport.peerMetric(0) == 1 and
    slot.transport.authenticatedConnections > 0
proc ready*(catalog: CurrentDownloadPeers, id: DownloadPeerId): bool =
  ## Missing/retired peers cannot be selected for a native stream.
  let index = catalog.find(id)
  index >= 0 and catalog.slots[index].ready
proc identityRejected*(catalog: CurrentDownloadPeers, id: DownloadPeerId): bool =
  ## Distinguish an observed certificate-policy refusal from an incomplete handshake.
  let index = catalog.find(id)
  index >= 0 and catalog.slots[index].checked and not catalog.slots[index].verified
proc readyPeers*(catalog: CurrentDownloadPeers): seq[DownloadPeerId] =
  ## Return copied authenticated catalog identities in stable registration-slot order.
  result = @[]
  for index in 0..<catalog.limit:
    if catalog.slots[index].ready: result.add(catalog.slots[
        index].id) # The configured cap bounds both scanning and allocation.
proc busy*(catalog: CurrentDownloadPeers): bool =
  ## Pending native opens also prevent callback mapping reuse until actual retirement.
  for index in 0..<catalog.limit:
    if catalog.slots[index].pending or catalog.slots[index].handle != NativeStream(nil): return true
  false

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Pin the actual TLS-owned DER to this slot's expected key with the shared JAM identity policy.
  let slot = cast[ptr PeerSlot](user)
  if not slot.registered or slot.stopping: return 0 # Retired callback contexts never admit another identity.
  let expected = array[32, byte](slot.expected)
  let accepted = validPeer(cast[ptr byte](der), length, expected)
  slot.checked = true
  slot.verified = accepted
  cint(accepted)

proc streamEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## One slot owns at most one requested stream; unsolicited/refused opens receive no application I/O.
  let slot = cast[ptr PeerSlot](user)
  let borrowed = slot.session
  let token = slot.attempt
  if event == 0:
    if slot.stopping or not slot.pending or slot.handle != NativeStream(nil) or
        borrowed == nil or token == nil or not slot.transport.locallyOpened(stream):
      streamAbort(stream)
      return # Late/foreign opens cannot overwrite an existing callback mapping.
    let session: ptr CurrentDownloadSession = borrowed
    slot.handle = stream
    slot.pending = false
    let binding = session[].bindStream(token, slot.id, stream, slot.limits, slot.started)
    if binding.error != CurrentDownloadSessionError.None:
      slot.binding = binding
      slot.lastError = CurrentDownloadPeerError.BindingFailure
      streamAbort(stream) # Retain this rejected handle/token until its close callback.
    else:
      slot.bound = true # Only the session's successful binding enables native read/write dispatch.
  elif stream == slot.handle and stream != NativeStream(nil):
    if borrowed != nil and token != nil and slot.bound:
      let session: ptr CurrentDownloadSession = borrowed
      discard session[].streamEvent(token, slot.id, stream,
          event) # The joined owner checks exact token/handle/receiver identity.
    if event == 3:
      slot.handle = NativeStream(nil)
      slot.session = nil
      slot.attempt = nil
      slot.pending = false
      slot.bound = false # Clear borrows only after the final real close event.

proc configure*(catalog: var CurrentDownloadPeers, peers: ElementLimit): CurrentDownloadPeerError =
  ## Fixed identity associations are configured once and never rebound to a different peer key.
  if catalog.configured: return CurrentDownloadPeerError.Busy # Use the same catalog to reconnect only already pinned identities.
  if uint64(peers) == 0 or uint64(peers) > 16: return CurrentDownloadPeerError.InvalidPolicy
  catalog.limit = int(uint64(peers)) # The hard cap proves host-sized conversion and callback work.
  catalog.configured = true
  CurrentDownloadPeerError.None

proc openPeer*(catalog: var CurrentDownloadPeers; id: DownloadPeerId;
    expected: CurrentDownloadPeerKey; port: uint16;
    certificate, key, alpn: string): CurrentDownloadPeerError =
  ## Allocate one outgoing endpoint only after bounded identity, duplicate and endpoint preflight.
  if not catalog.configured: return CurrentDownloadPeerError.Uninitialized
  if catalog.draining: return CurrentDownloadPeerError.Busy # Reopening cannot race unfinished native connection retirement.
  if uint64(id) == 0: return CurrentDownloadPeerError.InvalidPeer # Zero cannot become a scheduler identity.
  if port == 0: return CurrentDownloadPeerError.InvalidEndpoint # This API names an explicit existing loopback listener.
  var selected = -1
  for index in 0..<catalog.limit:
    let slot = addr catalog.slots[index]
    if slot.known:
      if slot.id == id:
        if slot.registered: return CurrentDownloadPeerError.DuplicatePeer
        if slot.expected != expected: return CurrentDownloadPeerError.DuplicatePeer # Retirement cannot silently change an ID's authenticated principal.
        selected = index
      elif slot.expected == expected:
        return CurrentDownloadPeerError.DuplicateIdentity # One key cannot acquire duplicate scheduler weight under aliases.
    elif selected == -1:
      selected = index # Prefer a fixed unused slot unless a later known ID identifies its original slot.
  if selected < 0: return CurrentDownloadPeerError.Capacity
  let slot = addr catalog.slots[selected]
  slot.expected = expected
  slot.id = id
  slot.checked = false
  slot.verified = false
  slot.stopping = false
  slot.failed = false
  slot.lastError = CurrentDownloadPeerError.None
  let context = cast[pointer](slot) # Copy the callback address before the mutable Transport initialization borrow.
  if not slot.transport.openTransport(false, false, 0, certificate, key, alpn,
      context, verify, streamEvent):
    return CurrentDownloadPeerError.TransportFailure # Transport.open already retires partial socket/engine setup.
  slot.registered = true
  if not slot.transport.connectTransport(port):
    slot.transport.closeTransport()
    slot.registered = false
    return CurrentDownloadPeerError.TransportFailure # Refused dial setup must not retain a native endpoint.
  slot.known = true
  inc catalog.count # At most sixteen registered slots exist.
  CurrentDownloadPeerError.None

proc poll*(catalog: var CurrentDownloadPeers): int =
  ## Poll each owned endpoint once, nonblockingly, without doing block preparation or adoption.
  result = 0
  for index in 0..<catalog.limit:
    let slot = addr catalog.slots[index]
    if slot.registered:
      if not slot.transport.pollTransport(0): slot.failed = true # A failed endpoint becomes ineligible without stopping healthy peers.
      inc result

proc requestStream*(catalog: var CurrentDownloadPeers, session: var CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt, limits: CurrentDownloadStreamLimits,
        now: CurrentDownloadTick): CurrentDownloadPeerError =
  ## Resolve the selected authenticated peer and retain exact callback context before native open.
  if catalog.busy: return CurrentDownloadPeerError.Busy # Outstanding/rejected/pending handles cannot be rebound early.
  let index = catalog.find(attempt.peer)
  if index < 0: return CurrentDownloadPeerError.MissingPeer
  let slot = addr catalog.slots[index]
  if not slot[].ready: return CurrentDownloadPeerError.NotAuthenticated
  if session.stage != CurrentBlockDownloadStage.Receiving or session.request(attempt).error !=
      CurrentDownloadSessionError.None:
    return CurrentDownloadPeerError.InvalidAttempt # A forged/stale/foreign token cannot choose native I/O.
  slot.session = addr session
  slot.attempt = attempt
  slot.limits = limits
  slot.started = now
  slot.pending = true
  slot.bound = false
  slot.lastError = CurrentDownloadPeerError.None
  slot.binding = default(CurrentDownloadSessionFailure)
  slot.transport.openStream() # Native may call back synchronously; every borrowed field is already installed.
  CurrentDownloadPeerError.None

proc bindingFailure*(catalog: CurrentDownloadPeers,
    id: DownloadPeerId): CurrentDownloadPeerResult[CurrentDownloadSessionFailure] =
  ## Preserve selected late-open binding refusal without exposing native or receiver storage.
  let index = catalog.find(id)
  if index < 0: return CurrentDownloadPeerResult[CurrentDownloadSessionFailure](
      status: CurrentDownloadPeerError.MissingPeer)
  if catalog.slots[index].lastError != CurrentDownloadPeerError.BindingFailure:
    return CurrentDownloadPeerResult[CurrentDownloadSessionFailure](
        status: CurrentDownloadPeerError.NoBindingFailure)
  CurrentDownloadPeerResult[CurrentDownloadSessionFailure](status: CurrentDownloadPeerError.None,
    completed: catalog.slots[index].binding)

proc expire*(catalog: var CurrentDownloadPeers, now: CurrentDownloadTick): int =
  ## Enforce only already bound stream deadlines; pending-open/handshake policy remains explicit host retirement.
  result = 0
  for index in 0..<catalog.limit:
    let slot = addr catalog.slots[index]
    let borrowed = slot.session
    let token = slot.attempt
    if slot.registered and slot.bound and borrowed != nil and token != nil:
      let session: ptr CurrentDownloadSession = borrowed
      if session[].expire(token, slot.handle, now): inc result # Cancellation retains the native handle until close.

proc retire*(catalog: var CurrentDownloadPeers, id: DownloadPeerId): bool =
  ## Native engine destruction flushes close callbacks before identity/context storage may be reused.
  let index = catalog.find(id)
  if index < 0 or not catalog.slots[index].registered: return false
  let slot = addr catalog.slots[index]
  slot.stopping = true
  slot.transport.closeTransport() # Both this slot and every borrowed session remain live through synchronous native close.
  slot.registered = false
  slot.session = nil
  slot.attempt = nil
  slot.handle = NativeStream(nil)
  slot.pending = false
  slot.bound = false
  dec catalog.count # A registered slot proves a corresponding retained endpoint exists.
  true

proc close*(catalog: var CurrentDownloadPeers) =
  ## Idempotently retire all outgoing engines while caller-owned sessions still outlive every callback.
  for index in 0..<catalog.limit:
    if catalog.slots[index].registered:
      let id = catalog.slots[index].id
      discard catalog.retire(id) # Copy the scalar identity before mutating its owning catalog.
  catalog.draining = false # Joined endpoint teardown also completes any interrupted graceful retirement.

proc disconnectPeers*(catalog: var CurrentDownloadPeers): CurrentDownloadPeerError =
  ## One bounded graceful retirement turn; keep polling until count is zero before opening replacement endpoints.
  if not catalog.configured: return CurrentDownloadPeerError.Uninitialized
  if catalog.busy: return CurrentDownloadPeerError.Busy # Native stream/input callbacks must retire before a connection may drain.
  catalog.draining = true
  for index in 0..<catalog.limit:
    # Mark stopping before requesting close, so no new authenticated request can attach to a draining connection.
    let slot = addr catalog.slots[index]
    if slot.registered and not slot.stopping:
      slot.stopping = true
      slot.transport.disconnectTransport()
  discard catalog.poll() # One native turn sends close packets and observes real connection close callbacks.
  for index in 0..<catalog.limit:
    # Engine destruction follows native connection retirement, preserving a single-peer listener's reusable slot.
    let slot = addr catalog.slots[index]
    if slot.registered and slot.transport.peerMetric(0) == 0:
      let id = slot.id
      discard catalog.retire(id)
  if catalog.count == 0: catalog.draining = false # Fixed ID/key reservations survive completed retirement for exact-pin reconnects.
  CurrentDownloadPeerError.None
