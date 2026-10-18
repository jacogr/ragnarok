# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated request result and inactive timestamp reads require exact supported success/shape contracts.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_requests
# Faults apply to this test-only observer-linked adapter, never production corpus binaries.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
## Select source mode from runtime input so inactive-field checks execute rather than fold at compilation.
proc selected(mode: string): RequestHistory =
  case mode
  of "1": availableHistory(RequestSlot(17)) # One active supplied-at value.
  of "2": unavailableHistory(RequestSlot(17), RequestSlot(18)) # Two ordered positions.
  of "3": reavailableHistory(RequestSlot(17), RequestSlot(18), RequestSlot(19)) # Three restoration positions.
  else: requestedHistory() # Explicit and default requested histories have no active timestamp.
## Decode a literal runtime-selected mode without using production encoding as a fixture generator.
proc decoded(mode: string): RequestHistory =
  let bytes = case mode
    of "1": @[1'u8, 17, 0, 0, 0]                                           # One complete E4 slot.
    of "2": @[2'u8, 17, 0, 0, 0, 18, 0, 0, 0]                              # Two complete E4 slots.
    of "3": @[3'u8, 17, 0, 0, 0, 18, 0, 0, 0, 19, 0, 0, 0]                 # Three complete E4 slots.
    else: @[0'u8] # Empty mode retains its canonical count.
  decodeRequestHistory(bytes, RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(
      13))).value.history
fail(0)
let useDefault = paramStr(2) == "default"
let policy = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
    items: ElementLimit(3), maxBytes: ByteLimit(13)))
let noItems = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
    items: ElementLimit(0), maxBytes: ByteLimit(13)))
let noBytes = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
    items: ElementLimit(3), maxBytes: ByteLimit(0)))
let noKey = RequestEntryConfig(keyBytes: ByteLimit(31), history: policy.history)
let restored = reavailableHistory(RequestSlot(17), RequestSlot(18), RequestSlot(19))
let history = if useDefault: default(RequestHistory)
  elif paramStr(2) == "source": selected(paramStr(3))
  else: decoded(paramStr(3))
case paramStr(1)
of "owner":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[RequestHistoryRead]) else: decodeRequestHistory(
      [], policy.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.Truncated)
  discard parsed.value.history
of "consumed":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[RequestHistoryRead]) else: decodeRequestHistory(
      [], policy.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.Truncated)
  discard parsed.value.consumed
of "decode-framing":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[RequestHistoryRead]) else: decodeRequestHistory(
      [128'u8, 0], policy.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.NonCanonical)
  discard parsed.value.history
of "decode-count":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[RequestHistoryRead]) else: decodeRequestHistory(
      [4'u8], policy.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.InvalidCount)
  discard parsed.value.history
of "decode-items":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[RequestHistoryRead]) else: decodeRequestHistory(
      [1'u8], noItems.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value.history
of "decode-bytes":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[RequestHistoryRead]) else: decodeRequestHistory(
      [0'u8], noBytes.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value.history
of "decode-tail":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[RequestHistoryRead]) else: decodeRequestHistory(
      [3'u8], policy.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.Truncated)
  discard parsed.value.history
of "key-policy":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[StateKey]) else: serviceRequestKey(ServiceIndex(
      1), default(ServicePreimageHash), RequestLength(0), ByteLimit(31))
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value
of "key-backend":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  fail(1)
  let parsed = if useDefault: default(RequestResult[StateKey]) else: serviceRequestKey(ServiceIndex(
      1), default(ServicePreimageHash), RequestLength(0), ByteLimit(32))
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.BackendFailure)
  discard parsed.value
of "entry-items":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[StateEntry]) else: serviceRequestEntry(
      ServiceIndex(1), default(ServicePreimageHash), RequestLength(0), restored, noItems)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value.value.len
of "entry-bytes":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[StateEntry]) else: serviceRequestEntry(
      ServiceIndex(1), default(ServicePreimageHash), RequestLength(0), restored, noBytes)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value.value.len
of "entry-key":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[StateEntry]) else: serviceRequestEntry(
      ServiceIndex(1), default(ServicePreimageHash), RequestLength(0), restored, noKey)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value.value.len
of "entry-backend":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  fail(1)
  let parsed = if useDefault: default(RequestResult[StateEntry]) else: serviceRequestEntry(
      ServiceIndex(1), default(ServicePreimageHash), RequestLength(0), restored, policy)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.BackendFailure)
  discard parsed.value.value.len
of "extent-count":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[int]) else: extent(high(uint64), policy.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.InvalidCount)
  discard parsed.value
of "extent-items":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[int]) else: extent(3, noItems.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value
of "extent-bytes":
  # Default and actual failures cannot authorize keys, history values or partial progress.
  let parsed = if useDefault: default(RequestResult[int]) else: extent(0, noBytes.history)
  assert parsed.error == (if useDefault: RequestError.Uninitialized else: RequestError.LimitExceeded)
  discard parsed.value
of "field-since":
  # Read one inactive timestamp separately from a runtime-selected source/default/decoded shape.
  discard history.since
of "field-availableFrom":
  # Read one inactive timestamp separately from a runtime-selected source/default/decoded shape.
  discard history.availableFrom
of "field-unavailableFrom":
  # Read one inactive timestamp separately from a runtime-selected source/default/decoded shape.
  discard history.unavailableFrom
of "field-originalFrom":
  # Read one inactive timestamp separately from a runtime-selected source/default/decoded shape.
  discard history.originalFrom
of "field-removedAt":
  # Read one inactive timestamp separately from a runtime-selected source/default/decoded shape.
  discard history.removedAt
of "field-restoredAt":
  # Read one inactive timestamp separately from a runtime-selected source/default/decoded shape.
  discard history.restoredAt
else:
  # Unknown fixture modes fail setup rather than count as contract rejections.
  quit 2
