# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached handoff enforces byte bounds, one-frame credit and stale-generation isolation.

import std/[assertions, syncio, strutils, atomics, threadpool]
import ../../../src/rpc/transport_bridge as transport

var bridge = default(transport.RpcTransportBridge)
var connection = default(transport.BridgeTicket)
assert bridge.open(0, connection) == transport.Ready
var incoming = transport.BridgeMessage(kind: transport.Text, payload: "request")
assert bridge.publish(connection, incoming) == transport.Ready
assert incoming.payload == ""
var deferred = transport.BridgeMessage(kind: transport.Text, payload: "next")
assert bridge.publish(connection, deferred) == transport.Full
assert deferred.payload == "next"
var grant = default(transport.BridgeDispatch)
var message = default(transport.BridgeMessage)
assert bridge.reserve(0, grant, message) == transport.Ready
assert message.payload == "request"
var second = default(transport.BridgeDispatch)
assert bridge.reserve(0, second, message) == transport.Busy
var response = transport.BridgeMessage(kind: transport.Text, payload: "response")
assert bridge.commit(grant, response) == transport.Ready
assert response.payload == ""
assert bridge.commit(grant, response) == transport.Stale
var delivery = default(transport.BridgeWrite)
assert bridge.take(connection, delivery, message) == transport.Ready
assert message.payload == "response"
let originalWrite = delivery
assert bridge.publish(connection, deferred) == transport.Ready
assert bridge.reserve(0, second, message) == transport.Busy
assert bridge.complete(delivery, true) == transport.Ready
assert bridge.complete(delivery, true) == transport.Stale
assert bridge.reserve(0, second, message) == transport.Ready
assert message.payload == "next"
response = default(transport.BridgeMessage)
assert bridge.commit(second, response) == transport.Ready
assert bridge.close(connection) == transport.Ready
var replacement = default(transport.BridgeTicket)
assert bridge.open(0, replacement) == transport.Ready
assert replacement.generation > connection.generation
incoming = transport.BridgeMessage(kind: transport.Text, payload: "stale")
assert bridge.publish(connection, incoming) == transport.Stale
assert incoming.payload == "stale"
assert bridge.complete(delivery, false) == transport.Stale
assert bridge.commit(second, response) == transport.Stale
incoming.payload = repeat('x', transport.BridgeRequestBytes + 1)
assert bridge.publish(replacement, incoming) == transport.Invalid
assert incoming.payload.len == transport.BridgeRequestBytes + 1
incoming.payload = repeat('x', transport.BridgeRequestBytes)
assert bridge.publish(replacement, incoming) == transport.Ready
assert bridge.reserve(0, grant, message) == transport.Ready
assert message.payload.len == transport.BridgeRequestBytes
response = transport.BridgeMessage(kind: transport.Text, payload: repeat('y',
    transport.BridgeReplyBytes + 1))
assert bridge.commit(grant, response) == transport.Invalid
assert response.payload.len == transport.BridgeReplyBytes + 1
response.payload = repeat('y', transport.BridgeReplyBytes)
assert bridge.commit(grant, response) == transport.Ready
assert bridge.take(replacement, delivery, message) == transport.Ready
assert message.payload.len == transport.BridgeReplyBytes
assert bridge.complete(originalWrite, false) == transport.Stale, "late completion cannot retire a replacement"
assert bridge.complete(delivery, false) == transport.Ready
assert bridge.snapshot(0, replacement) == transport.Empty
# A default or malformed ticket never grants delivery authority.
assert bridge.close(default(transport.BridgeTicket)) == transport.Stale
assert bridge.publish(default(transport.BridgeTicket), incoming) == transport.Stale
type ProducerResult = object
  ## The done release publishes the producer-owned scalar result to the foreground.
  done, preserved: bool
  status: int

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## A finite foreground wait lets the bounded test pool race actual mailbox writers.

proc produce(bridge: ptr transport.RpcTransportBridge, ticket: transport.BridgeTicket,
    text: sink string, observed: ptr ProducerResult) {.passive.} =
  ## Competing readers must transfer one request or retain their refused message intact.
  let expected = text
  var message = transport.BridgeMessage(kind: transport.Text, payload: move(text))
  let status = bridge[].publish(ticket, message)
  observed.status = ord(status)
  observed.preserved = if status == transport.Ready: message.payload.len ==
      0 else: message.payload == expected
  atomicStore(observed.done, true, moRelease)

initPool(2)
for iteration in 0..<20:
  # Race only detached bytes; stable observations outlive both producer jobs.
  var selected = default(transport.BridgeTicket)
  assert bridge.open(0, selected) == transport.Ready
  var producers = default(array[2, ProducerResult])
  submit(delay(produce(addr bridge, selected, "first", addr producers[0])), -1)
  submit(delay(produce(addr bridge, selected, "second", addr producers[1])), -1)
  var finished = false
  for attempt in 0..<2000:
    finished = atomicLoad(producers[0].done, moAcquire) and atomicLoad(producers[1].done, moAcquire)
    if finished: break
    discard pauseMicros(1000)
  assert finished
  assert producers[0].preserved and producers[1].preserved
  let firstWon = producers[0].status == ord(transport.Ready)
  let secondWon = producers[1].status == ord(transport.Ready)
  assert firstWon != secondWon
  assert bridge.reserve(0, grant, message) == transport.Ready
  assert message.payload == (if firstWon: "first" else: "second")
  response = default(transport.BridgeMessage)
  assert bridge.commit(grant, response) == transport.Ready
  assert bridge.close(selected) == transport.Ready
shutdownPool()
bridge.beginStop()
assert bridge.open(0, connection) == transport.Closed, "shutdown admission cannot reopen a scanned slot"
echo "RPC transport bridge checks passed"
