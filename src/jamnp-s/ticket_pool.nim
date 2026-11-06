# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed detached pending-ticket retention accepts only sealed proof results for a current finalized epoch context.
## Pool contents are prospective GP inputs, never canonical inclusion or sealer-schedule authority.
import std/assertions
import ./ticket_validation
import ../codec/[header, tickets]
import ../codec/state/[safrole, trie]

const MaxPendingNetworkTickets* = 2046 ## At most two pinned-network attempts for each of1023 pending validator positions.

type
  TicketPoolError* {.pure.} = enum ## Refused insertion never changes the accepted prefix or manufactures proof authority.
    None, InvalidTicket, NoSource, InvalidWindow, WrongContext, Duplicate, AlreadyIncluded, Full
  PendingTicketPool* = object ## Independent value owners share only immutable checked proofs and inclusion copies; no native/worker handle exists.
    entries: array[MaxPendingNetworkTickets, CheckedNetworkTicket]
    count, limit: int
    active: bool
    epoch, duration, tail: uint32
    context: array[32, byte]
    lastBlock: array[32, byte]
    lastRoot: StateRoot
    included: seq[WinningTicketId] # Fresh copied immutable IDs never alias the worker-shared source owner.
func len*(pool: PendingTicketPool): int =
  ## Count retained complete proofs even while an unrelated Services worker owns canonical state.
  pool.count
proc clear*(pool: var PendingTicketPool) =
  ## Dropping detached immutable proof owners cannot cancel a Native stream or CPU job.
  pool = default(PendingTicketPool)
proc expire*(pool: var PendingTicketPool, now: StateTime) =
  ## Observed clock changes retire obsolete proof owners before collecting any asynchronously completed job.
  if not pool.active: return
  if uint32(now) div pool.duration != pool.epoch or uint32(now) mod pool.duration >= pool.tail:
    pool.clear()
proc advance*(pool: var PendingTicketPool, source: TicketSource, now: StateTime): TicketPoolError =
  ## Caller refreshes finalized source under the graph gate; this local operation retains no source/roster reference.
  if not source.valid: return TicketPoolError.NoSource
  let duration = source.epochLength
  let epoch = source.epoch
  let tail = source.lotteryTail
  if uint32(now) div duration != epoch or uint32(now) mod duration >= tail:
    return TicketPoolError.InvalidWindow
  let population = source.pendingCount
  assert population > 0 and population <= MaxPendingNetworkTickets div 2
  let context = source.contextHash
  if not pool.active or pool.context != context:
    pool.clear()
    pool.active = true
    pool.context = context
    pool.epoch = epoch
    pool.duration = duration
    pool.tail = tail
    pool.limit = population*2 # Sealed source preflight bounds the product before retention.
  let blockHash = array[32, byte](source.sourceBlock)
  let root = source.stateRoot
  if pool.lastBlock == blockHash and array[32, byte](pool.lastRoot) == array[32, byte](
      root): return TicketPoolError.None
  pool.included = source.includedIdentifiers
  for index in 0..<MaxPendingNetworkTickets:
    if pool.entries[index].valid and source.includes(pool.entries[index].identifier):
      pool.entries[index] = default(CheckedNetworkTicket)
      dec pool.count # Finalized inclusion retires pending data without changing canonical C4.
  pool.lastBlock = blockHash
  pool.lastRoot = root
  TicketPoolError.None
proc retain*(pool: var PendingTicketPool, ticket: CheckedNetworkTicket,
    now: StateTime): TicketPoolError =
  ## Fresh clock/context checks are load-bearing even when an older CPU result was fully cryptographically valid.
  if not ticket.valid: return TicketPoolError.InvalidTicket
  if not pool.active: return TicketPoolError.NoSource
  if uint32(now) div pool.duration != pool.epoch or uint32(now) mod pool.duration >= pool.tail:
    return TicketPoolError.InvalidWindow
  if ticket.contextHash != pool.context or ticket.distributionEpoch != pool.epoch or
      ticket.epochLength != pool.duration:
    return TicketPoolError.WrongContext
  let expected = array[32, byte](ticket.identifier)
  for id in pool.included:
    if array[32, byte](id) == expected: return TicketPoolError.AlreadyIncluded
  for index in 0..<MaxPendingNetworkTickets:
    if pool.entries[index].valid and array[32, byte](pool.entries[index].identifier) == expected:
      return TicketPoolError.Duplicate
  if pool.count >= pool.limit: return TicketPoolError.Full
  for index in 0..<MaxPendingNetworkTickets:
    if not pool.entries[index].valid:
      pool.entries[index] = ticket
      inc pool.count
      return TicketPoolError.None
  assert false # Fixed capacity and a checked smaller limit prove an unused row exists.
  TicketPoolError.Full
proc ticketAt*(pool: PendingTicketPool, ordinal: int): CheckedNetworkTicket {.requires: ordinal >=
    0 and ordinal < pool.count.} =
  ## Return an immutable complete proof by owner-bound ordinal, not a mutable backing row.
  var seen = 0
  for index in 0..<MaxPendingNetworkTickets:
    if pool.entries[index].valid:
      if seen == ordinal: return pool.entries[index]
      inc seen
  assert false # The private count is maintained only with occupied-row insertion/removal.
  default(CheckedNetworkTicket)
