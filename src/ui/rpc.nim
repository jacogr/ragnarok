# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Browser WebSocket JSON-RPC client: bounded concurrent calls and independently routed subscriptions.
## Reply IDs and subscription IDs have separate lifetimes. Capture-free callbacks own no browser handles.
## Call/subscribe/unsubscribe return zero when disconnected, invalid or full; accepted calls settle once.
## Subscription callbacks receive Success updates or one terminal error/disconnect, then retire.

when defined(ragnarokBrowser):
  const MaxPendingRequests* = 16
  const MaxSubscriptions* = 8

  type
    RpcStatus* = enum Success, RemoteError, TimedOut, ConnectionClosed, TransportError,
      InvalidResponse, Unsubscribed
      ## Success carries an envelope; all other statuses are explicit failures, possibly without JSON.
    Action* = proc() {.nimcall.} ## Browser event callbacks retain no captured Nim resources.
    ReplyHandler* = proc(identity: int, status: RpcStatus,
        message: string) {.nimcall.} ## Exactly one completion per accepted request.
    UpdateHandler* = proc(identity: uint32, status: RpcStatus,
        message: string) {.nimcall.} ## Success repeats until a terminal status.
    CloseHandler* = proc(status: RpcStatus) {.nimcall.} ## One lifecycle notification per connection teardown.
    Message = proc(message: string) {.nimcall.} ## Copy bounded browser text into Nim.
    RequestKind = enum Call, Subscribe, Unsubscribe ## Subscription acknowledgements have their own lifecycle.
    PendingRequest = object ## Owned callback/selector record; zero ID denotes a free slot.
      id: int
      deadline: float64
      kind: RequestKind
      reply: nil ReplyHandler
      update: nil UpdateHandler
      methodName: string
      subscription: uint32
    Subscription = object ## Server-issued ID and exact notification method route an active stream.
      id: uint32
      methodName: string
      update: nil UpdateHandler

  var connected {.threadvar.}: bool
  var nextId {.threadvar.}: int
  var timer {.threadvar.}: int
  var generation {.threadvar.}: int
  var requests {.threadvar.}: array[MaxPendingRequests, PendingRequest]
  var subscriptions {.threadvar.}: array[MaxSubscriptions, Subscription]
  var onOpened {.threadvar.}: nil Action
  var onClosed {.threadvar.}: nil CloseHandler

  # Browser objects stay in the host; old sockets lose callbacks before a replacement can open.
  proc stopSocket() {.importjs: """
    (() => { const s = globalThis.ragnarokRpcSocket; globalThis.ragnarokRpcSocket = null;
      if (s) { s.onopen = s.onmessage = s.onclose = s.onerror = null; s.close(); }
    })()
  """.}
  proc openSocket(url: string, opened, closed, failed: Action,
      message: Message): bool {.importjs: """
    ((url, opened, closed, failed, message) => { try {
      const endpoint = new URL(url);
      if (!['ws:', 'wss:'].includes(endpoint.protocol) || endpoint.username || endpoint.password) return false;
      const s = new WebSocket(endpoint.href); globalThis.ragnarokRpcSocket = s;
      s.onopen = () => { if (globalThis.ragnarokRpcSocket === s) opened(); };
      s.onclose = () => { if (globalThis.ragnarokRpcSocket === s) closed(); };
      s.onerror = () => { if (globalThis.ragnarokRpcSocket === s) failed(); };
      s.onmessage = e => { if (globalThis.ragnarokRpcSocket === s) {
        if (typeof e.data === 'string' && e.data.length <= 65535) message(e.data);
        else failed();
      } };
      return true;
    } catch (_) { return false; } })(#, #, #, #, #)
  """.}
  proc sendSocket(message: string): bool {.importjs: """
    ((message) => { const s = globalThis.ragnarokRpcSocket;
      if (!s || s.readyState !== WebSocket.OPEN) return false;
      try { s.send(message); return true; } catch (_) { return false; }
    })(#)
  """.}
  proc now(): float64 {.importjs: "performance.now()".}
  proc later(action: Action): int {.importjs: "setTimeout(#, 25)".}
  proc cancel(timer: int) {.importjs: "clearTimeout(#)".}

  # Scalar extraction is strict; unknown/malformed messages cannot consume a pending request.
  proc replyId(message: string): int {.importjs: """
    ((s) => { try { const d = JSON.parse(s);
      return d && !Array.isArray(d) && d.jsonrpc === '2.0' && Number.isInteger(d.id) &&
        d.id > 0 && d.id <= 2147483647 ? d.id : 0;
    } catch (_) { return 0; } })(#)
  """.}
  proc validReply(message: string): bool {.importjs: """
    ((s) => { try { const d = JSON.parse(s), own = k => Object.prototype.hasOwnProperty.call(d, k);
      return !own('method') && (own('result') !== own('error')) && (!own('error') ||
        (d.error && Number.isInteger(d.error.code) && typeof d.error.message === 'string'));
    } catch (_) { return false; } })(#)
  """.}
  proc succeeded(message: string): bool {.importjs:
    "Object.prototype.hasOwnProperty.call(JSON.parse(#), 'result')".}
  proc subscriptionResult(message: string): uint32 {.importjs: """
    ((s) => { const id = JSON.parse(s).result;
      return Number.isInteger(id) && id > 0 && id <= 4294967295 ? id : 0; })(#)
  """.}
  proc unsubscribeResult(message: string): bool {.importjs:
    "typeof JSON.parse(#).result === 'boolean'".}
  proc notificationId(message: string): uint32 {.importjs: """
    ((s) => { try { const d = JSON.parse(s), p = d.params;
      if (!d || Array.isArray(d) || d.jsonrpc !== '2.0' || 'id' in d || typeof d.method !== 'string' ||
          !p || typeof p !== 'object' || Array.isArray(p)) return 0;
      const own = k => Object.prototype.hasOwnProperty.call(p, k);
      return Number.isInteger(p.subscription) && p.subscription > 0 && p.subscription <= 4294967295 &&
        own('result') !== own('error') && (!own('error') || typeof p.error === 'string') ? p.subscription : 0;
    } catch (_) { return 0; } })(#)
  """.}
  proc notificationMethod(message: string): string {.importjs: "JSON.parse(#).method".}
  proc terminal(message: string): bool {.importjs:
    "Object.prototype.hasOwnProperty.call(JSON.parse(#).params, 'error')".}
  proc requestText(id: int, methodName, parameters: string): string {.importjs: """
    ((id, method, text) => { try { const params = JSON.parse(text);
      if (!Array.isArray(params)) return '';
      const value = JSON.stringify({jsonrpc: '2.0', method, params, id});
      return new TextEncoder().encode(value).length <= 16384 ? value : '';
    } catch (_) { return ''; } })(#, #, #)
  """.}

  # Clear owned records in place, including callback borrows and retained method strings.
  proc clearRequest(index: int) =
    requests[index].id = 0
    requests[index].deadline = 0
    requests[index].kind = RequestKind.Call
    requests[index].reply = nil
    requests[index].update = nil
    requests[index].methodName = ""
    requests[index].subscription = 0

  proc clearSubscription(index: int) =
    subscriptions[index].id = 0
    subscriptions[index].methodName = ""
    subscriptions[index].update = nil

  # Empty slots contain nullable callbacks; occupied records validate these before invocation.
  proc deliver(callback: nil ReplyHandler, identity: int, status: RpcStatus, message: string) =
    if callback != nil: callback(identity, status,
        message) # Nullable storage never becomes an unchecked indirect call.

  # Streams always carry their selector, including local termination without a JSON envelope.
  proc publish(callback: nil UpdateHandler, identity: uint32, status: RpcStatus, message: string) =
    if callback != nil: callback(identity, status,
        message) # Shared handlers can distinguish simultaneous streams.

  # Detach all state before callbacks; callbacks may open another connection without losing its records.
  proc retire(reason: RpcStatus) =
    stopSocket()
    connected = false
    if generation == 2_147_483_647: generation = 0 # Avoid target integer wrap.
    else: inc generation
    if timer != 0: cancel(timer) # No old deadline can fire into a replacement connection.
    timer = 0
    let pending = requests
    let active = subscriptions
    let closed = onClosed
    for i in 0..<MaxPendingRequests: clearRequest(i) # Release every pending owner before callbacks.
    for i in 0..<MaxSubscriptions: clearSubscription(i) # No old stream survives connection retirement.
    onOpened = nil
    onClosed = nil
    for item in pending:
      if item.id != 0: deliver(item.reply, item.id, reason,
          "") # Each accepted request receives one explicit terminal result.
    for item in active:
      if item.id != 0: publish(item.update, item.id, reason, "") # Remote subscriptions end with the socket.
    if closed != nil: closed(reason) # Report only a connection with an installed lifecycle owner.

  proc closeRpc*() =
    ## Disconnect explicitly, retiring every pending request and active subscription once.
    retire(RpcStatus.ConnectionClosed)

  # One bounded deadline sweep serves independent calls; ambiguous subscription timeouts retire the socket.
  proc tick() =
    timer = 0
    let epoch = generation
    let instant = now()
    for i in 0..<MaxPendingRequests:
      if requests[i].id != 0 and requests[i].deadline <= instant:
        if requests[i].kind != RequestKind.Call:
          retire(RpcStatus.TimedOut) # A lost subscribe/unsubscribe ACK leaves unknown remote state.
          return
        let callback = requests[i].reply
        let identity = requests[i].id
        clearRequest(i)
        deliver(callback, identity, RpcStatus.TimedOut, "")
        if epoch != generation: return # A completion may synchronously replace the connection.
    for item in requests:
      if item.id != 0:
        if timer == 0: timer = later(tick) # A reentrant callback may already have scheduled the sweep.
        return

  # Reserve capacity for active and not-yet-acknowledged subscriptions before sending any request.
  proc beginRequest(kind: RequestKind, methodName, parameters: string, reply: ReplyHandler,
      update: nil UpdateHandler, subscription: uint32, timeoutMs: int): int =
    if not connected or methodName.len == 0 or methodName.len > 128 or parameters.len > 16384 or
        timeoutMs < 1 or timeoutMs > 60000 or nextId == 2_147_483_647: return 0
    var slot = -1
    var reserved = 0
    for i in 0..<MaxPendingRequests:
      if requests[i].id == 0: slot = i # Any free fixed slot can own this independently identified call.
      elif requests[i].kind == RequestKind.Subscribe: inc reserved
      elif kind == RequestKind.Unsubscribe and requests[i].kind == RequestKind.Unsubscribe and
          requests[i].subscription == subscription: return 0 # Only one retirement per active subscription.
    if slot < 0: return 0 # Backpressure is explicit; no unbounded request queue is retained.
    for item in subscriptions:
      if item.id != 0: inc reserved # Pending unsubscribe remains active until its acknowledgement.
    if kind == RequestKind.Subscribe and (update == nil or reserved >= MaxSubscriptions): return 0
    inc nextId # IDs never wrap or alias late replies during this page's lifetime.
    let identity = nextId
    let message = requestText(identity, methodName, parameters)
    if message.len == 0: return 0 # Invalid positional parameters never enter the outstanding table.
    requests[slot].id = identity
    requests[slot].deadline = now() + float64(timeoutMs)
    requests[slot].kind = kind
    requests[slot].reply = reply
    requests[slot].update = update
    requests[slot].methodName = methodName
    requests[slot].subscription = subscription
    if not sendSocket(message):
      retire(RpcStatus.TransportError) # Also resolve the just-reserved request when sending fails.
      return identity
    if timer == 0: timer = later(tick) # Existing requests keep their own deadlines.
    identity

  proc call*(methodName, parameters: string, reply: ReplyHandler, timeoutMs = 5000): int =
    ## Send a positional JSON-RPC call; zero means rejected before acceptance, otherwise reply settles once.
    beginRequest(RequestKind.Call, methodName, parameters, reply, nil, 0, timeoutMs)

  proc subscribe*(methodName, parameters: string, reply: ReplyHandler, update: UpdateHandler,
      timeoutMs = 5000): int =
    ## Reserve an independent JIP-2 stream; its ACK returns a server uint32 ID, then updates route by ID/method.
    beginRequest(RequestKind.Subscribe, methodName, parameters, reply, update, 0, timeoutMs)

  proc unsubscribe*(methodName: string, subscription: uint32, reply: ReplyHandler,
      timeoutMs = 5000): int =
    ## Keep updates alive until a successful boolean unsubscribe ACK; remote errors preserve the stream.
    for item in subscriptions:
      if item.id == subscription and subscription != 0:
        return beginRequest(RequestKind.Unsubscribe, methodName, "[" & $subscription & "]", reply,
            nil, subscription, timeoutMs)
    0 # Unknown/local-retired IDs cannot be unsubscribed accidentally.

  # Acknowledgements settle one request; notifications never consume an unrelated request or its deadline.
  proc received(message: string) =
    let id = replyId(message)
    if id != 0:
      for i in 0..<MaxPendingRequests:
        if requests[i].id == id:
          let item = requests[i]
          if not validReply(message):
            retire(RpcStatus.InvalidResponse) # Malformed ACKs cannot strand remote subscription state.
            return
          if not succeeded(message):
            clearRequest(i) # Remote errors settle only this request.
            deliver(item.reply, item.id, RpcStatus.RemoteError, message)
            return
          var retired: nil UpdateHandler = nil
          if item.kind == RequestKind.Subscribe:
            let identity = subscriptionResult(message)
            var slot = -1
            for j in 0..<MaxSubscriptions:
              if subscriptions[j].id == identity and identity != 0:
                retire(RpcStatus.InvalidResponse) # Duplicate server IDs cannot route two streams safely.
                return
              if subscriptions[j].id == 0: slot = j # Reservation guarantees capacity unless the peer misbehaves.
            if identity == 0 or slot < 0:
              retire(RpcStatus.InvalidResponse)
              return
            subscriptions[slot].id = identity
            subscriptions[slot].methodName = item.methodName
            subscriptions[slot].update = item.update
          elif item.kind == RequestKind.Unsubscribe:
            if not unsubscribeResult(message):
              retire(RpcStatus.InvalidResponse)
              return
            for j in 0..<MaxSubscriptions:
              if subscriptions[j].id == item.subscription:
                retired = subscriptions[j].update
                clearSubscription(j) # Both true/false ACKs confirm no remote stream remains.
          clearRequest(i) # Release before callbacks permit reentrant calls.
          publish(retired, item.subscription, RpcStatus.Unsubscribed, "")
          deliver(item.reply, item.id, RpcStatus.Success, message)
          return
      return # Unknown/duplicate/stale reply IDs leave all active work unchanged.
    let identity = notificationId(message)
    if identity == 0: return # Malformed messages and unknown notification envelopes have no effects.
    for i in 0..<MaxSubscriptions:
      if subscriptions[i].id == identity and subscriptions[i].methodName == notificationMethod(message):
        let callback = subscriptions[i].update
        let ended = terminal(message)
        if ended: clearSubscription(i) # Terminal errors retire before invoking user code.
        publish(callback, identity, (if ended: RpcStatus.RemoteError else: RpcStatus.Success), message)
        return

  # Socket callbacks have no captures and are detached on every retirement/replacement path.
  proc opened() =
    connected = true
    if onOpened != nil: onOpened() # A ready callback can immediately issue multiple independent requests.

  proc socketClosed() = retire(RpcStatus.ConnectionClosed)
  proc failed() = retire(RpcStatus.TransportError)

  proc openRpc*(url: string, ready: Action, closed: CloseHandler): bool =
    ## Replace the page's connection; ready may call/subscribe, while every old request/stream retires.
    let previous = generation
    closeRpc()
    let expected = (if previous == 2_147_483_647: 0 else: previous + 1)
    if generation != expected: return false # A cleanup callback opened a newer connection; preserve its ownership.
    onOpened = ready
    onClosed = closed
    if not openSocket(url, opened, socketClosed, failed, received):
      onOpened = nil
      onClosed = nil
      return false
    true
