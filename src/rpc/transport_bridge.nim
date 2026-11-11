# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded detached-byte handoff between transport tasks and the RPC dispatcher.
## Every operation tries one per-connection lock and returns Busy instead of waiting.
## Caller-owned storage must remain at a stable address until its transport tasks have retired.

import std/atomics

const
  BridgeConnections* = 8
  BridgeRequestBytes* = 16384
  BridgeReplyBytes* = 65535

type
  BridgeIndex* = range[0..BridgeConnections - 1]
  BridgeStatus* = enum
    ## Refusals preserve caller-owned messages; only Ready transfers ownership.
    Invalid, Ready, Empty, Busy, Full, Stale, Closed
  BridgeKind* = enum
    ## None releases a dispatcher reservation without putting a frame on the wire.
    None, Text, Binary, Ping, Pong, Close
  BridgeMessage* = object
    ## Only owned bytes and scalar framing metadata cross the transport boundary.
    kind*: BridgeKind
    payload*: string
    code*: int
  BridgeTicket* = object
    ## A connection generation grants no authority over a reused slot.
    slot: BridgeIndex
    epoch: uint64
  BridgeDispatch* = object
    ## A single dispatcher reservation prevents queued notifications overtaking a reply.
    connection: BridgeTicket
    sequence: uint64
  BridgeWrite* = object
    ## Only completion of the exact outstanding frame releases its output credit.
    connection: BridgeTicket
    sequence: uint64
  BridgeSlot = object
    ## Each direction owns at most one message; in-flight output retains its own credit.
    locked, active, incomingReady, outgoingReady, dispatching, writing: bool
    epoch, sequence: uint64
    incoming, outgoing: BridgeMessage
  RpcTransportBridge* = object
    ## Shared mutation is confined to short per-slot critical sections; no canonical types occur here.
    stopRequested: bool
    slots: array[BridgeConnections, BridgeSlot]

proc `=copy`*(dest: var RpcTransportBridge, source: RpcTransportBridge) {.error.}
  ## Copying live handoff state would duplicate connection and completion authority.

proc `=dup`*(source: RpcTransportBridge): RpcTransportBridge {.error.}
  ## Transport tasks borrow one stable bridge rather than cloning it.

func valid*(ticket: BridgeTicket): bool =
  ## Default tickets cannot deliver requests or acknowledge output.
  ticket.epoch != 0

func index*(ticket: BridgeTicket): BridgeIndex {.requires: ticket.valid.} =
  ## The fixed connection selector is available only for a live-shaped ticket.
  ticket.slot

func generation*(ticket: BridgeTicket): uint64 {.requires: ticket.valid.} =
  ## A scalar generation is safe to retain on either side of the bridge.
  ticket.epoch

func ticket*(grant: BridgeDispatch): BridgeTicket =
  ## The reservation carries only the detached connection identity.
  grant.connection

proc acquire(slot: var BridgeSlot): bool =
  ## A failed CAS returns immediately; the dispatcher never spins behind a task.
  var expected = false
  atomicCompareExchange(slot.locked, expected, true, moAcquire, moRelaxed)

proc release(slot: var BridgeSlot) =
  ## Publish moved message storage before another role can take the slot.
  atomicStore(slot.locked, false, moRelease)

func matches(slot: BridgeSlot, connection: BridgeTicket): bool =
  ## Every operation checks both lifecycle and generation while holding the slot lock.
  slot.active and connection.epoch != 0 and slot.epoch == connection.epoch

proc retire(slot: var BridgeSlot) =
  ## Retiring queued storage cannot revoke bytes already owned by a writer; their completion becomes stale.
  slot.active = false
  slot.incomingReady = false
  slot.outgoingReady = false
  slot.dispatching = false
  slot.writing = false
  slot.incoming = default(BridgeMessage)
  slot.outgoing = default(BridgeMessage)

func fits(message: BridgeMessage, maximum: int): bool =
  ## Enforce existing RPC byte budgets before retaining untrusted payloads.
  if message.payload.len > maximum: return false
  case message.kind
  of None: message.payload.len == 0 and message.code == 0
  of Ping, Pong: message.payload.len <= 125
  of Close: message.payload.len <= 123 and message.code >= 0 and message.code <= 65535
  of Text, Binary: true

proc beginStop*(bridge: var RpcTransportBridge) =
  ## Freeze admission before scanning slots; the bridge is one-shot until all borrowing tasks retire.
  atomicStore(bridge.stopRequested, true, moRelease)

proc stopping*(bridge: var RpcTransportBridge): bool =
  ## A scalar stop observation never inspects slot payloads without their lock.
  atomicLoad(bridge.stopRequested, moAcquire)

proc open*(bridge: var RpcTransportBridge, index: BridgeIndex,
    connection: var BridgeTicket): BridgeStatus =
  ## Admission initializes one free slot; generation exhaustion refuses rather than wrapping.
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if bridge.stopping(): return Closed # The check is inside the admission critical section.
  if bridge.slots[index].active: return Full
  if bridge.slots[index].epoch == high(uint64): return Full
  bridge.slots[index].retire()
  inc bridge.slots[index].epoch
  bridge.slots[index].sequence = 0
  bridge.slots[index].active = true
  connection = BridgeTicket(slot: index, epoch: bridge.slots[index].epoch)
  Ready

proc snapshot*(bridge: var RpcTransportBridge, index: BridgeIndex,
    connection: var BridgeTicket): BridgeStatus =
  ## Observe admission without touching transport descriptors or RPC sessions.
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].active: return Empty
  connection = BridgeTicket(slot: index, epoch: bridge.slots[index].epoch)
  Ready

proc close*(bridge: var RpcTransportBridge, connection: BridgeTicket): BridgeStatus =
  ## Cancellation drops queued bytes and invalidates outstanding credits; socket cancellation is the transport owner's job.
  if not connection.valid: return Stale
  let index = connection.slot
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].matches(connection): return Stale
  bridge.slots[index].retire()
  Ready

proc publish*(bridge: var RpcTransportBridge, connection: BridgeTicket,
    message: var BridgeMessage): BridgeStatus =
  ## A transport reader transfers one complete message; Busy/Full retain it with the caller.
  if bridge.stopping(): return Closed
  if not connection.valid: return Stale
  if message.kind == None or not message.fits(BridgeRequestBytes): return Invalid
  let index = connection.slot
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].matches(connection): return Stale
  if bridge.slots[index].incomingReady: return Full
  bridge.slots[index].incoming = move(message)
  bridge.slots[index].incomingReady = true
  Ready

proc reserve*(bridge: var RpcTransportBridge, index: BridgeIndex,
    grant: var BridgeDispatch, incoming: var BridgeMessage): BridgeStatus =
  ## The dispatcher claims output credit before processing a request or draining its notification FIFO.
  if bridge.stopping(): return Closed
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].active: return Empty
  if bridge.slots[index].outgoingReady or bridge.slots[index].writing or
      bridge.slots[index].dispatching: return Busy
  if bridge.slots[index].sequence == high(uint64): return Full
  inc bridge.slots[index].sequence
  bridge.slots[index].dispatching = true
  grant = BridgeDispatch(connection: BridgeTicket(slot: index, epoch: bridge.slots[index].epoch),
    sequence: bridge.slots[index].sequence)
  incoming = default(BridgeMessage)
  if bridge.slots[index].incomingReady:
    # A pending request takes precedence over a notification that has not entered the transport.
    incoming = move(bridge.slots[index].incoming)
    bridge.slots[index].incomingReady = false
  Ready

proc commit*(bridge: var RpcTransportBridge, grant: BridgeDispatch,
    outgoing: var BridgeMessage): BridgeStatus =
  ## Commit only the current reservation; a disconnect during dispatch cannot deliver to a replacement.
  let connection = grant.connection
  if not connection.valid: return Stale
  if not outgoing.fits(BridgeReplyBytes): return Invalid
  let index = connection.slot
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].matches(connection) or not bridge.slots[index].dispatching or
      bridge.slots[index].sequence != grant.sequence: return Stale
  bridge.slots[index].dispatching = false
  if outgoing.kind != None:
    # The writer receives this frame exactly once and must acknowledge it before another dispatch.
    bridge.slots[index].outgoing = move(outgoing)
    bridge.slots[index].outgoingReady = true
  Ready

proc take*(bridge: var RpcTransportBridge, connection: BridgeTicket,
    delivery: var BridgeWrite, outgoing: var BridgeMessage): BridgeStatus =
  ## A writer takes one complete frame; it owns the bytes across all suspended/partial writes.
  if bridge.stopping(): return Closed
  if not connection.valid: return Stale
  let index = connection.slot
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].matches(connection): return Stale
  if not bridge.slots[index].outgoingReady: return Empty
  outgoing = move(bridge.slots[index].outgoing)
  bridge.slots[index].outgoingReady = false
  bridge.slots[index].writing = true
  delivery = BridgeWrite(connection: connection, sequence: bridge.slots[index].sequence)
  Ready

proc complete*(bridge: var RpcTransportBridge, delivery: BridgeWrite,
    succeeded: bool): BridgeStatus =
  ## Stale or duplicate completions cannot release a new connection's credit.
  let connection = delivery.connection
  if not connection.valid: return Stale
  let index = connection.slot
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].matches(connection) or not bridge.slots[index].writing or
      bridge.slots[index].sequence != delivery.sequence: return Stale
  if succeeded:
    bridge.slots[index].writing = false
  else:
    bridge.slots[index].retire() # Failed delivery retires only its originating connection.
  Ready

proc readCredit*(bridge: var RpcTransportBridge, connection: BridgeTicket): BridgeStatus =
  ## The single reader waits for its preceding request to leave the inbox before reading another message.
  if bridge.stopping(): return Closed
  if not connection.valid: return Stale
  let index = connection.slot
  if not bridge.slots[index].acquire(): return Busy
  defer: bridge.slots[index].release()
  if not bridge.slots[index].matches(connection): return Stale
  if bridge.slots[index].incomingReady: return Full
  Ready
