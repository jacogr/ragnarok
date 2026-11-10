# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Move an accepted socket into one bounded Reader/Writer task. The dispatcher
## exchanges owned byte chunks and keeps all service policy and application state.

import std/[assertions, atomics, ioring, streamio, strutils, threadpool]
import ./logging

type
  Phase = enum Read, Input, Write, Ready, Done
  Exchange = object
    phase: int
    stopping: bool
    data: string
    limit: int
    final: bool
    failure, cleanupFailure: ErrorCode
    operation: Phase
    deadline: Deadline
  HttpStream* = object
    exchange: nil ptr Exchange

proc pause(us: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Give worker lanes time to finish a parked operation during joined shutdown.

proc observedPhase(s: ptr Exchange): Phase =
  ## The published phase grants access to the corresponding mailbox fields.
  Phase(atomicLoad(s.phase, moAcquire))

proc publish(s: ptr Exchange, phase: Phase) =
  ## Publish all mailbox changes before the other owner touches them.
  atomicStore(s.phase, ord(phase), moRelease)

proc yieldIo() {.passive.} =
  ## Wait for a dispatcher turn without holding a worker.
  let continuation = delay()
  discard submitTimeout(afterMs(1), continuation)
  suspend()

proc run(fd: cint, deadline: Deadline, s: ptr Exchange) {.passive.} =
  ## Both halves stay with this task, so the standing deadline is immutable.
  var (reader, writer) = openStreams(fd, deadline)
  var bytes = default(array[16384, char])
  try:
    while not atomicLoad(s.stopping, moAcquire):
      case s.observedPhase
      of Read:
        s.operation = Read
        if expired(deadline):
          s.failure = TimeoutError
          break
        let limit = min(s.limit, bytes.len)
        let count = reader.read(toOpenArray(bytes, 0, limit - 1))
        if count == 0:
          s.failure = EndOfStreamError
          break
        s.data = ""
        for i in 0..<count: s.data.add(bytes[i])
        s.publish(Input)
      of Write:
        s.operation = Write
        if expired(deadline):
          s.failure = TimeoutError
          break
        let chunk = move(s.data)
        writer.write(chunk)
        if s.final:
          writer.close()
          break
        writer.flush()
        s.publish(Ready)
      of Input, Ready:
        yieldIo()
      of Done:
        break
  except ErrorCode as error:
    s.failure = error
  writer.abort()
  try:
    reader.close()
  except ErrorCode as error:
    s.cleanupFailure = error
  s.publish(Done)

proc pollHttpStreams*() =
  ## Passive waits can run on the foreground lane, which must also drive I/O.
  var completions = default(array[16, IoCompletion])
  discard pollCompletions(completions)

proc release(s: ptr Exchange, logger: LogWriter, service: string) =
  ## A five-second deadline set before submission bounds outstanding I/O.
  atomicStore(s.stopping, true, moRelease)
  while s.observedPhase != Done:
    pollHttpStreams()
    discard pause(1000)
  if s.failure != default(ErrorCode):
    # EOF and timeouts are common client lifecycle events. Unexpected I/O failures are warnings.
    let level = if s.failure in {EndOfStreamError, TimeoutError}: LogLevel.Debug else: LogLevel.Warn
    let operation = if s.operation == Read: "read" else: "write"
    log(logger, LogTarget.Rpc, level, service & " stream " & operation & " ended: " & $s.failure)
  elif ioring.expired(s.deadline):
    log(logger, LogTarget.Rpc, LogLevel.Debug, service & " connection deadline expired")
  if s.cleanupFailure != default(ErrorCode):
    log(logger, LogTarget.Rpc, LogLevel.Warn, service & " reader close failed: " &
        $s.cleanupFailure)
  log(logger, LogTarget.Rpc, LogLevel.Trace, service & " connection retired")
  `=destroy`(s[])
  dealloc(s)

proc close*(stream: var HttpStream, logger: LogWriter, service: string) =
  ## Join the task and report its outcome from the dispatcher.
  let s = stream.exchange
  if s != nil:
    stream.exchange = nil
    s.release(logger, service)

proc logHttpResponse*(logger: LogWriter, service, response: string) =
  ## Log only the server-generated status line. Request bodies and headers remain private.
  if logger.enabled(LogTarget.Rpc, LogLevel.Debug):
    let ending = response.find("\r\n")
    if ending > 0:
      log(logger, LogTarget.Rpc, LogLevel.Debug, service & " response " & response.substr(0,
          ending - 1))

proc `=copy`*(dest: var HttpStream, source: HttpStream) {.error.}

proc `=dup`*(source: HttpStream): HttpStream {.error.}

proc `=destroy`*(stream: HttpStream) =
  ## Mailbox storage outlives every task borrow, including on error paths.
  let s = stream.exchange
  if s != nil: s.release(default(LogWriter), "")

proc `=wasMoved`*(stream: var HttpStream) {.nodestroy.} =
  ## Transfer the pointer without moving the storage used by the task.
  stream.exchange = nil

proc start*(stream: var HttpStream, fd: cint, limit: int, timeoutMs = 5000) =
  ## Take ownership of a configured accepted descriptor and begin one request.
  assert stream.exchange == nil and fd >= 0 and limit > 0 and timeoutMs > 0
  let s = cast[ptr Exchange](alloc0(sizeof(Exchange)))
  let deadline = afterMs(timeoutMs)
  s[] = Exchange(phase: ord(Read), limit: limit, deadline: deadline)
  stream.exchange = s
  submit(delay(run(fd, deadline, s)), -1)

proc finished*(stream: HttpStream): bool =
  ## Done means both halves have released their stream ownership.
  let s = stream.exchange
  s != nil and s.observedPhase == Done

proc expired*(stream: HttpStream): bool =
  ## Apply the same immutable deadline before dispatching a request or reading a file.
  let s = stream.exchange
  s != nil and ioring.expired(s.deadline)

proc stop*(stream: var HttpStream) =
  ## Retire an expired mailbox without waiting on a dispatcher turn.
  let s = stream.exchange
  if s != nil: atomicStore(s.stopping, true, moRelease)

proc receiveChunk*(stream: var HttpStream, input: var string): bool =
  ## Transfer a received chunk to the dispatcher exactly once per request.
  let s = stream.exchange
  if s == nil or s.observedPhase != Input or ioring.expired(s.deadline): return false
  input.add(s.data)
  s.data = ""
  true

proc requestChunk*(stream: var HttpStream, limit: int) =
  ## Ask for more request bytes only after parsing the preceding chunk.
  let s = stream.exchange
  assert s != nil and limit > 0
  if s.observedPhase == Input:
    s.limit = limit
    s.publish(Read)

proc canSend*(stream: HttpStream): bool =
  ## Only a waiting task can accept another output chunk.
  let s = stream.exchange
  s != nil and s.observedPhase in {Input, Ready}

proc sendChunk*(stream: var HttpStream, output: var string, final: bool) =
  ## Transfer one serialized response chunk. The task closes after the final chunk.
  let s = stream.exchange
  assert s != nil and s.observedPhase in {Input, Ready}
  s.data = move(output)
  s.final = final
  s.publish(Write)

proc shutdownHttpStreams*() =
  ## The application calls this once after every service has retired its tasks.
  ioring.shutdown()
