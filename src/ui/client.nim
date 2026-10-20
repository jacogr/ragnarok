# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Browser prototype compiled by the pinned Nimony JS backend. Nim owns connection/request state
## and DOM updates; importjs bindings bridge browser events, timers and JSON values. The native
## source checker skips this target-specific body; make ui-assets compiles it with ragnarokBrowser.

when defined(ragnarokBrowser):
  type
    Action = proc() {.nimcall.} ## Capture-free callbacks outlive their synchronous registration call.
    Message = proc(text: string) {.nimcall.} ## A bounded text frame is copied across the JS/Nim bridge.

  # Browser bindings touch textContent only; backend strings never become executable HTML.
  proc text(id, value: string) {.importjs: "document.getElementById(#).textContent = #".}
  proc disabled(id: string, value: bool) {.importjs: "document.getElementById(#).disabled = #".}
  proc input(id: string): string {.importjs: "document.getElementById(#).value".}
  proc clicked(id: string, action: Action) {.importjs: "document.getElementById(#).addEventListener('click', #)".}
  proc defaultEndpoint(): string {.importjs: "'ws://' + location.hostname + ':19800/'".}
  proc inputValue(id, value: string) {.importjs: "document.getElementById(#).value = #".}
  proc later(action: Action, milliseconds: int): int {.importjs: "setTimeout(#, #)".}
  proc cancel(timer: int) {.importjs: "clearTimeout(#)".}

  # One socket belongs to this page. Detach callbacks before retiring it; stale events cannot
  # change the state of a replacement connection. Browser objects stay in the JS host.
  proc stopSocket() {.importjs: """
    (() => { const s = globalThis.ragnarokPrototypeSocket;
      globalThis.ragnarokPrototypeSocket = null;
      if (s) { s.onopen = s.onmessage = s.onclose = s.onerror = null; s.close(); }
    })()
  """.}
  proc openSocket(url: string, opened, closed, failed: Action,
      message: Message): bool {.importjs: """
    ((url, opened, closed, failed, message) => {
      try {
        const endpoint = new URL(url);
        if (!['ws:', 'wss:'].includes(endpoint.protocol) || endpoint.username || endpoint.password) return false;
        const s = new WebSocket(endpoint.href);
        globalThis.ragnarokPrototypeSocket = s;
        s.onopen = () => { if (globalThis.ragnarokPrototypeSocket === s) opened(); };
        s.onclose = () => { if (globalThis.ragnarokPrototypeSocket === s) {
          globalThis.ragnarokPrototypeSocket = null; closed(); } };
        s.onerror = () => { if (globalThis.ragnarokPrototypeSocket === s) failed(); };
        s.onmessage = e => { if (globalThis.ragnarokPrototypeSocket === s) {
          if (typeof e.data === 'string' && e.data.length <= 65535) message(e.data);
          else { failed(); s.close(); }
        } };
        return true;
      } catch (_) { return false; }
    })(#, #, #, #, #)
  """.}
  proc sendSocket(message: string): bool {.importjs: """
    ((message) => { const s = globalThis.ragnarokPrototypeSocket;
      if (!s || s.readyState !== WebSocket.OPEN) return false;
      try { s.send(message); return true; } catch (_) { return false; }
    })(#)
  """.}

  # JSON stays in browser values across these narrow bindings; only scalar IDs and display strings
  # enter Nim. Replies must match the one pending numeric request before they update the DOM.
  proc replyId(message: string): int {.importjs: """
    ((s) => { try { const d = JSON.parse(s);
      return d && d.jsonrpc === '2.0' && Number.isInteger(d.id) && d.id > 0 && d.id <= 2147483647 ? d.id : 0;
    } catch (_) { return 0; } })(#)
  """.}
  proc succeeded(message: string): bool {.importjs: """
    ((s) => { try { const d = JSON.parse(s);
      return Object.prototype.hasOwnProperty.call(d, 'result') && !Object.prototype.hasOwnProperty.call(d, 'error');
    } catch (_) { return false; } })(#)
  """.}
  proc formatted(message: string): string {.importjs: """
    ((s) => { try { return JSON.stringify(JSON.parse(s), null, 2); } catch (_) { return s; } })(#)
  """.}
  proc field(message, name: string): string {.importjs: """
    ((s, key) => { try { const value = JSON.parse(s).result[key];
      return typeof value === 'string' || typeof value === 'number' ? String(value) : '—';
    } catch (_) { return '—'; } })(#, #)
  """.}

  var initialized {.threadvar.}: bool
  var connected {.threadvar.}: bool
  var pending {.threadvar.}: bool
  var requestId {.threadvar.}: int
  var responses {.threadvar.}: int
  var timer {.threadvar.}: int

  # Retire the timer before any state transition; only one RPC request is pending at a time.
  proc clearPending() =
    if timer != 0: cancel(timer) # A response, disconnect or reconnect cancels the old deadline.
    timer = 0
    pending = false
    disabled("refresh", not connected)

  # A silent endpoint cannot leave the refresh button permanently disabled.
  proc timedOut() =
    clearPending()
    text("status", "Request timed out")

  # The browser owns JSON serialization; the only dynamic field is a bounded numeric request ID.
  proc infoRequest(id: int): string {.importjs:
    "JSON.stringify({jsonrpc: '2.0', method: 'ragnarok_clientInfo', params: [], id: #})".}

  # Send exactly the requested prototype endpoint, with bounded monotonically changing IDs.
  proc requestInfo() =
    if not connected or pending: return
    if requestId >= 2_147_483_647: requestId = 1 # Avoid 32-bit integer wrap in the browser target.
    else: inc requestId
    let request = infoRequest(requestId)
    if sendSocket(request):
      pending = true
      disabled("refresh", true)
      text("status", "Reading client info…")
      timer = later(timedOut, 5000)
    else:
      connected = false
      clearPending()
      text("status", "Connection unavailable")

  # Bridge callbacks own no captured native resources; their state belongs to this page module.
  proc opened() =
    connected = true
    text("status", "Connected")
    requestInfo()

  proc closed() =
    connected = false
    clearPending()
    text("status", "Disconnected")

  proc failed() =
    connected = false
    clearPending()
    text("status", "Connection failed")

  proc received(message: string) =
    if not pending or replyId(message) != requestId: return # Ignore unsolicited or stale replies.
    clearPending()
    text("response", formatted(message))
    if succeeded(message):
      if responses < 2_147_483_647: inc responses # The display counter never wraps.
      text("responses", $responses)
      text("implementation", field(message, "implementation"))
      text("peers", field(message, "connectedPeers"))
      text("uptime", field(message, "uptimeMs") & " ms")
      text("status", "Connected")
    else:
      text("status", "RPC error") # Keep the error envelope visible for this diagnostic prototype.

  proc disconnect() =
    stopSocket()
    closed()

  proc connect() =
    disconnect() # A replacement socket starts with no borrowed callbacks or outstanding timer.
    let endpoint = input("endpoint")
    if endpoint.len == 0 or endpoint.len > 1024:
      text("status", "Enter a WebSocket URL")
      return
    text("status", "Connecting…")
    if not openSocket(endpoint, opened, closed, failed, received):
      text("status", "Invalid WebSocket URL")

  proc startUi*() {.exportc: "ragnarokUiStart".} =
    ## An exported browser entry keeps the host-driven JS runtime alive after module initialization.
    if initialized: return # Repeated host initialization must not attach duplicate listeners.
    initialized = true
    inputValue("endpoint", defaultEndpoint())
    clicked("connect", connect)
    clicked("disconnect", disconnect)
    clicked("refresh", requestInfo)
    disabled("refresh", true)
    text("status", "Disconnected")
    text("app-state", "Ready")

  startUi() # A deferred classic script initializes after the page's DOM has been parsed.
