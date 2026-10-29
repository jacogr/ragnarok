# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Read validated GP 0.8.0 activity statistics from a configured genesis snapshot.
## Exposes statistics with a guarded immutable value result; missing chapters are errors, not empty data.

import ./genesis
import ../state/store
import ../codec/state/[layout as state_layout, safrole as state_safrole,
    statistics as state_statistics]
import ../codec/bounded
export StateValue, bytes, ByteLimit

type
  StatisticsReadError* {.pure.} = enum ## Default, unavailable, malformed and oversized inputs never expose a value.
    Uninitialized, None, Unavailable, Malformed, LimitExceeded
  StatisticsReadResult* = object ## A successful view retains its immutable state owner; extraction returns independent bytes.
    case status: StatisticsReadError
    of None:
      completed: StateValue
    else:
      discard # Failure carries only its reason.

func error*(value: StatisticsReadResult): StatisticsReadError =
  ## Inspect success or failure without granting mutable access to the result.
  value.status
func value*(value: StatisticsReadResult): StateValue {.requires: value.status ==
    StatisticsReadError.None.} =
  ## Extract only a complete successful immutable view.
  value.completed

proc statistics*(view: Genesis, limit: ByteLimit): StatisticsReadResult =
  ## Validate chapter 13 against both actual roster populations and the retained core configuration.
  ## Bound copies before decoding; no state mutation or consensus validation is performed.
  let found = view.lookup(chapterKey(StateChapter(13)))
  if found.error == StateStoreError.Uninitialized:
    return StatisticsReadResult(status: StatisticsReadError.Uninitialized) # Default genesis fails before guarded access.
  if found.error != StateStoreError.None:
    return StatisticsReadResult(status: StatisticsReadError.Unavailable) # Missing statistics cannot mean zero activity.
  if uint64(found.value.byteLength) > uint64(limit):
    return StatisticsReadResult(status: StatisticsReadError.LimitExceeded) # No oversized copy or decoder allocation.
  var populations = default(array[2, ValidatorCount])
  for index in 0..<2:
    # Current C(8) and previous C(9) may have different valid populations after resizing.
    let roster = view.lookup(chapterKey(StateChapter(8 + index)))
    if roster.error != StateStoreError.None:
      return StatisticsReadResult(status: StatisticsReadError.Unavailable) # Require the actual decoding context.
    if roster.value.byteLength > 1024 * 1024:
      return StatisticsReadResult(status: StatisticsReadError.LimitExceeded) # Bound roster copies independently.
    let wire = roster.value.bytes
    let decoded = decodeStateValidators(wire, ValidatorStateConfig(cores: view.cores,
      validators: ElementLimit(1023), maxBytes: ByteLimit(1024 * 1024)))
    if decoded.error != StateComponentError.None:
      return StatisticsReadResult(status: StatisticsReadError.Malformed) # Do not infer counts from unchecked prefixes.
    if decoded.value.consumed != wire.len:
      return StatisticsReadResult(status: StatisticsReadError.Malformed) # A complete chapter has no suffix.
    let count = validatorCount(decoded.value.value)
    if count.error != StateComponentError.None:
      return StatisticsReadResult(status: StatisticsReadError.Malformed) # Only validated owners supply context.
    populations[index] = ValidatorCount(count.value)
  let wire = found.value.bytes
  let decoded = decodeActivityState(wire, ActivityConfig(cores: view.cores,
    current: populations[0], previous: populations[1], maxServices: ElementLimit(16384),
        maxBytes: limit))
  if decoded.error != ActivityError.None:
    return StatisticsReadResult(status: StatisticsReadError.Malformed) # Includes noncanonical compact gas and dictionary order.
  if decoded.value.consumed != wire.len:
    return StatisticsReadResult(status: StatisticsReadError.Malformed) # Never publish a valid prefix with trailing bytes.
  StatisticsReadResult(status: StatisticsReadError.None, completed: found.value)
