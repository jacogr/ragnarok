# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stock WebSocket read/write task adapters carry detached bridge bytes only.
## The caller owns the HTTP listener, stable bridge/task-state storage and joined IO-runtime lifetime.
## An idle stock recv cannot yet be interrupted by bridge closure: retain storage until both tasks finish.

import std/[atomics, websocket, ioring]
import std/httpserver as http
import ./transport_bridge as transport
import ./wire
import ../lib/socket_io as native_io

type WebSocketTaskState* = object
  ## One task publishes progress atomically; the dispatcher never touches its socket half.
  done: bool
  frames: uint64

proc completed*(state: var WebSocketTaskState): bool =
  ## Joining code observes completion only after the task has retired its IO half.
  atomicLoad(state.done, moAcquire)

proc transferred*(state: var WebSocketTaskState): uint64 =
  ## Scalar observations carry no authority over the task's socket or queue state.
  atomicLoad(state.frames, moAcquire)

proc progress(state: ptr WebSocketTaskState) =
  ## Each state has one producer; guarded counting cannot wrap into false progress.
  let count = atomicLoad(state.frames, moRelaxed)
  if count < high(uint64): atomicStore(state.frames, count + 1, moRelease)

proc yieldTransport() {.passive.} =
  ## Public reactor timeout yields a bounded task turn without blocking a pool worker on a native sleep.
  let continuation = delay()
  discard submitTimeout(afterMs(1), continuation)
  suspend()

proc pollWebSocketTransport*() =
  ## Drive the caller's public IO lane before entering canonical dispatch; passive waits may help tasks there.
  var completions = default(array[transport.BridgeConnections * 2, IoCompletion])
  discard pollCompletions(completions)

proc retire(bridge: ptr transport.RpcTransportBridge,
    connection: transport.BridgeTicket) {.passive.} =
  ## A busy critical section delays retirement rather than losing the close request.
  while bridge[].close(connection) == transport.Busy:
    yieldTransport()

proc listenRpcWebSocket*(port: uint16): http.HttpServer =
  ## Adopt an already configured loopback descriptor through HttpServer's public fields.
  ## A negative fd signals startup failure. Darwin peers inherit SO_NOSIGPIPE from listenLoopback.
  http.HttpServer(fd: native_io.listenLoopback(port, cint(transport.BridgeConnections)),
    tags: http.newHttpTags(), headMs: http.DefaultHeadMs, requestMs: http.DefaultRequestMs,
    idleMs: http.DefaultIdleMs, maxRequests: http.DefaultMaxRequests, serverName: "",
    checkTargets: true, compression: false, compressLevel: http.DefaultCompressLevel,
    compressMinLen: http.DefaultCompressMinLen)

proc upgradeRpcWebSocket*(connection: var http.HttpConnection, uiPort: uint16 = 0): WebSocket {.
    passive, raises.} =
  ## Existing RPC route/origin/body policy precedes the stock RFC handshake and message framing.
  for field in ["Host", "Origin", "Connection", "Upgrade"]:
    if connection.countRequestHeader(field) > 1:
      connection.close()
      raise ProtocolError
  if connection.target != "/" or connection.requestHeader("Host").len == 0 or
      connection.countRequestHeader("Content-Length") > 0 or
      connection.countRequestHeader("Transfer-Encoding") > 0:
    connection.close()
    raise ProtocolError
  let origin = connection.requestHeader("Origin")
  if connection.countRequestHeader("Origin") > 0:
    let suffix = if uiPort == 80: "" else: ":" & $uiPort
    if uiPort == 0 or origin notin ["http://127.0.0.1" & suffix, "http://localhost" & suffix]:
      connection.close()
      raise ProtocolError
  result = upgradeWebSocket(connection, maxMessage = MaxMessage)

proc readWebSocket*(input: sink WebSocketReader, bridge: ptr transport.RpcTransportBridge,
    connection: transport.BridgeTicket, state: ptr WebSocketTaskState) {.passive.} =
  ## One owner receives; it publishes neither ClientInfo nor provider/state handles to another task.
  var reader = input
  var running = true
  var closeDelivered = false
  while running:
    let credit = bridge[].readCredit(connection)
    if credit in [transport.Stale, transport.Closed]: break
    if credit != transport.Ready:
      yieldTransport()
      continue
    var payload = ""
    var kind = mkText
    try:
      kind = reader.recv(payload)
    except ErrorCode:
      break # The owner closes its own half after EOF, protocol refusal or IO failure.
    var message = default(transport.BridgeMessage)
    case kind
    of mkText: message = transport.BridgeMessage(kind: transport.Text, payload: move(payload))
    of mkBinary: message = transport.BridgeMessage(kind: transport.Binary, payload: move(payload))
    of mkPing: message = transport.BridgeMessage(kind: transport.Ping, payload: move(payload))
    of mkPong: message = transport.BridgeMessage(kind: transport.Pong, payload: move(payload))
    of mkClose:
      # The bare stock reader already strips the two-byte code from the returned reason.
      message = transport.BridgeMessage(kind: transport.Close, code: reader.closeCode,
          payload: move(payload))
      running = false
    while true:
      # Busy preserves message ownership; no reader spins or drops a frame behind the dispatcher.
      let published = bridge[].publish(connection, message)
      if published == transport.Ready:
        if kind == mkClose: closeDelivered = true
        state.progress()
        break
      if published notin [transport.Busy, transport.Full]:
        running = false
        break
      yieldTransport()
  reader.close()
  # A received close is acknowledged by the sole writer before dispatcher retirement.
  if not closeDelivered: bridge.retire(connection)
  atomicStore(state.done, true, moRelease)

proc writeWebSocket*(output: sink WebSocketWriter, bridge: ptr transport.RpcTransportBridge,
    connection: transport.BridgeTicket, state: ptr WebSocketTaskState) {.passive.} =
  ## One writer serializes replies, notifications and control frames; its credit spans the entire send.
  var writer = output
  var running = true
  while running:
    var delivery = default(transport.BridgeWrite)
    var message = default(transport.BridgeMessage)
    let taken = bridge[].take(connection, delivery, message)
    if taken in [transport.Stale, transport.Closed]: break
    if taken != transport.Ready:
      yieldTransport()
      continue
    var sent = false
    try:
      case message.kind
      of transport.Text: writer.send(mkText, message.payload)
      of transport.Binary: writer.send(mkBinary, message.payload)
      of transport.Ping: writer.send(mkPing, message.payload)
      of transport.Pong: writer.send(mkPong, message.payload)
      of transport.Close:
        if message.code == 0: writer.close()
        else: writer.close(message.code, message.payload)
        running = false
      of transport.None: discard # None releases dispatcher credit and is never queued.
      sent = true
    except ErrorCode:
      discard # Failed send is acknowledged once and retires only this generation.
    while bridge[].complete(delivery, sent) == transport.Busy:
      yieldTransport()
    if not sent: break
    state.progress()
  writer.abort()
  bridge.retire(connection)
  atomicStore(state.done, true, moRelease)
