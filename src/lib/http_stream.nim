# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## UI, MCP, and management hand each accepted connection to one task that owns
## its Reader and Writer. The dispatcher checks the stream deadline before
## handling a request or reading another asset chunk. The task scans one
## bounded head. The dispatcher applies policy before authorizing any body
## read and handles the completed request with the current application state.
##
## Joining the task keeps mailbox storage alive until both halves retire.
## std/ioring starts the process-wide worker pool on import. The executable
## shuts down that reactor after every service has joined its stream tasks.

import std/[atomics, ioring, streamio, strutils, threadpool]
import std/http/httpparse as http_parse
import ./logging

type
  Phase = enum ReadHead, HeadReady, ReadBody, BodyReady, Write, Ready, Done
  Exchange = object
    phase: int
    stopping: bool
    data: string
    headBytes, bodyBytes, maxBodyBytes: int
    hasSuffix: bool
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

proc fillRequest(reader: var Reader, deadline: Deadline) {.passive, raises.} =
  ## Every read in this request shares the original deadline.
  if expired(deadline): raise TimeoutError
  if reader.fill() == 0: raise EndOfStreamError

proc run(fd: cint, deadline: Deadline, s: ptr Exchange) {.passive.} =
  ## Both halves stay with this task, so the standing deadline is immutable.
  var (reader, writer) = openStreams(fd, deadline)
  var scanner = default(http_parse.HeadScanner)
  try:
    while not atomicLoad(s.stopping, moAcquire):
      case s.observedPhase
      of ReadHead:
        s.operation = ReadHead
        # The scanner resumes over the reader's unread buffer. Any coalesced
        # body bytes stay there until the dispatcher authorizes their length.
        while true:
          let extent = scanner.findHeadEnd(reader.peek)
          if extent != http_parse.ParseIncomplete:
            s.headBytes = extent
            if extent > 0:
              let bytes = reader.peek
              for index in 0..<extent: s.data.add(bytes[index])
              reader.consume(extent)
            s.publish(HeadReady)
            break
          reader.fillRequest(deadline)
      of ReadBody:
        s.operation = ReadBody
        # Stop filling as soon as the declared extent is present. A suffix
        # already buffered with it is invalid for these single-request endpoints.
        while reader.buffered < s.bodyBytes:
          reader.fillRequest(deadline)
        s.hasSuffix = reader.buffered > s.bodyBytes
        if not s.hasSuffix:
          for octet in reader.peek: s.data.add(octet)
          reader.consume(s.bodyBytes)
        s.publish(BodyReady)
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
      of HeadReady, BodyReady, Ready:
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
    let operation = if s.operation == Write: "write" else: "read"
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

proc start*(stream: var HttpStream, fd: cint, maxBodyBytes = 0,
    timeoutMs = 5000): bool =
  ## Take the descriptor on success. The caller retains it on refusal.
  if stream.exchange != nil or fd < 0 or maxBodyBytes < 0 or timeoutMs <= 0:
    return false
  let s = cast[ptr Exchange](alloc0(sizeof(Exchange)))
  let deadline = afterMs(timeoutMs)
  s[] = Exchange(phase: ord(ReadHead), deadline: deadline, maxBodyBytes: maxBodyBytes)
  stream.exchange = s
  submit(delay(run(fd, deadline, s)), -1)
  true

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

proc receiveHead*(stream: var HttpStream, head: var string): int =
  ## Transfer one complete head or the scanner's over-limit result.
  let s = stream.exchange
  if s == nil or s.observedPhase != HeadReady or ioring.expired(s.deadline):
    return http_parse.ParseIncomplete
  head = move(s.data)
  result = s.headBytes
  s.publish(Ready)

proc requestBody*(stream: var HttpStream, length: int) =
  ## The caller has validated the headers and bounded the declared body length.
  let s = stream.exchange
  if s == nil: return
  if s.observedPhase != Ready or length < 0 or length > s.maxBodyBytes:
    stream.stop()
    return
  s.bodyBytes = length
  s.publish(ReadBody)

proc receiveBody*(stream: var HttpStream, body: var string, hasSuffix: var bool): bool =
  ## Take the complete authorized body or report a suffix buffered beyond it.
  let s = stream.exchange
  if s == nil or s.observedPhase != BodyReady or ioring.expired(s.deadline): return false
  body = move(s.data)
  hasSuffix = s.hasSuffix
  s.publish(Ready)
  true

proc canSend*(stream: HttpStream): bool =
  ## The dispatcher can take a finished read or queue the next response chunk.
  let s = stream.exchange
  s != nil and s.observedPhase in {HeadReady, BodyReady, Ready}

proc sendChunk*(stream: var HttpStream, output: var string, final: bool) =
  ## Transfer one serialized response chunk. The task closes after the final chunk.
  let s = stream.exchange
  if s == nil: return
  if s.observedPhase != Ready:
    stream.stop()
    return
  s.data = move(output)
  s.final = final
  s.publish(Write)

proc shutdownHttpStreams*() =
  ## The application calls this once after every service has retired its tasks.
  ioring.shutdown()
