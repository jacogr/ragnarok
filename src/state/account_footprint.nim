# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current GP accounts eq:deposits computes dependent footprint counts with explicit nonwrapping arithmetic.
## Unauthenticated aggregate inputs produce arithmetic observations, never a source-bound state certificate.
import ../codec/state_accounts as codec_state_accounts

type
  AccountFootprintShape* = object ## Logical storage/request counts and component byte sums before namespace overhead.
    storage*, requests*: uint64
    storageKeyBytes*, storageValueBytes*, requestBytes*: uint64
  AccountFootprint* = object ## Protocol dependent fields retain their existing nominal widths.
    items*: AccountStorageItems
    bytes*: AccountStorageBytes
  AccountFootprintError* {.pure.} = enum ## Failed/default arithmetic has no truncated or wrapped dependent values.
    Uninitialized, None, Overflow
  AccountFootprintResult* = object ## Only successful checked equations expose their fixed observation.
    case status: AccountFootprintError
    of None:
      completed: AccountFootprint
    else:
      discard
func error*(outcome: AccountFootprintResult): AccountFootprintError =
  ## Inspect arithmetic refusal without exposing mutable discriminators.
  outcome.status
func value*(outcome: AccountFootprintResult): AccountFootprint {.inline,
    requires: outcome.status == AccountFootprintError.None.} =
  ## Extract only representable protocol fields under checked optimized contracts.
  outcome.completed
func calculateAccountFootprint*(shape: AccountFootprintShape): AccountFootprintResult =
  ## Preimage payloads do not add independent footprint: requests reserve their advertised byte length.
  if shape.storage > uint64(high(uint32)) or
      shape.requests > (uint64(high(uint32))-shape.storage) div 2:
    return AccountFootprintResult(status: AccountFootprintError.Overflow) # Prove E4 item addition and multiplication before evaluating them.
  let items = shape.storage + shape.requests * 2
  var octets = 0'u64
  template product(count, width: uint64) =
    if count > (high(uint64)-octets) div width:
      return AccountFootprintResult(status: AccountFootprintError.Overflow)
    octets += count * width # Positive fixed overhead widths prove multiplication and addition together.
  template add(amount: uint64) =
    if amount > high(uint64)-octets:
      return AccountFootprintResult(status: AccountFootprintError.Overflow)
    octets += amount # No later nonnegative term can repair an overflowing sum.
  product(shape.requests, 81'u64)
  product(shape.storage, 34'u64)
  add(shape.requestBytes)
  add(shape.storageKeyBytes)
  add(shape.storageValueBytes)
  AccountFootprintResult(status: AccountFootprintError.None,
    completed: AccountFootprint(items: AccountStorageItems(uint32(items)),
        bytes: AccountStorageBytes(octets)))
