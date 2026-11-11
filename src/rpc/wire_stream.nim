# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One task owns both Nimony stream halves per accepted RPC connection.
## Read timeouts yield to queued output without touching the frame parser.
## The dispatcher owns framing, request execution and subscription state.

import std/[assertions, atomics, ioring, streamio, threadpool]

type
  StreamExchange = object
    stopping, done, inputReady, inputEof, outputReady: bool
    input, output: string
    outputDeadline: Deadline
  RpcWireStream* = object
    exchange: nil ptr StreamExchange

proc pause(us: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Let worker lanes finish without holding the dispatcher I/O lane.

proc pollRpcStreams*() =
  ## A passive continuation can be scheduled on the foreground reactor lane.
  var completions = default(array[16, IoCompletion])
  discard pollCompletions(completions)

proc yieldRpcIo() {.passive.} =
  ## Yield briefly while waiting for the dispatcher to take input or publish output.
  let continuation = delay()
  discard submitTimeout(afterMs(1), continuation)
  suspend()

proc run(fd: cint, s: ptr StreamExchange) {.passive.} =
  ## The single owner can safely change the shared stream deadline between operations.
  var (reader, writer) = openStreams(fd)
  var bytes = default(array[4096, char])
  var atEof = false
  try:
    while not atomicLoad(s.stopping, moAcquire):
      if atomicLoad(s.outputReady, moAcquire):
        # Credit remains occupied until the entire response reaches the kernel.
        writer.renew(s.outputDeadline)
        writer.write(s.output)
        writer.flush()
        s.output = ""
        atomicStore(s.outputReady, false, moRelease)
      elif not atEof and not atomicLoad(s.inputReady, moAcquire):
        reader.renew(afterMs(10))
        var count = 0
        try:
          count = reader.read(bytes)
        except ErrorCode as error:
          # The plain stream has delivered no bytes when a read times out.
          if error == TimeoutError: continue
          break
        if count == 0:
          # FIN ends input only. The dispatcher may still be building a reply for the last chunk.
          atEof = true
          atomicStore(s.inputEof, true, moRelease)
          continue
        for index in 0..<count: s.input.add(bytes[index])
        atomicStore(s.inputReady, true, moRelease)
      else:
        yieldRpcIo()
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
  ## Request retirement without blocking a dispatcher turn.
  let s = stream.exchange
  if s != nil: atomicStore(s.stopping, true, moRelease)

proc `=copy`*(dest: var RpcWireStream, source: RpcWireStream) {.error.}

proc `=dup`*(source: RpcWireStream): RpcWireStream {.error.}

proc `=destroy`*(stream: RpcWireStream) =
  ## Shutdown waits only for the bounded operation already owned by the worker.
  let s = stream.exchange
  if s != nil:
    atomicStore(s.stopping, true, moRelease)
    while not atomicLoad(s.done, moAcquire):
      pollRpcStreams()
      discard pause(1000)
    `=destroy`(s[])
    dealloc(s)

proc `=wasMoved`*(stream: var RpcWireStream) {.nodestroy.} =
  ## Move cleanup authority while the task retains the same address.
  stream.exchange = nil

proc start*(stream: var RpcWireStream, fd: cint) =
  ## Transfer a configured accepted descriptor into stock stream ownership.
  assert not stream.active and fd >= 0
  let s = cast[ptr StreamExchange](alloc0(sizeof(StreamExchange)))
  s[] = default(StreamExchange)
  stream.exchange = s
  submit(delay(run(fd, s)), -1)

proc takeInput*(stream: var RpcWireStream, chunk: var string): bool =
  ## The dispatcher takes one bounded chunk without borrowing the reader.
  let s = stream.exchange
  if s == nil or not atomicLoad(s.inputReady, moAcquire): return false
  chunk = move(s.input)
  atomicStore(s.inputReady, false, moRelease)
  true

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
  s.output = move(output)
  s.outputDeadline = afterMs(5000)
  atomicStore(s.outputReady, true, moRelease)
