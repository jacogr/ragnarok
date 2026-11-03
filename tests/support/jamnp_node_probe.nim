# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent multi-stream TLS probe observes byte transcripts, FIN and reset without production encoders.
import std/[assertions, envvars, syncio]
import ../../src/quic/transport
import ../../src/jamnp-s/protocol

type
  ProbeFlow* = object ## Stable slots retain observations after their native handle retires.
    handle: NativeStream
    number*: NativeStreamId
    output, input: seq[byte]
    offset: int
    enabled, persistent: bool
    opened*, sentFin*, receivedFin*, reset*, closed*: bool
  NodeProbe* = object ## One authenticated client owns fixed flow storage through engine retirement.
    transport: Transport
    flows*: array[16, ProbeFlow]
    issued, opened: int
    expected: array[32, byte]
proc `=copy`(destination: var NodeProbe, source: NodeProbe) {.error.}
  ## Native callbacks borrow exactly one stable probe address.
proc `=dup`(source: NodeProbe): NodeProbe {.error.}
  ## Initialization must not duplicate an owning transport aggregate.
proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Independently read raw fixture key pins the node identity before opening streams.
  let probe = cast[ptr NodeProbe](user)
  cint(validPeer(cast[ptr byte](der), length, probe.expected))
proc event(user: pointer, stream: NativeStream, kind: cint) {.cdecl, raises: [].} =
  ## Each callback performs one bounded chunk and never accesses canonical state.
  let probe = cast[ptr NodeProbe](user)
  var position = -1
  if kind == 0:
    assert probe.opened < probe.issued
    position = probe.opened
    inc probe.opened
    probe.flows[position].handle = stream
    probe.flows[position].number = stream.streamId
    probe.flows[position].opened = true
    wantRead(stream, 1)
    wantWrite(stream, cint(probe.flows[position].enabled))
    return
  for index in 0..<probe.opened:
    if probe.flows[index].handle == stream:
      position = index
      break # Exact handle matching prevents late events from updating another transcript.
  if position < 0: return
  let flow = addr probe.flows[position]
  case kind
  of 1:
    var bytes = default(array[4096, byte])
    let amount = streamRead(stream, addr bytes[0], csize_t(bytes.len))
    if amount == -2: return
    if amount <= 0:
      if amount == 0:
        flow.receivedFin = true
        readDone(stream)
      else: flow.reset = true # Reset must never masquerade as an empty successful message.
      wantRead(stream, 0)
    else:
      assert amount <= int64(bytes.len) and flow.input.len+int(amount) <= 8388608
      for index in 0..<int(amount): flow.input.add(bytes[index])
  of 2:
    if flow.offset < flow.output.len:
      let amount = streamWrite(stream, addr flow.output[flow.offset],
        csize_t(min(4096, flow.output.len-flow.offset)))
      if amount == -2: return
      assert amount >= 0 and amount <= int64(flow.output.len-flow.offset)
      flow.offset += int(amount)
    if flow.offset == flow.output.len:
      wantWrite(stream, 0)
      discard streamFlush(stream)
      if not flow.persistent and not flow.sentFin:
        flow.sentFin = true
        streamFin(stream) # Persistent probes deliberately withhold FIN even when their send queue is empty.
  of 3:
    flow.closed = true
    flow.handle = NativeStream(nil)
  of 4:
    let alreadyReset = flow.reset
    flow.reset = true
    wantRead(stream, 0)
    wantWrite(stream, 0)
    if not alreadyReset: streamAbort(stream) # Retire our directions as well as observing the peer's directional reset.
  else: discard # Other native events do not establish protocol success.
proc open*(probe: var NodeProbe, port: uint16) {.raises.} =
  ## A fresh engine presents the second certificate while pinning the node's first certificate.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  assert raw.len == 32
  for index in 0..<32: probe.expected[index] = byte(raw[index])
  assert openTransport(probe.transport, false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), "jamnp-s/1/00000000", addr probe, verify, event,
    idleSeconds = 30, keepalive = true)
  assert probe.transport.connectTransport(port)
proc close*(probe: var NodeProbe) =
  ## Final transport callbacks run while every fixed transcript slot remains alive.
  closeTransport(probe.transport)
proc poll*(probe: var NodeProbe) =
  ## Host polling never overlaps another native executable or mutates shared native libraries.
  assert probe.transport.pollTransport(0)
proc authenticated*(probe: NodeProbe): bool =
  ## TLS completion is a prerequisite, not proof of application framing or FIN.
  probe.transport.authenticatedConnections > 0
proc issue*(probe: var NodeProbe, wire: seq[byte], persistent = false, enabled = true): int =
  ## Intent data is installed before the native engine may synchronously report its new stream.
  assert probe.issued < probe.flows.len
  result = probe.issued
  probe.flows[result].output = wire
  probe.flows[result].persistent = persistent
  probe.flows[result].enabled = enabled
  inc probe.issued
  probe.transport.openStream()
proc enable*(probe: var NodeProbe, index: int, finish = false) =
  ## A separate host gate releases delayed selector bytes or a request FIN.
  assert index >= 0 and index < probe.issued and probe.flows[index].opened
  if finish: probe.flows[index].persistent = false
  probe.flows[index].enabled = true
  wantWrite(probe.flows[index].handle, 1)
proc abort*(probe: var NodeProbe, index: int) =
  ## Cancellation retains transcript storage through the eventual native close callback.
  if probe.flows[index].handle != NativeStream(nil): streamAbort(probe.flows[index].handle)
proc bytes*(probe: NodeProbe, index: int): seq[byte] =
  ## Copy the observed transcript to keep test mutations independent of callback-owned buffers.
  result = @[]
  for octet in probe.flows[index].input: result.add(octet)
