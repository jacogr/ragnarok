# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Browser console compiled by the pinned Nimony JS backend. rpc.nim owns multiplexed transport
## state; this module owns clientInfo presentation and DOM updates; importjs bindings bridge browser events, timers and JSON values. The native
## source checker skips this target-specific body; make ui-assets compiles it with ragnarokBrowser.

when defined(ragnarokBrowser):
  import ./rpc
  import ../app/cli/defaults as cli_defaults

  proc text(id, value: string) {.importjs: "document.getElementById(#).textContent = #".}
    ## Browser bindings touch textContent only; backend strings never become executable HTML.

  proc disabled(id: string, value: bool) {.importjs: "document.getElementById(#).disabled = #".}
    ## Set a browser control's disabled state by its element identity.

  proc input(id: string): string {.importjs: "document.getElementById(#).value".}
    ## Read the current text value of the selected browser input.

  proc clicked(id: string, action: Action) {.importjs: "document.getElementById(#).addEventListener('click', #)".}
    ## Register the supplied action for click events on the selected browser control.

  proc defaultEndpoint(port: string): string {.importjs: "'ws://' + location.hostname + ':' + # + '/'".}
    ## Build the page-host WebSocket endpoint using the configured RPC port.

  proc inputValue(id, value: string) {.importjs: "document.getElementById(#).value = #".}
    ## Replace the selected browser input's text value.

  proc formatted(message: string): string {.importjs: """
    ((s) => { try { return JSON.stringify(JSON.parse(s), null, 2); } catch (_) { return s; } })(#)
  """.}
    ## Pretty-print valid JSON for display, preserving the original text when parsing fails.

  proc field(message, name: string): string {.importjs: """
    ((s, key) => { try { const value = JSON.parse(s).result[key];
      return typeof value === 'string' || typeof value === 'number' ? String(value) : '—';
    } catch (_) { return '—'; } })(#, #)
  """.}
    ## Read a printable scalar result field, using a placeholder for absent or invalid values.

  var initialized {.threadvar.}: bool
  var connected {.threadvar.}: bool
  var responses {.threadvar.}: int

  proc infoReply(identity: int, status: RpcStatus, message: string) =
    ## One-shot results are independent of every other outstanding call or subscription stream.
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

  proc requestInfo() =
    ## Refresh can run while earlier calls or subscription updates are in flight.
    if not connected: return
    let identity = call("ragnarok_clientInfo", "[]", infoReply)
    if connected:
      text("status", (if identity != 0: "Reading client info…" else: "Too many pending requests"))

  proc opened() =
    ## Connection callbacks own only DOM state; rpc.nim retires all request and stream callbacks.
    connected = true
    disabled("refresh", false)
    text("status", "Connected")
    requestInfo()

  proc closed(status: RpcStatus) =
    ## Mark the UI disconnected and disable refresh after socket closure or connection failure.
    connected = false
    disabled("refresh", true)
    text("status", (if status == RpcStatus.ConnectionClosed: "Disconnected" else: "Connection failed"))

  proc disconnect() =
    ## Close the RPC connection and reset the displayed connection state.
    closeRpc()
    closed(RpcStatus.ConnectionClosed)

  proc connect() =
    ## Replace the old connection after bounded endpoint validation and update its UI status.
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
