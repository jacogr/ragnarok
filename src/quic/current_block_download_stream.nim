# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded native CE 128 routing. Transport owns handles; callers retain stable receiver/callback
## owners until native close. No operation prepares a block or dereferences a retained receiver address.

import std/assertions
import ./transport
import ../app/current_block_download
import ../codec/bounded

type
  CurrentDownloadTick* = distinct uint64 ## Caller-supplied monotonic milliseconds, unrelated to block slots.
  CurrentDownloadTimeout* = distinct uint64 ## Explicit positive total transfer duration in milliseconds.
  CurrentDownloadStreamLimits* = object ## Validated once before enabling callbacks; no network value chooses callback work.
    readBytes*, writeBytes*: ByteLimit
    timeout*: CurrentDownloadTimeout
  CurrentDownloadStreamError* {.pure.} = enum ## Binding refusal leaves both controller and receiver unchanged.
    None, Busy, InvalidStream, InvalidPolicy, NotReceiving, StaleDownload
  CurrentDownloadStream* = object ## Exclusive callback binding; transport and receiver must outlive its final close event.
    handle: NativeStream
    receiver: nil pointer
    id: CurrentBlockDownloadId
    request: array[42, byte]
    offset, readLimit, writeLimit: int
    received, started, timeout: uint64
    readFin, writeFin, stopping: bool

proc `=destroy`*(route: CurrentDownloadStream) =
  ## Verify explicit callback retirement; destruction must never call through a borrowed native handle.
  assert route.handle == NativeStream(nil), "CurrentDownloadStream must receive native close before destruction"
proc `=copy`*(destination: var CurrentDownloadStream, source: CurrentDownloadStream) {.
    error: "CurrentDownloadStream owns a native callback binding".}
  ## Duplicating a borrowed native handle would duplicate cancellation and write offsets.
proc `=dup`*(source: CurrentDownloadStream): CurrentDownloadStream {.error.}
  ## Scalar-only bindings also require an explicit duplication ban in the pinned compiler.

proc active*(route: CurrentDownloadStream): bool =
  ## Cancellation retains a binding until native close; callbacks still need this stable owner.
  route.handle != NativeStream(nil)

func receivedBytes*(route: CurrentDownloadStream): uint64 =
  ## Observe copied wire bytes while active; close clears all per-stream counters.
  route.received

proc matches(route: CurrentDownloadStream, download: var CurrentBlockDownload,
    id: CurrentBlockDownloadId, handle: NativeStream): bool =
  ## Compare all identities before touching either a native handle or application generation.
  route.active and route.id == id and route.handle == handle and
    route.receiver == cast[pointer](addr download)

proc bindStream*(route: var CurrentDownloadStream, download: var CurrentBlockDownload,
    id: CurrentBlockDownloadId, handle: NativeStream, limits: CurrentDownloadStreamLimits,
    now: CurrentDownloadTick): CurrentDownloadStreamError =
  ## Bind an already admitted request at native open; refusal never enables native callbacks.
  if route.active: return CurrentDownloadStreamError.Busy # Even a stopping handle awaits its final close callback.
  if handle == NativeStream(nil): return CurrentDownloadStreamError.InvalidStream # No native operation accepts a missing handle.
  if uint64(limits.readBytes) == 0 or uint64(limits.readBytes) > 4096 or
      uint64(limits.writeBytes) == 0 or uint64(limits.writeBytes) > 42 or
      uint64(limits.timeout) == 0:
    return CurrentDownloadStreamError.InvalidPolicy # Fixed storage bounds precede every narrowing conversion.
  if download.stage != CurrentBlockDownloadStage.Receiving:
    return CurrentDownloadStreamError.NotReceiving # A completed, failed or absent request cannot start another transport.
  let request = download.request(id)
  if request.error != CurrentBlockDownloadError.None:
    return CurrentDownloadStreamError.StaleDownload # Wrong generations retain the current application request unchanged.
  route = CurrentDownloadStream(handle: handle, receiver: cast[pointer](addr download), id: id,
    request: request.value, offset: 0, readLimit: int(uint64(limits.readBytes)),
    writeLimit: int(uint64(limits.writeBytes)), received: 0, started: uint64(now),
    timeout: uint64(limits.timeout), readFin: false, writeFin: false, stopping: false)
  wantRead(handle, 1)
  wantWrite(handle, 1)
  CurrentDownloadStreamError.None

proc stop(route: var CurrentDownloadStream, download: var CurrentBlockDownload) =
  ## Abort this native stream once, preserving selected framing failures and complete two-FIN outcomes.
  if download.stage == CurrentBlockDownloadStage.Receiving:
    discard download.cancel(route.id) # Generation checks keep external cancellation/replacement inert.
  if not route.stopping:
    route.stopping = true
    let handle = route.handle
    wantRead(handle, 0)
    wantWrite(handle, 0)
    streamAbort(handle) # The bridge closes a stream; it does not prove a wire-level RESET_STREAM.

proc cancel*(route: var CurrentDownloadStream, download: var CurrentBlockDownload,
    id: CurrentBlockDownloadId, handle: NativeStream): bool =
  ## Explicit acknowledgement also retires Ready/Failed input, but never releases the native binding early.
  if not route.matches(download, id, handle): return false # Late/foreign callbacks cannot cancel another receiver.
  discard download.cancel(id)
  route.stop(download)
  true

proc expire*(route: var CurrentDownloadStream, download: var CurrentBlockDownload,
    id: CurrentBlockDownloadId, handle: NativeStream, now: CurrentDownloadTick): bool =
  ## Enforce an explicit total deadline outside callbacks without overflow or fabricated response FIN.
  if not route.matches(download, id, handle) or route.stopping or
      download.stage != CurrentBlockDownloadStage.Receiving:
    return false # Completed/error streams retain their selected outcomes until normal close/acknowledgement.
  if uint64(now) < route.started or uint64(now) - route.started < route.timeout:
    return false # Backward ticks never underflow into an immediate expiry.
  route.stop(download)
  true

proc readable(route: var CurrentDownloadStream, download: var CurrentBlockDownload) =
  ## Read at most one explicitly bounded fragment; only actual native EOF supplies response FIN.
  if route.readFin: return # Replayed read callbacks cannot supply a second FIN.
  var buffer = default(array[4096, byte])
  let count = streamRead(route.handle, addr buffer[0], csize_t(route.readLimit))
  if count == -2: return # Would-block yields with unchanged offset/context.
  if count < 0 or count > int64(route.readLimit):
    route.stop(download)
    return # Native errors and impossible adapter extents authorize no usable prefix.
  var outcome = CurrentBlockDownloadError.None
  if count == 0:
    route.readFin = true
    let handle = route.handle
    readDone(handle)
    wantRead(handle, 0)
    outcome = download.append(route.id, [], true)
  else:
    if uint64(count) > high(uint64) - route.received:
      route.stop(download)
      return # Counter arithmetic is checked independently of application payload limits.
    route.received += uint64(count)
    outcome = download.append(route.id, buffer.toOpenArray(0, int(count) - 1), false)
  if outcome != CurrentBlockDownloadError.None:
    route.stop(download) # Typed framing failure remains available after native close.

proc writable(route: var CurrentDownloadStream, download: var CurrentBlockDownload) =
  ## Retain partial-write offsets and queue FIN exactly once after all fixed request bytes are accepted.
  if route.writeFin: return # A duplicate callback after FIN must never repeat native shutdown.
  if route.offset < route.request.len:
    let length = min(route.writeLimit, route.request.len - route.offset)
    let count = streamWrite(route.handle, addr route.request[route.offset], csize_t(length))
    if count == -2: return # Flow control retains the exact unsent suffix for a later callback.
    if count < 0 or count > int64(length):
      route.stop(download)
      return # A failed/invalid native write cannot supply request FIN.
    route.offset += int(count) # Count is bounded by the remaining fixed request extent.
  if route.offset == route.request.len:
    route.writeFin = true
    let handle = route.handle
    wantWrite(handle, 0)
    streamFin(handle)
    if download.requestFinished(route.id) != CurrentBlockDownloadError.None:
      route.stop(download) # Externally retired input cannot be revived by a delayed write callback.

proc streamEvent*(route: var CurrentDownloadStream, download: var CurrentBlockDownload,
    id: CurrentBlockDownloadId, handle: NativeStream, event: cint): bool =
  ## Dispatch read/write/close/reset only for the retained binding; open remains an explicit bind operation.
  if not route.matches(download, id, handle): return false # Replayed/foreign events perform no native calls.
  case event
  of 3:
    if download.stage == CurrentBlockDownloadStage.Receiving:
      discard download.cancel(id) # Final close is never an implicit clean response FIN.
    route.handle = NativeStream(nil) # Mark the binding retired before replacing its checked lifetime owner.
    route = default(CurrentDownloadStream) # Native owns no further callback borrow after close.
  of 4:
    route.stop(download) # Reset cannot manufacture completion or erase an actual framing failure.
  of 1, 2:
    if not route.stopping:
      if download.request(id).error != CurrentBlockDownloadError.None:
        route.stop(download) # External retirement/replacement stops I/O before touching stale request bytes.
      elif event == 1:
        route.readable(download) # Each callback performs at most one native I/O operation.
      else:
        route.writable(download) # Writes retain the same request captured at binding.
  else:
    return false # Unknown/open events need explicit host policy rather than guessed ABI behavior.
  true
