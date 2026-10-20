# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compile the real browser RPC client into an isolated host-driven regression page.
## Exported no-argument actions let Playwright schedule replies, notifications and socket retirement.

when defined(ragnarokBrowser):
  import ../../src/ui/rpc

  var firstSubscription {.threadvar.}: uint32

  # Explicit callback registration retains test actions in the JS backend's reachable graph.
  proc register(name: string, action: Action) {.importjs: "globalThis[#] = #".}
  proc endpoint(): string {.importjs: "globalThis.rpcTestEndpoint || 'ws://127.0.0.1/rpc-test'".}

  # The independent browser harness records callback order and complete envelopes for assertions.
  proc record(label, status, message: string, identity = "") {.importjs: """
    ((label, status, message, identity) => globalThis.rpcEvents.push({label, status,
      id: identity ? Number(identity) : null, message: message ? JSON.parse(message) : null}))(#, #, #, #)
  """.}
  proc accepted(label: string, identity: int) {.importjs:
    "globalThis.rpcAccepted.push({label: #, id: #})".}
  proc resultId(message: string): uint32 {.importjs: "JSON.parse(#).result".}

  # Distinct handlers prove that correlation follows IDs, including out-of-order replies.
  proc firstReply(identity: int, status: RpcStatus, message: string) = record("first", $status,
      message, $identity)
  proc secondReply(identity: int, status: RpcStatus, message: string) = record("second", $status,
      message, $identity)
  proc extraReply(identity: int, status: RpcStatus, message: string) = record("extra", $status,
      message, $identity)
  proc reentrantReply(identity: int, status: RpcStatus, message: string) =
    record("reentrant", $status, message, $identity)
    if status == RpcStatus.TimedOut:
      accepted("after-timeout", call("after-timeout", "[]",
          extraReply)) # Completion can synchronously submit new work.
  proc timeoutReply(identity: int, status: RpcStatus, message: string) = record("timeout", $status,
      message, $identity)
  proc heldReply(identity: int, status: RpcStatus, message: string) = record("held", $status,
      message, $identity)
  proc removed(identity: int, status: RpcStatus, message: string) = record("unsubscribe", $status,
      message, $identity)
  proc bulkReply(identity: int, status: RpcStatus, message: string) = record("bulk", $status,
      message, $identity)
  proc firstUpdate(identity: uint32, status: RpcStatus, message: string) = record("update1",
      $status, message, $identity)
  proc secondUpdate(identity: uint32, status: RpcStatus, message: string) = record("update2",
      $status, message, $identity)
  proc firstAck(identity: int, status: RpcStatus, message: string) =
    if status == RpcStatus.Success: firstSubscription = resultId(
        message) # Capture the remote selector only after a valid ACK.
    record("ack1", $status, message, $identity)
  proc secondAck(identity: int, status: RpcStatus, message: string) = record("ack2", $status,
      message, $identity)
  proc closed(status: RpcStatus) = record("closed", $status, "")
  proc idle() = record("opened", "Success", "")

  # Reopening during cleanup must not leave a superseded outer socket alive.
  proc reconnectReply(identity: int, status: RpcStatus, message: string) =
    record("close-reentrant", $status, message, $identity)
    if status == RpcStatus.ConnectionClosed: discard openRpc(endpoint(), idle, closed)

  proc onClose*() {.exportc: "rpcTestOnClose".} =
    ## A pending call's cleanup handler may synchronously replace the connection.
    accepted("close-reentrant", call("reopen-on-close", "[]", reconnectReply))

  # Two subscriptions to the same method coexist with independently pending one-shot calls.
  proc ready() =
    accepted("sub1", subscribe("subscribeBestBlock", "[]", firstAck, firstUpdate))
    accepted("sub2", subscribe("subscribeBestBlock", "[]", secondAck, secondUpdate))
    accepted("first", call("ragnarok_clientInfo", "[]", firstReply))
    accepted("second", call("ragnarok_clientInfo", "[]", secondReply))

  proc start*() {.exportc: "rpcTestStart".} =
    ## The host installs a deterministic WebSocket implementation before loading this fixture.
    discard openRpc(endpoint(), ready, closed)

  proc extra*() {.exportc: "rpcTestExtra".} =
    ## One-shot calls are permitted while streams are active.
    accepted("extra", call("ragnarok_clientInfo", "[]", extraReply))

  proc deadlines*() {.exportc: "rpcTestDeadlines".} =
    ## A short independent deadline must not cancel a longer request or any subscription.
    accepted("timeout", call("slow", "[]", timeoutReply, 40))
    accepted("held", call("held", "[]", heldReply, 5000))

  proc reentrant*() {.exportc: "rpcTestReentrant".} =
    ## The callback issues a new call inside the deadline sweep without creating a second timer.
    accepted("reentrant", call("reentrant", "[]", reentrantReply, 40))

  proc unsubscribeFirst*() {.exportc: "rpcTestUnsubscribe".} =
    ## Stream updates remain routed until this retirement receives a successful boolean ACK.
    accepted("unsubscribe", unsubscribe("unsubscribeBestBlock", firstSubscription, removed))

  proc reconnect*() {.exportc: "rpcTestReconnect".} =
    ## Old callbacks and deadlines retire before the replacement socket becomes usable.
    discard openRpc("ws://127.0.0.1/replacement", idle, closed)

  proc fill*() {.exportc: "rpcTestFill".} =
    ## The fixed request table rejects excess work without allocating an unbounded queue.
    for i in 0..MaxPendingRequests:
      accepted("bulk", call("bulk", "[]", bulkReply))

  proc fillSubscriptions*() {.exportc: "rpcTestSubscriptions".} =
    ## Pending subscribe ACKs reserve capacity just like already active streams.
    for i in 0..MaxSubscriptions:
      accepted("sub-limit", subscribe("subscribeBestBlock", "[]", secondAck, secondUpdate))

  proc subscriptionDeadline*() {.exportc: "rpcTestSubscriptionDeadline".} =
    ## A missing subscription ACK makes remote ownership ambiguous, requiring socket retirement.
    accepted("sub-timeout", subscribe("subscribeBestBlock", "[]", secondAck, secondUpdate, 40))

  proc stop*() {.exportc: "rpcTestStop".} =
    ## Explicit retirement resolves pending calls and active streams once.
    closeRpc()

  register("rpcTestStart", start)
  register("rpcTestExtra", extra)
  register("rpcTestDeadlines", deadlines)
  register("rpcTestReentrant", reentrant)
  register("rpcTestOnClose", onClose)
  register("rpcTestUnsubscribe", unsubscribeFirst)
  register("rpcTestReconnect", reconnect)
  register("rpcTestFill", fill)
  register("rpcTestSubscriptions", fillSubscriptions)
  register("rpcTestSubscriptionDeadline", subscriptionDeadline)
  register("rpcTestStop", stop)
  start()
