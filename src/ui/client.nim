# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Browser console compiled by the pinned Nimony JS backend. rpc.nim owns multiplexed transport
## state; this module owns clientInfo presentation and DOM updates; importjs bindings bridge browser events, timers and JSON values. The native
## source checker skips this target-specific body; make ui-assets compiles it with ragnarokBrowser.

when defined(ragnarokBrowser):
  import ./rpc
  import ../app/cli/defaults as cli_defaults

  # Browser bindings touch textContent only; backend strings never become executable HTML.
  proc text(id, value: string) {.importjs: "document.getElementById(#).textContent = #".}
  proc disabled(id: string, value: bool) {.importjs: "document.getElementById(#).disabled = #".}
  proc input(id: string): string {.importjs: "document.getElementById(#).value".}
  proc clicked(id: string, action: Action) {.importjs: "document.getElementById(#).addEventListener('click', #)".}
  proc defaultEndpoint(port: string): string {.importjs: "'ws://' + location.hostname + ':' + # + '/'".}
  proc inputValue(id, value: string) {.importjs: "document.getElementById(#).value = #".}
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
  var responses {.threadvar.}: int

  # One-shot results are independent of every other outstanding call or subscription stream.
  proc infoReply(identity: int, status: RpcStatus, message: string) =
    case status
    of RpcStatus.Success:
      text("response", formatted(message))
      if responses < 2_147_483_647: inc responses # The display counter never wraps.
      text("responses", $responses)
      text("implementation", field(message, "implementation"))
      text("peers", field(message, "connectedPeers"))
      text("uptime", field(message, "uptimeMs") & " ms")
      text("status", "Connected")
    of RpcStatus.RemoteError:
      text("response", formatted(message))
      text("status", "RPC error")
    of RpcStatus.TimedOut:
      text("status", "Request timed out") # Other calls and active streams remain usable.
    else:
      discard # Connection lifecycle owns disconnect/error display after settling pending calls.

  # Refresh can run while earlier calls or subscription updates are in flight.
  proc requestInfo() =
    if not connected: return
    let identity = call("ragnarok_clientInfo", "[]", infoReply)
    if connected:
      text("status", (if identity != 0: "Reading client info…" else: "Too many pending requests"))

  # Connection callbacks own only DOM state; rpc.nim retires all request and stream callbacks.
  proc opened() =
    connected = true
    disabled("refresh", false)
    text("status", "Connected")
    requestInfo()

  proc closed(status: RpcStatus) =
    connected = false
    disabled("refresh", true)
    text("status", (if status == RpcStatus.ConnectionClosed: "Disconnected" else: "Connection failed"))

  proc disconnect() =
    closeRpc()
    closed(RpcStatus.ConnectionClosed)

  proc connect() =
    disconnect() # A replacement socket starts with no outstanding calls or subscriptions.
    let endpoint = input("endpoint")
    if endpoint.len == 0 or endpoint.len > 1024:
      text("status", "Enter a WebSocket URL")
      return
    text("status", "Connecting…")
    if not openRpc(endpoint, opened, closed):
      text("status", "Invalid WebSocket URL")

  proc startUi*() {.exportc: "ragnarokUiStart".} =
    ## An exported browser entry keeps the host-driven JS runtime alive after module initialization.
    if initialized: return # Repeated host initialization must not attach duplicate listeners.
    initialized = true
    inputValue("endpoint", defaultEndpoint($DefaultRpcPort))
    clicked("connect", connect)
    clicked("disconnect", disconnect)
    clicked("refresh", requestInfo)
    disabled("refresh", true)
    text("status", "Disconnected")
    text("app-state", "Ready")

  startUi() # A deferred classic script initializes after the page's DOM has been parsed.
