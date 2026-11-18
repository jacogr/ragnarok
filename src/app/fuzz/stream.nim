# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One task owns the Unix connection's Reader and Writer. A bounded input chunk
## crosses to the dispatcher, which holds framing, session and execution state.
## No read is in flight while the host owns a request or a reply is flushing.
## The exchange deadline renews only after a complete flush. Shutdown wakes
## pending I/O and joins the task before freeing the mailbox. Linux uses
## bounded write-readiness waits because the pinned epoll backend dispatches
## writable events without treating hangup alone as writable.

import std/[atomics, ioring, locks, streamio, threadpool]

const IoBytes* = 4096 ## Only one bounded request chunk crosses per dispatcher turn.

type
  Phase = enum Reading, InputReady, Parked, Writing, Written, Done
  Exchange = object
    phase: int
    stopping: bool
    lock: Lock
    waiter: Continuation
    fd: cint
    deadline: Deadline
    timeoutMs, count: int
    bytes: array[IoBytes, byte]
    buffered: bool
    output: seq[byte]
  FuzzStream* = object ## The dispatcher owns the mailbox until the stream task has joined.
    exchange: nil ptr Exchange

proc shutDownSocket(fd, mode: cint): cint {.importc: "shutdown", header: "<sys/socket.h>".}
  ## Wake a pending Reader or Writer without closing its descriptor.

let ShutBoth {.importc: "SHUT_RDWR", header: "<sys/socket.h>".}: cint

proc pause(us: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Let worker lanes run during joined shutdown.

proc pollFuzzStreams*() =
  ## Drive continuations that have submitted I/O on the dispatcher lane.
  var events = default(array[16, IoCompletion])
  discard pollCompletions(events)

proc observedPhase(s: ptr Exchange): Phase =
  ## Observe mailbox publication before accessing its detached bytes.
  Phase(atomicLoad(s.phase, moAcquire))

proc publish(s: ptr Exchange, phase: Phase) =
  ## Transfer mailbox access and publish the preceding work.
  atomicStore(s.phase, ord(phase), moRelease)

proc wake(s: ptr Exchange) =
  ## Transfer a parked continuation exactly once.
  acquire(s.lock)
  let next = s.waiter
  s.waiter = default(Continuation)
  release(s.lock)
  if next.fn != nil: submit(next, -1)

proc waitForWork(s: ptr Exchange) {.passive.} =
  ## Check work under the waiter lock so a preceding wake cannot be lost.
  let next = delay()
  acquire(s.lock)
  if atomicLoad(s.stopping, moAcquire) or s.observedPhase in {Reading, Writing}:
    release(s.lock)
    return
  s.waiter = next
  release(s.lock)
  suspend()

when defined(linux):
  const WriteWaitMs = 250

  proc waitWritable(s: ptr Exchange): bool {.passive.} =
    ## Wait to write without lending bytes to a reactor operation. Slice the wait
    ## so stop can retire it even when shutdown reports hangup without EPOLLOUT.
    while not atomicLoad(s.stopping, moAcquire) and not expired(s.deadline):
      var ready = 0
      let next = delay()
      discard submitPollAdd(s.fd, earlier(s.deadline, afterMs(WriteWaitMs)), {evWrite},
          next, addr ready)
      suspend()
      if ready >= 0: return evWrite in toIoEvents(ready)
      if ready != IoTimedOut: return false
    false

proc run(s: ptr Exchange) {.passive.} =
  ## The worker adopts this descriptor, makes all Reader and Writer calls, and closes it once.
  var (reader, writer) = openStreams(s.fd, s.deadline)
  var scratch = default(array[IoBytes, char])
  try:
    while not atomicLoad(s.stopping, moAcquire):
      case s.observedPhase
      of Reading:
        if expired(s.deadline): break
        reader.renew(s.deadline)
        let count = reader.read(scratch)
        if count == 0: break
        for index in 0..<count: s.bytes[index] = byte(scratch[index])
        s.count = count
        s.buffered = reader.buffered > 0 # A buffered suffix cannot become another request during this exchange.
        s.publish(InputReady)
      of Writing:
        if expired(s.deadline): break
        writer.renew(s.deadline)
        let output = move(s.output)
        var offset = 0
        while offset < output.len:
          # Writer retains partial progress within a chunk even when the socket would block.
          if atomicLoad(s.stopping, moAcquire) or expired(s.deadline): break
          when defined(linux):
            if not s.waitWritable() or atomicLoad(s.stopping, moAcquire): break
            # The only writer takes one bounded chunk after readiness. Bound the
            # attempt itself in case readiness changes or the kernel makes partial progress.
            writer.renew(earlier(s.deadline, afterMs(WriteWaitMs)))
          let count = min(IoBytes, output.len - offset)
          for index in 0..<count: scratch[index] = char(output[offset + index])
          writer.write(scratch.toOpenArray(0, count - 1))
          when defined(linux): writer.flush()
          offset += count
        if offset != output.len or atomicLoad(s.stopping, moAcquire) or expired(s.deadline): break
        when not defined(linux): writer.flush()
        s.deadline = afterMs(s.timeoutMs)
        s.publish(Written)
      of InputReady, Parked, Written:
        s.waitForWork()
      of Done:
        break # Only retirement publishes this terminal phase.
  except ErrorCode:
    discard # EOF, deadline and I/O failure all retire this local session.
  acquire(s.lock)
  s.fd = -1 # Revoke shutdown authority before the task closes the descriptor to the OS.
  release(s.lock)
  writer.abort()
  try:
    reader.close()
  except ErrorCode:
    discard # Close has retired Reader ownership even if the OS reported an error.
  s.publish(Done)

proc retire(s: ptr Exchange) =
  ## Cancel a blocked operation and wait for the worker to release both halves and its last borrow.
  acquire(s.lock)
  atomicStore(s.stopping, true, moRelease)
  if s.fd >= 0: discard shutDownSocket(s.fd, ShutBoth)
  release(s.lock)
  s.wake()
  while s.observedPhase != Done:
    pollFuzzStreams()
    discard pause(1000)
  s.output = @[] # Stop can arrive before the worker takes a submitted reply.
  deinitLock(s.lock)
  dealloc(s)

proc `=copy`*(dest: var FuzzStream, src: FuzzStream) {.error.}
  ## Mailbox retirement has one owner.

proc `=dup`*(src: FuzzStream): FuzzStream {.error.}
  ## Implicit duplication would duplicate the same join.

proc `=wasMoved`*(stream: var FuzzStream) {.nodestroy.} =
  ## The destination retains the stable mailbox and the source no longer owns it.
  stream.exchange = nil

proc `=destroy`*(stream: FuzzStream) =
  ## A moved or default stream has no outstanding work.
  let s = stream.exchange
  if s != nil: s.retire()

proc start*(stream: var FuzzStream, fd: cint, deadline: Deadline, timeoutMs: int): bool =
  ## Adopt one already configured descriptor on success.
  if stream.exchange != nil or fd < 0: return false
  let s = cast[ptr Exchange](alloc0(sizeof(Exchange)))
  if s == nil: return false
  s[] = Exchange(fd: fd, deadline: deadline, timeoutMs: timeoutMs, phase: ord(Reading))
  initLock(s.lock)
  stream.exchange = s
  submit(delay(run(s)), -1)
  true

proc finished*(stream: FuzzStream): bool =
  ## Completion means task I/O and descriptor ownership have retired.
  let s = stream.exchange
  s != nil and s.observedPhase == Done

proc takeInput*(stream: FuzzStream, data: var array[IoBytes, byte], buffered: var bool): int =
  ## Copy one published chunk and suspend input until the dispatcher decides what comes next.
  let s = stream.exchange
  if s == nil or s.observedPhase != InputReady: return 0
  let count = s.count
  for index in 0..<count: data[index] = s.bytes[index]
  buffered = s.buffered
  s.publish(Parked)
  count

proc receiveNext*(stream: FuzzStream) =
  ## Resume after a partial frame or once a complete exchange has flushed.
  let s = stream.exchange
  if s != nil and s.observedPhase in {Parked, Written}:
    s.publish(Reading)
    s.wake()

proc send*(stream: FuzzStream, output: var seq[byte]): bool =
  ## Transfer one complete frame while reading is parked.
  let s = stream.exchange
  if s == nil or s.observedPhase != Parked: return false
  s.output = move(output)
  s.publish(Writing)
  s.wake()
  true

proc takeWritten*(stream: FuzzStream, deadline: var Deadline): bool =
  ## Use the deadline computed at flush completion before resuming reads.
  let s = stream.exchange
  if s == nil or s.observedPhase != Written: return false
  deadline = s.deadline
  true
