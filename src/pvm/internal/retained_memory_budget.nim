# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical retained payload accounting for owners under the same exclusive scheduling turn.
## The ledger cannot own the charged storage. A charge follows its owner through retirement.

type
  RetainedMemoryByteLimit* = distinct uint64
    ## Ceiling for the logical extent of one class of retained payload.
  RetainedMemoryLedger = ref object
    ## All users of one ledger must serialize access, including ARC operations and destruction.
    limit, used: uint64
  RetainedMemoryBudget* = object
    ## Copyable handle to a synchronous budget. The default selects per-owner limits alone.
    ledger: nil RetainedMemoryLedger
    bound: bool
  RetainedMemoryCharge* = object
    ## Exactly one owner returns a positive reservation to its original ledger.
    ledger: nil RetainedMemoryLedger
    bytes: uint64

proc `=wasMoved`*(budget: var RetainedMemoryBudget) {.nodestroy, inline.} =
  ## A moved handle becomes unbound rather than an explicitly empty budget.
  `=wasMoved`(budget.ledger)
  budget.bound = false

proc `=destroy`*(charge: RetainedMemoryCharge) =
  ## Refund only this owner's charge. An unbound or moved-from charge has no ledger.
  let ledger {.cursor.} = charge.ledger
  if ledger != nil and charge.bytes <= ledger.used:
    ledger.used -= charge.bytes
  `=destroy`(charge.ledger)

proc `=wasMoved`*(charge: var RetainedMemoryCharge) {.nodestroy, inline.} =
  ## Leave reservation authority solely with the destination.
  `=wasMoved`(charge.ledger)
  charge.bytes = 0

proc `=copy`*(destination: var RetainedMemoryCharge, source: RetainedMemoryCharge) {.error.}
  ## A copied charge could refund the same bytes twice.

proc `=dup`*(source: RetainedMemoryCharge): RetainedMemoryCharge {.error.}
  ## A duplicated charge has the same double-refund problem.

proc newRetainedMemoryBudget*(limit: RetainedMemoryByteLimit): RetainedMemoryBudget =
  ## Create a shared ceiling. Zero or a refused allocation suppresses optional retention.
  if uint64(limit) == 0:
    return RetainedMemoryBudget(bound: true)
  RetainedMemoryBudget(bound: true, ledger: RetainedMemoryLedger(limit: uint64(limit), used: 0))

func isBound*(budget: RetainedMemoryBudget): bool =
  ## True also identifies an explicitly empty budget after a refused ledger allocation.
  budget.bound

func retainedMemoryPayloadBytes*(budget: RetainedMemoryBudget): uint64 =
  ## Observe logical retained usage under the turn that protects execution and retirement.
  let ledger {.cursor.} = budget.ledger
  if ledger == nil: 0'u64 else: ledger.used

func chargedPayloadBytes*(charge: RetainedMemoryCharge): uint64 =
  ## The active owner can compare its logical occupancy before replacing a reservation.
  charge.bytes

proc tryCharge*(budget: RetainedMemoryBudget, bytes: uint64,
    charge: var RetainedMemoryCharge): bool =
  ## Acquire an empty token before publishing retained payload.
  ## Failure leaves the ledger and any existing token unchanged.
  if charge.ledger != nil: return false
  if not budget.bound: return true
  let ledger {.cursor.} = budget.ledger
  if ledger == nil or bytes == 0 or ledger.used > ledger.limit or
      bytes > ledger.limit-ledger.used:
    return false
  ledger.used += bytes
  charge.ledger = budget.ledger
  charge.bytes = bytes
  true
