# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One task owns the telemetry connection and its Writer; only bounded bytes cross to it.
## The dispatcher keeps all JIP-3 state. It holds output credit until Writer.flush returns,
## so staging and in-flight bytes together stay within the exporter's fixed budget.
## A release/acquire phase transfers exclusive access to the batch and its deadline.
## A lock protects the parked continuation, including the publish-before-park race.
## A named collector is resolved by std/dns once per attempt using the connect deadline.
## The process keeps one configured resolver with a reactor-owned receiver. An incomplete
## cold lookup leaves no cached configuration, so the next attempt can read it again.
## Stop wakes an idle task. Outstanding lookup/connect/write operations retain their original
## five-second deadline; close joins them before releasing mailbox storage and the reactor.
## Stop revokes new batches. An already admitted batch keeps its original write deadline;
## afterward Writer.abort retires the connection without an implicit final flush.

import std/[atomics, dns, ioring, locks, streamio, threadpool]
import std/nativesocket
import std/posix/posix
import std/socket as tcp
import ../lib/socket_io as native_io

const MaxPendingBytes* = 2048
const MaxCollectorName* = 254 ## Textual DNS name length including an optional trailing dot.

type
  Phase = enum Connecting, Ready, Writing, Done
  Exchange = object
    phase: int
    stopping: bool
    bytes: array[MaxPendingBytes, char]
    length: int
    deadline: Deadline
    failure: ErrorCode
    lock: Lock
    waiter: Continuation
  TelemetryStream* = object
    ## Exclusive mailbox owner; the task borrows its stable address only until Done.
    exchange: nil ptr Exchange

var
  collectorResolver: nil Resolver
  resolverLock: Lock

initLock(resolverLock)

proc resolverForAttempt(deadline: Deadline): Resolver {.passive, raises.} =
  ## Retain one configured resolver for the process reactor. Never hold the lock across I/O.
  var installed: nil Resolver = nil
  withLock(resolverLock):
    {.cast(assumeSync).}:
      installed = collectorResolver
  if installed != nil: return installed
  let candidate = dns.initResolver(deadline)
  if monoNow() >= deadline: raise TimeoutError
  # The hosts table and localhost still work without a nameserver. Retry reading
  # the config on the next attempt because no DNS receiver was created here.
  if candidate.servers.len == 0: return candidate
  result = candidate
  withLock(resolverLock):
    {.cast(assumeSync).}:
      let shared = collectorResolver
      if shared == nil:
        collectorResolver = candidate
      else:
        result = shared

proc collectorIpv4Address*(host: string, port: uint16, address: var Sockaddr_in): bool =
  ## Write an initialized native address for a literal or a validated A answer.
  var literal = host
  let family = cint(ord(nativesocket.AF_INET))
  if native_io.parseAddress(family, literal.toCString(), addr address.sin_addr) != 1: return false
  address.sin_family = TSa_Family(family)
  address.sin_port = native_io.networkPort(port)
  when defined(macosx):
    address.sin_len = uint8(sizeof(Sockaddr_in)) # Darwin includes the sockaddr extent.
  true

proc pause(us: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Let reactor workers finish a bounded operation while the owner joins shutdown.

proc observedPhase(s: ptr Exchange): Phase =
  ## Acquire the task's ownership transfer before inspecting its completed batch or error.
  Phase(atomicLoad(s.phase, moAcquire))

proc publish(s: ptr Exchange, phase: Phase) =
  ## Release every mailbox update before another owner observes the phase.
  atomicStore(s.phase, ord(phase), moRelease)

proc pollTelemetryStreams*() =
  ## Drive the existing foreground reactor lane without waiting or creating another pool.
  var completions = default(array[16, IoCompletion])
  discard pollCompletions(completions)

proc wake(s: ptr Exchange) =
  ## Transfer the parked continuation once; an unparked task rechecks published state itself.
  acquire(s.lock)
  let next = s.waiter
  s.waiter = default(Continuation)
  release(s.lock)
  if next.fn != nil: submit(next, -1)

proc waitForBatch(s: ptr Exchange) {.passive.} =
  ## Recheck work and stop under the waiter lock, so a preceding wake cannot be lost.
  let next = delay()
  acquire(s.lock)
  if atomicLoad(s.stopping, moAcquire) or s.observedPhase == Writing:
    release(s.lock)
    return
  s.waiter = next
  release(s.lock)
  suspend()

proc runConnected(fd: cint, s: ptr Exchange) {.passive.} =
  ## Adopt the connected descriptor once; Writer owns all partial-write progress thereafter.
  var (reader, writer) = openStreams(fd)
  try:
    reader.close() # Telemetry is send-only; the Writer retains the shared connection core.
    s.publish(Ready)
    while true:
      if s.observedPhase == Writing:
        # Admission already transferred this batch. Stop cannot erase it in the window
        # before the Writer starts; its original deadline still bounds joined shutdown.
        writer.renew(s.deadline)
        writer.write(toOpenArray(s.bytes, 0, s.length-1))
        writer.flush()
        s.publish(Ready) # Only complete delivery into the kernel releases byte credit.
      elif atomicLoad(s.stopping, moAcquire):
        break
      else:
        waitForBatch(s)
  except ErrorCode as error:
    s.failure = error
  writer.abort() # No destructor flush or trailer is allowed after failure or stop.
  s.publish(Done)

proc connect(address: Sockaddr_storage, size: SockLen, family: Domain,
    deadline: Deadline): tcp.Socket {.passive, raises.} =
  ## The pinned Socket.connect convenience API accepts IPv4 only. Preserve validated IPv6
  ## collectors through public submitConnect; Socket owns setup failure and cancellation cleanup.
  result = tcp.initSocket(-1, deadline)
  result.fd = native_io.socket(cint(ord(family)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if result.fd < 0 or not native_io.nonblocking(result.fd): raise IOError
  var resultCode = 0
  let continuation = delay()
  discard submitConnect(result.fd, address, size, deadline, continuation, addr resultCode)
  suspend()
  if resultCode != 0: raise tcp.toErr(resultCode)

proc connectResolved(literal: string, port: uint16, deadline: Deadline): tcp.Socket {.
    passive, raises.} =
  ## Convert the resolver answer once and enter the same checked native connect path.
  var ipv4 = default(Sockaddr_in)
  var address = default(Sockaddr_storage)
  if sizeof(ipv4) > sizeof(address) or not collectorIpv4Address(literal, port, ipv4):
    raise IOError
  copyMem(addr address, addr ipv4, sizeof(ipv4))
  connect(address, SockLen(sizeof(ipv4)), nativesocket.AF_INET, deadline)

proc run(address: Sockaddr_storage, size: SockLen, family: Domain, name: string, port: uint16,
    deadline: Deadline, s: ptr Exchange) {.passive.} =
  ## Connection setup and stream ownership remain in the same task and share one bounded attempt.
  try:
    var socket = tcp.initSocket(-1, deadline)
    if name.len == 0:
      # Numeric collectors retain the direct IPv4 or IPv6 connection path.
      socket = connect(address, size, family, deadline)
    else:
      # Resolve on the same passive task and absolute deadline as the connect.
      var resolver = resolverForAttempt(deadline)
      let literal = dns.resolve(resolver, name, deadline)
      if atomicLoad(s.stopping, moAcquire):
        s.publish(Done)
        return
      socket = connectResolved(literal, port, deadline)
    let fd = socket.fd
    socket.fd = -1 # Ownership passes to openStreams, including its error and stop paths.
    runConnected(fd, s)
  except ErrorCode as error:
    s.failure = error
    s.publish(Done)

proc release(s: ptr Exchange) =
  ## Join before freeing: a stopped task may still borrow its batch during a bounded write.
  atomicStore(s.stopping, true, moRelease)
  s.wake()
  while s.observedPhase != Done:
    pollTelemetryStreams()
    discard pause(1000)
  deinitLock(s.lock)
  dealloc(s)

proc `=copy`*(destination: var TelemetryStream, source: TelemetryStream) {.error.}
  ## Copying would duplicate join and mailbox destruction authority.

proc `=dup`*(source: TelemetryStream): TelemetryStream {.error.}
  ## The task's stable mailbox has exactly one owner.

proc `=wasMoved`*(stream: var TelemetryStream) {.nodestroy.} =
  ## Transfer the mailbox without waking or freeing the destination's task.
  stream.exchange = nil

proc `=destroy`*(stream: TelemetryStream) =
  ## Every exit joins outstanding I/O before its borrowed storage retires.
  let s = stream.exchange
  if s != nil: release(s)

proc close*(stream: var TelemetryStream) =
  ## Join the already admitted bounded operation, then abort without a final output flush.
  let s = stream.exchange
  if s != nil:
    stream.exchange = nil
    release(s)

proc stop*(stream: var TelemetryStream) =
  ## Request retirement without waiting in a dispatcher tick.
  let s = stream.exchange
  if s != nil:
    atomicStore(s.stopping, true, moRelease)
    s.wake()

proc active*(stream: TelemetryStream): bool =
  ## A pending retirement prevents another attempt from overwriting borrowed mailbox storage.
  stream.exchange != nil

proc finished*(stream: TelemetryStream): bool =
  ## Done publishes the final error after all stream resources have retired.
  let s = stream.exchange
  s != nil and s.observedPhase == Done

proc ready*(stream: TelemetryStream): bool =
  ## Ready grants the dispatcher exclusive access to the next bounded batch.
  let s = stream.exchange
  s != nil and s.observedPhase == Ready

proc failure*(stream: TelemetryStream): ErrorCode =
  ## Read error data only after Done transfers ownership back to the dispatcher.
  let s = stream.exchange
  if s != nil and s.observedPhase == Done: s.failure else: default(ErrorCode)

proc startAttempt(stream: var TelemetryStream, address: Sockaddr_storage, size: SockLen,
    family: Domain, name: string, port: uint16): bool =
  ## Admit an owned continuation and transfer the endpoint and one deadline to it.
  if stream.active: return false # Active and retiring owners keep their existing mailbox.
  let s = cast[ptr Exchange](alloc0(sizeof(Exchange)))
  s[] = Exchange(phase: ord(Connecting), deadline: afterMs(5000))
  initLock(s.lock)
  stream.exchange = s
  submit(delay(run(address, size, family, name, port, s.deadline, s)), -1)
  true

proc start*(stream: var TelemetryStream, address: Sockaddr_storage, size: SockLen,
    family: Domain): bool =
  ## Start one direct connection attempt to an admitted numeric endpoint.
  if family notin {nativesocket.AF_INET, nativesocket.AF_INET6} or
      size == SockLen(0) or int(size) > sizeof(Sockaddr_storage): return false
  stream.startAttempt(address, size, family, "", 0)

proc start*(stream: var TelemetryStream, name: string, port: uint16): bool =
  ## Resolve an admitted DNS name and dial it within one shared attempt deadline.
  if name.len == 0 or name.len > MaxCollectorName or port == 0: return false
  stream.startAttempt(default(Sockaddr_storage), SockLen(0), nativesocket.AF_INET, name, port)

proc send*(stream: var TelemetryStream, bytes: openArray[byte], deadline: Deadline): bool =
  ## Copy one complete bounded batch only while the Writer has released its previous borrow.
  let s = stream.exchange
  if s == nil or s.observedPhase != Ready or bytes.len == 0 or bytes.len > MaxPendingBytes or
      atomicLoad(s.stopping, moAcquire): return false
  for index in 0..<bytes.len:
    s.bytes[index] = char(bytes[index]) # No pointer into dispatcher-owned storage reaches I/O.
  s.length = bytes.len
  s.deadline = deadline
  s.publish(Writing)
  s.wake()
  true
