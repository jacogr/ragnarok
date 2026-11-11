# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One task owns both Nimony stream halves per accepted RPC connection.
## The dispatcher owns one-shot read readiness. Publishing output or stop
## wakes the parked task directly, including when the socket is idle.
## Only a complete upgrade head, a decoded frame or a framing error crosses
## the input mailbox. The reader fills only while the current head or frame
## is incomplete. The dispatcher owns upgrade policy, message assembly,
## request execution and subscription state.

import std/[assertions, atomics, ioring, locks, streamio, threadpool]
import std/http/httpparse as http_parse
import ./wire

const PendingReadiness = low(int)

type
  WaitFor = enum OutputOnly, InboxTaken, SocketReadable
  WireInputKind* = enum BadHead, UpgradeHead, ClientFrame
  WireInput* = object
    case kind*: WireInputKind
    of BadHead: discard
    of UpgradeHead: head*: string
    of ClientFrame: frame*: FrameResult
  StreamExchange = object
    stopping, done, inputReady, bufferedInput, inputEof, outputReady: bool
    input: WireInput
    output: string
    lock: Lock
    waiter: Continuation
    waitFor: WaitFor
    readDeadline: Deadline
    readable: bool
    fd: cint
    watching: bool
    readiness: int
    outputDeadline: Deadline
  RpcWireStream* = object
    exchange: nil ptr StreamExchange

proc pause(us: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Let worker lanes finish without holding the dispatcher I/O lane.

proc pollRpcStreams*() =
  ## A passive continuation can be scheduled on the foreground reactor lane.
  var completions = default(array[16, IoCompletion])
  discard pollCompletions(completions)

proc wake(s: ptr StreamExchange) =
  ## The lock transfers the one parked continuation to exactly one submitter.
  acquire(s.lock)
  let next = s.waiter
  s.waiter = default(Continuation)
  release(s.lock)
  if next.fn != nil: submit(next, -1)

proc waitForDispatch(s: ptr StreamExchange, reason: WaitFor, deadline = never) {.passive.} =
  ## Recheck producer state while publishing the waiter to avoid lost wakeups.
  let next = delay()
  acquire(s.lock)
  if atomicLoad(s.stopping, moAcquire) or atomicLoad(s.outputReady, moAcquire) or
      (reason == InboxTaken and not atomicLoad(s.inputReady, moAcquire)) or
      (reason == SocketReadable and atomicLoad(s.readable, moAcquire)):
    release(s.lock)
    return
  s.waitFor = reason
  s.readDeadline = deadline
  s.waiter = next
  release(s.lock)
  suspend()

proc cancelWatch(s: ptr StreamExchange) =
  ## Only the dispatcher lane registers and cancels readiness. It cancels
  ## before waking a writer or stopping the stream, while the fd is still live.
  if s.watching:
    discard submitPollRemove(s.fd)
    assert s.readiness != PendingReadiness
    s.watching = false

proc pump*(stream: RpcWireStream) =
  ## Drive one-shot readiness on the same dispatcher lane each turn.
  let s = stream.exchange
  if s == nil: return
  if s.watching:
    if s.readiness == PendingReadiness: return
    s.watching = false
    atomicStore(s.readable, true, moRelease)
    s.wake()
    return
  acquire(s.lock)
  let wantsRead = s.waiter.fn != nil and s.waitFor == SocketReadable
  let deadline = s.readDeadline
  release(s.lock)
  if wantsRead:
    s.readiness = PendingReadiness
    s.watching = true
    discard submitPollAdd(s.fd, deadline, {evRead}, resPtr = addr s.readiness)

proc run(fd: cint, s: ptr StreamExchange) {.passive.} =
  ## The single owner can safely change the shared stream deadline between operations.
  var (reader, writer) = openStreams(fd)
  var scanner = default(http_parse.HeadScanner)
  var readingHead = true
  var atEof = false
  var frameDeadline = never
  try:
    while not atomicLoad(s.stopping, moAcquire):
      if atomicLoad(s.outputReady, moAcquire):
        # Credit remains occupied until the entire response reaches the kernel.
        writer.renew(s.outputDeadline)
        writer.write(s.output)
        writer.flush()
        s.output = ""
        atomicStore(s.outputReady, false, moRelease)
      elif atEof:
        s.waitForDispatch(OutputOnly)
      elif atomicLoad(s.inputReady, moAcquire):
        s.waitForDispatch(InboxTaken)
      else:
        if expired(frameDeadline): break
        if reader.buffered > 0:
          if readingHead:
            let extent = scanner.findHeadEnd(reader.peek)
            if extent != http_parse.ParseIncomplete:
              if extent < 0:
                # Publish the framing failure and let the dispatcher retire the connection.
                s.input = WireInput(kind: BadHead)
                atEof = true
              else:
                var head = ""
                let bytes = reader.peek
                for index in 0..<extent: head.add(bytes[index])
                reader.consume(extent)
                s.input = WireInput(kind: UpgradeHead, head: move(head))
                readingHead = false
              frameDeadline = never
              atomicStore(s.inputReady, true, moRelease)
              atomicStore(s.bufferedInput, not atEof and reader.buffered > 0, moRelease)
              continue
          else:
            var parsed = decodeFrame(reader.peek)
            if parsed.status != incomplete:
              if parsed.status == complete:
                reader.consume(parsed.consumed)
              else:
                # Keep the writer for the dispatcher-generated protocol close.
                atEof = true
              s.input = WireInput(kind: ClientFrame, frame: move(parsed))
              frameDeadline = never
              atomicStore(s.inputReady, true, moRelease)
              atomicStore(s.bufferedInput, not atEof and reader.buffered > 0, moRelease)
              continue
          if frameDeadline == never: frameDeadline = afterMs(5000)
        if not atomicLoad(s.readable, moAcquire):
          s.waitForDispatch(SocketReadable, frameDeadline)
          continue
        atomicStore(s.readable, false, moRelease)
        # Readiness is advisory. A short retry keeps an unexpected wait bounded.
        reader.renew(earlier(afterMs(10), frameDeadline))
        var count = 0
        try:
          count = reader.fill()
        except ErrorCode as error:
          # Timeout leaves the unread prefix intact for the next readiness event.
          if error == TimeoutError: continue
          break
        if count == 0:
          # FIN follows the last inbox transfer and must leave the writer available.
          atEof = true
          atomicStore(s.inputEof, true, moRelease)
          atomicStore(s.bufferedInput, false, moRelease)
        else:
          atomicStore(s.bufferedInput, true, moRelease)
  except ErrorCode:
    discard # Writer failure retires the connection and its outstanding credit.
  writer.abort()
  try:
    reader.close()
  except ErrorCode:
    discard
  atomicStore(s.done, true, moRelease)

proc active*(stream: RpcWireStream): bool =
  ## Allocated mailboxes must outlive the task, including after stop is requested.
  stream.exchange != nil

proc finished*(stream: RpcWireStream): bool =
  ## Completion is published only after both halves retire.
  let s = stream.exchange
  s != nil and atomicLoad(s.done, moAcquire)

proc stop*(stream: RpcWireStream) =
  ## Stop from the dispatcher lane that armed readiness. A parked task is
  ## woken here. An operation already in flight keeps its existing deadline.
  let s = stream.exchange
  if s != nil:
    s.cancelWatch()
    atomicStore(s.stopping, true, moRelease)
    s.wake()

proc `=copy`*(dest: var RpcWireStream, source: RpcWireStream) {.error.}

proc `=dup`*(source: RpcWireStream): RpcWireStream {.error.}

proc `=destroy`*(stream: RpcWireStream) =
  ## Shutdown waits only for the bounded operation already owned by the worker.
  let s = stream.exchange
  if s != nil:
    stream.stop()
    while not atomicLoad(s.done, moAcquire):
      pollRpcStreams()
      discard pause(1000)
    deinitLock(s.lock)
    `=destroy`(s[])
    dealloc(s)

proc `=wasMoved`*(stream: var RpcWireStream) {.nodestroy.} =
  ## Move cleanup authority while the task retains the same address.
  stream.exchange = nil

proc start*(stream: var RpcWireStream, fd: cint) =
  ## Transfer a configured accepted descriptor into stock stream ownership.
  assert not stream.active and fd >= 0
  let s = cast[ptr StreamExchange](alloc0(sizeof(StreamExchange)))
  s[] = StreamExchange(fd: fd)
  initLock(s.lock)
  stream.exchange = s
  submit(delay(run(fd, s)), -1)

proc takeInput*(stream: var RpcWireStream, input: var WireInput): bool =
  ## Move one complete framing result without borrowing the reader.
  let s = stream.exchange
  if s == nil or not atomicLoad(s.inputReady, moAcquire): return false
  input = move(s.input)
  atomicStore(s.inputReady, false, moRelease)
  s.wake()
  true

proc hasBufferedInput*(stream: RpcWireStream): bool =
  ## The worker's framing budget owns partial data once it has arrived.
  let s = stream.exchange
  s != nil and (atomicLoad(s.bufferedInput, moAcquire) or atomicLoad(s.inputReady, moAcquire))

proc inputEnded*(stream: RpcWireStream): bool =
  ## Orderly EOF follows the last inbox transfer. The writer remains available until stop.
  let s = stream.exchange
  s != nil and atomicLoad(s.inputEof, moAcquire)

proc writing*(stream: RpcWireStream): bool =
  ## Output credit includes the bytes currently being written by the task.
  let s = stream.exchange
  s != nil and atomicLoad(s.outputReady, moAcquire)

proc send*(stream: var RpcWireStream, output: var string) =
  ## Hand off one complete wire frame or upgrade response with a bounded send budget.
  let s = stream.exchange
  assert s != nil and not stream.writing
  s.cancelWatch()
  s.output = move(output)
  s.outputDeadline = afterMs(5000)
  atomicStore(s.outputReady, true, moRelease)
  s.wake()
