# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Tagged shape/result guards, fixed scope copies and explicit request-namespace overlap
## evidence.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/syncio
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded

## A decoded fixed tagged history survives source mutation, caller-input destruction and local scope exit.
proc captured(config: RequestEntryConfig): RequestHistoryRead =
  var source = reavailableHistory(RequestSlot(high(uint32)), RequestSlot(0), RequestSlot(128))
  let entry = serviceRequestEntry(ServiceIndex(1729), default(ServicePreimageHash), RequestLength(
      256), source, config)
  assert entry.error == RequestError.None and entry.value.value.len == 13
  source = default(RequestHistory)
  var input = entry.value.value
  let parsed = decodeRequestHistory(input, config.history)
  assert parsed.error == RequestError.None
  result = parsed.value
  for i in 0..<input.len: input[i] = 0 # Returned fields are independent fixed copies.

## Validate active fields, impossible reads, strict policies and deterministic namespace overlaps without new restrictions.
proc main() =
  let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  let value = captured(config)
  assert value.consumed == 13 and value.history.state == RequestState.Reavailable
  assert uint32(value.history.originalFrom) == high(uint32) and uint32(value.history.removedAt) ==
      0 and uint32(value.history.restoredAt) == 128
  var copy = value.history
  copy = reavailableHistory(copy.originalFrom, copy.removedAt, RequestSlot(0))
  assert uint32(value.history.restoredAt) == 128
  let requested = decodeRequestHistory(@[0'u8], config.history)
  assert requested.error == RequestError.None and requested.value.history.state ==
      RequestState.Requested
  let available = decodeRequestHistory(@[1'u8, 0, 0, 0, 0], config.history)
  assert available.error == RequestError.None and available.value.history.state ==
      RequestState.Available
  let excess = decodeRequestHistory(@[4'u8], config.history)
  assert excess.error == RequestError.InvalidCount
  let short = decodeRequestHistory(@[3'u8, 0, 0, 0, 0], config.history)
  assert short.error == RequestError.Truncated
  let limited = serviceRequestEntry(ServiceIndex(0), default(ServicePreimageHash), RequestLength(0),
      value.history,
    RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
        2), maxBytes: ByteLimit(13))))
  assert limited.error == RequestError.LimitExceeded
  let hash = default(ServicePreimageHash)
  let requestPreimage = serviceRequestEntry(ServiceIndex(0), hash, RequestLength(high(uint32)-1),
      default(RequestHistory), config)
  let preimage = servicePreimageEntry(ServiceIndex(0), hash, @[], ServiceEntryLimits(
      keyBytes: ByteLimit(32), valueBytes: ByteLimit(0)))
  assert requestPreimage.error == RequestError.InvalidLength and preimage.error ==
      ServiceValueError.None
  let requestStorage = serviceRequestKey(ServiceIndex(0), hash, RequestLength(high(uint32)),
      ByteLimit(32))
  assert requestStorage.error == RequestError.InvalidLength # Current preimagelen excludes storage and preimage namespace markers.
  let maximum = serviceRequestKey(ServiceIndex(0), hash, RequestLength(high(uint32)-2), ByteLimit(32))
  assert maximum.error == RequestError.None # The highest allowed length remains an exact fixed E4 prefix.
  echo "PASS requests: tagged fields, fixed scope copies, failure guards and reserved-length rejection"

main()
