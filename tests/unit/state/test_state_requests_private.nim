# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only request shape, fixed-copy, backend and scoped entry-release checks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import ../../support/arc_evidence
import std/[assertions, syncio]
include ../../../src/codec/state_requests
# This binary alone links the maintained test-only backend observer.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Copied call counts prove history/key preflight precedes native hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Construct each valid source shape independently; zero/max/descending values retain their positions.
proc source(count: int): RequestHistory =
  case count
  of 0: requestedHistory() # Default and explicit requested histories have no timeslot payload.
  of 1: availableHistory(RequestSlot(high(uint32))) # Preserve the full E4 supplied-at domain.
  of 2: unavailableHistory(RequestSlot(high(uint32)), RequestSlot(0)) # Descending values are structural data.
  else: reavailableHistory(RequestSlot(high(uint32)), RequestSlot(0), RequestSlot(
      128)) # Restoration supplies three positions.

## Escape all fixed history fields after source/input buffers and encoded entry leave their scope.
proc escaped(count: int, policy: RequestEntryConfig): RequestHistoryRead =
  var original = source(count)
  let encoded = serviceRequestEntry(ServiceIndex(1729), default(ServicePreimageHash), RequestLength(
      high(uint32)), original, policy)
  assert encoded.error == RequestError.None
  original = requestedHistory()
  var wire = encoded.value.value
  let parsed = decodeRequestHistory(wire, policy.history)
  assert parsed.error == RequestError.None
  result = parsed.value
  # Fixed histories cannot retain original byte coordinates or source fields.
  for i in 0..<wire.len: wire[i] = 0

## Each scope retires encoded entries and exercises every shape, copied fields and backend refusal/recovery.
proc cycle() =
  fail(0)
  let policy = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  # All four public constructors must agree with the decoder's exact active field shape.
  for count in 0..<4:
    var value = escaped(count, policy)
    let retained = value
    value = default(RequestHistoryRead)
    assert ord(retained.history.state) == count and retained.consumed == 1+4*count
    let copied = fields(retained.history)
    assert copied.count == count
    # Only actual active fields are copied; no unused staging slot is published by the API.
    for i in 0..<count:
      let expected = if i == 0: high(uint32) elif i == 1: 0'u32 else: 128'u32
      assert uint32(copied.slots[i]) == expected
    var wire = serviceRequestEntry(ServiceIndex(1), default(ServicePreimageHash), RequestLength(0),
        retained.history, policy).value.value
    wire.add(255'u8)
    let suffix = decodeRequestHistory(wire, policy.history)
    assert suffix.error == RequestError.None and suffix.value.consumed == 1+4*count
    wire.setLen(count*4)
    assert decodeRequestHistory(wire, policy.history).error == RequestError.Truncated
  fail(1)
  assert serviceRequestKey(ServiceIndex(1), default(ServicePreimageHash), RequestLength(0),
      ByteLimit(32)).error == RequestError.BackendFailure
  assert hashCalls() == 1
  fail(1)
  assert serviceRequestEntry(ServiceIndex(1), default(ServicePreimageHash), RequestLength(0),
      source(3), policy).error == RequestError.BackendFailure
  assert hashCalls() == 1
  fail(1)
  var limited = policy
  limited.history.items = ElementLimit(2)
  assert serviceRequestEntry(ServiceIndex(1), default(ServicePreimageHash), RequestLength(0),
      source(3), limited).error == RequestError.LimitExceeded
  assert hashCalls() == 0
  limited = policy
  limited.history.maxBytes = ByteLimit(12)
  assert serviceRequestEntry(ServiceIndex(1), default(ServicePreimageHash), RequestLength(0),
      source(3), limited).error == RequestError.LimitExceeded
  assert hashCalls() == 0
  limited = policy
  limited.keyBytes = ByteLimit(31)
  assert serviceRequestEntry(ServiceIndex(1), default(ServicePreimageHash), RequestLength(0),
      source(3), limited).error == RequestError.LimitExceeded
  assert hashCalls() == 0
  fail(0)
  assert serviceRequestEntry(ServiceIndex(1), default(ServicePreimageHash), RequestLength(0),
      source(3), policy).error == RequestError.None
  assert hashCalls() == 1

let policy = RequestHistoryConfig(items: ElementLimit(high(uint64)), maxBytes: ByteLimit(high(uint64)))
# Protocol count is rejected in uint64 before narrowing, even under permissive caller ceilings.
assert extent(high(uint64), policy).error == RequestError.InvalidCount
assert extent(4, policy).error == RequestError.InvalidCount
# Every accepted shape bounds all native extent arithmetic to 1/5/9/13 bytes.
for count in 0'u64..3'u64: assert extent(count, policy).value == 1+4*int(count)
# Warm all constructor/decode/failure paths and observer counters before measuring scoped release.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Fixed histories own no heap references; every fresh keyed entry must still retire at scope exit.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_requests_private", 1000, beforeRelease, afterRelease)
echo "REQUESTS_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony requests: all fixed shapes, preflight, backend recovery and scoped entry release passed"
