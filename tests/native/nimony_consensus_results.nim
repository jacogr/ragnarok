# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated chapter failure/default reads and inactive source-schedule reads require supported
## contracts.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
include ../../src/codec/state_consensus
let useDefault = paramStr(2) == "default"
let policy = SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(2),
    validators: ElementLimit(6), maxBytes: ByteLimit(2017)), epochSlots: EpochSlots(2),
    maxAccumulator: ElementLimit(2), maxBytes: ByteLimit(10000))
var invalidConfig = policy
invalidConfig.epochSlots = EpochSlots(0)
var huge = policy
huge.epochSlots = EpochSlots(high(uint64))
var strict = policy
strict.maxAccumulator = ElementLimit(1)
var entryStrict = policy
entryStrict.maxAccumulator = ElementLimit(0)
var tinyBytes = policy
tinyBytes.maxBytes = ByteLimit(1)
let item = default(WinningTicket)
let original = SafroleState(pending: newSeq[StateValidator](6), schedule: ticketSchedule(@[item,
    item]), accumulator: @[item])
let emptySchedule = SafroleState(pending: newSeq[StateValidator](6), schedule: default(
    SealerSchedule))
let encoded = safroleStateEntry(original, policy)
assert encoded.error == StateComponentError.None
let owner = decodeSafroleState(encoded.value.value, policy).value.snapshot
let fallback = SafroleState(pending: newSeq[StateValidator](6), schedule: keySchedule(newSeq[
    StateBsKey](2)))
let keysOwner = decodeSafroleState(safroleStateEntry(fallback, policy).value.value,
    policy).value.snapshot
# Author late failures at exact specification offsets, never from production decoder metadata.
proc broken(kind: string): seq[byte] =
  let full = encoded.value.value
  let length = if kind == "tag": full.len else: 2017+145+2*33
  result = newSeq[byte](length)
  # Copy the valid fixed prefix before replacing its tag or canonical accumulator framing.
  for i in 0..<length: result[i] = full[i]
  if kind == "tag":
    # Reserved schedule tags fail before schedule access.
    result[2017+144] = 2
  elif kind == "framing":
    # This complete second representation of zero is not canonical.
    result.add(128'u8)
    result.add(0'u8)
  elif kind == "count":
    # Count exceeds the two-slot chain epoch before payload access.
    result.add(3'u8)
  else:
    # Count two exceeds strict caller policy one before missing payload can matter.
    result.add(2'u8)
case paramStr(1)
of "entry-count":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateEntry]) else: safroleStateEntry(
      emptySchedule, policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidCount)
  echo parsed.value.value.len
of "entry-config":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateEntry]) else: safroleStateEntry(
      original, invalidConfig)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidConfig)
  echo parsed.value.value.len
of "entry-policy":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateEntry]) else: safroleStateEntry(
      original, entryStrict)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LimitExceeded)
  echo parsed.value.value.len
of "entry-bytes":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateEntry]) else: safroleStateEntry(
      original, tinyBytes)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LimitExceeded)
  echo parsed.value.value.len
of "owner":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState([], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo safroleInfo(parsed.value.snapshot).value.slots
of "consumed":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState([], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value.consumed
of "decode-config":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState([], invalidConfig)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidConfig)
  echo parsed.value.consumed
of "decode-roster":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState([0'u8], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidCount)
  echo parsed.value.consumed
of "decode-tag":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState(broken("tag"), policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidTag)
  echo parsed.value.consumed
of "decode-framing":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState(broken("framing"), policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.NonCanonical)
  echo parsed.value.consumed
of "decode-count":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState(broken("count"), policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidCount)
  echo parsed.value.consumed
of "decode-policy":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState(broken("policy"), strict)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LimitExceeded)
  echo parsed.value.consumed
of "decode-bytes":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState(encoded.value.value, tinyBytes)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LimitExceeded)
  echo parsed.value.consumed
of "decode-overflow":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[
      SafroleStateRead]) else: decodeSafroleState([], huge)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.LengthOverflow)
  echo parsed.value.consumed
of "info":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[SafroleStateInfo]) else: safroleInfo(
      default(SafroleStateSnapshot))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidOwner)
  echo parsed.value.slots
of "pending-owner":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateValidator]) else: pendingValidatorAt(
      default(SafroleStateSnapshot), StateValidatorIndex(0))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidOwner)
  echo array[32, byte](parsed.value.bandersnatch)[0]
of "pending-index":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateValidator]) else: pendingValidatorAt(
      owner, StateValidatorIndex(high(uint64)))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidIndex)
  echo array[32, byte](parsed.value.bandersnatch)[0]
of "ticket-owner":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[WinningTicket]) else: sealerTicketAt(
      default(SafroleStateSnapshot), SafroleStateIndex(0))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidOwner)
  echo byte(parsed.value.attempt)
of "ticket-variant":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[WinningTicket]) else: sealerTicketAt(
      keysOwner, SafroleStateIndex(0))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.WrongVariant)
  echo byte(parsed.value.attempt)
of "ticket-index":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[WinningTicket]) else: sealerTicketAt(owner,
      SafroleStateIndex(high(uint64)))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidIndex)
  echo byte(parsed.value.attempt)
of "key-owner":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateBsKey]) else: sealerKeyAt(default(
      SafroleStateSnapshot), SafroleStateIndex(0))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidOwner)
  echo array[32, byte](parsed.value)[0]
of "key-variant":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateBsKey]) else: sealerKeyAt(owner,
      SafroleStateIndex(0))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.WrongVariant)
  echo array[32, byte](parsed.value)[0]
of "key-index":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[StateBsKey]) else: sealerKeyAt(keysOwner,
      SafroleStateIndex(high(uint64)))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidIndex)
  echo array[32, byte](parsed.value)[0]
of "accumulator-owner":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[WinningTicket]) else: accumulatedTicketAt(
      default(SafroleStateSnapshot), SafroleStateIndex(0))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidOwner)
  echo byte(parsed.value.attempt)
of "accumulator-index":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[WinningTicket]) else: accumulatedTicketAt(
      owner, SafroleStateIndex(high(uint64)))
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.InvalidIndex)
  echo byte(parsed.value.attempt)
of "count-value":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[tuple[value: uint64,
      size: int]]) else: count([])
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value.value
of "count-size":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[tuple[value: uint64,
      size: int]]) else: count([128'u8, 0])
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.NonCanonical)
  echo parsed.value.size
of "layout-pending":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[Layout]) else: scan([], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value.pending
of "layout-consumed":
  # Default/failed operations cannot authorize a value, owner, child, metadata or progress.
  let parsed = if useDefault: default(SafroleStateResult[Layout]) else: scan([], policy)
  assert parsed.error == (if useDefault: StateComponentError.Uninitialized else: StateComponentError.Truncated)
  echo parsed.value.consumed
of "source-tickets":
  # Key alternatives carry no ticket sequence to inspect.
  let source = keySchedule(newSeq[StateBsKey](2))
  echo source.tickets.len
of "source-keys":
  # Default source schedules select tickets and carry no fallback key sequence.
  let source = default(SealerSchedule)
  echo source.keys.len
else:
  # Unknown selectors are harness errors, never guard evidence.
  quit(2)
