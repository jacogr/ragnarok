# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Export original qualified raw identities to the existing logical startup source syntax without materializing service payload values.
import ./current_logical_startup as app_current_logical_startup
import ../state/current_logical as state_current_logical
import ../state/supplied_logical_inventory as state_supplied_logical_inventory
import ../state/inventory as state_inventory
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
type
  LogicalSourceExportLimits* = object ## Whole identity traversal, each detached raw-key copy and output-plus-largest-key storage have independent ceilings.
    services*, facts*: ElementLimit
    perKey*, bytes*: ByteLimit
  LogicalSourceExportInfo* = object ## Accounting describes detached identity-only text, never root trust or producer mutation provenance.
    services*, facts*: int
    bytes*, copyBytes*: uint64
  LogicalSourceExportPlan* = object ## Original complete raw-key companion and admitted ledger remain private and immutable until explicit detached export.
    initialized: bool
    source: SuppliedLogicalInventory
    info: LogicalSourceExportInfo
  LogicalSourceExportError* {.pure.} = enum ## Invalid original logical source/plan and local transport/copy refusal expose no declaration prefix.
    Uninitialized, None, InvalidLogical, InvalidPlan, LimitExceeded
  LogicalSourceExportResult*[T] = object ## Only admitted complete plans, copied observations or complete detached text have a payload.
    case status: LogicalSourceExportError
    of None: completed: T
    else: discard # Default and failed exports contain no partial text or usable plan.
func error*[T](outcome: LogicalSourceExportResult[T]): LogicalSourceExportError =
  ## Read the immutable selected stage only.
  outcome.status
func value*[T](outcome: LogicalSourceExportResult[T]): T {.inline, requires: outcome.status ==
    LogicalSourceExportError.None.} =
  ## Extract only complete successful export observations/plans/text.
  outcome.completed
func decimalWidth(value: uint32): uint64 =
  ## Count canonical decimal digits without allocating a temporary string.
  var remaining = value
  result = 1
  while remaining >= 10:
    remaining = remaining div 10
    inc result # The fixed E4 domain needs at most ten digits.
proc planLogicalSourceExport*(source: CurrentLogicalState,
    limits: LogicalSourceExportLimits): LogicalSourceExportResult[LogicalSourceExportPlan] =
  ## Admit every row and all text/raw-key scratch storage before copying a key, allocating output or hashing any payload.
  template fail(reason: LogicalSourceExportError) =
    return LogicalSourceExportResult[LogicalSourceExportPlan](status: reason)
  let original = source.currentLogicalInventory
  if original.error != CurrentLogicalError.None: fail(LogicalSourceExportError.InvalidLogical)
  let compact = original.value.suppliedInventory.value
  let info = compact.inventoryInfo.value
  if uint64(info.services) > uint64(limits.services) or info.facts > uint64(limits.facts) or
      info.facts > uint64(CurrentLogicalSourceLines):
    fail(LogicalSourceExportError.LimitExceeded) # Bound even zero-byte identities and all child traversal before inspecting payload-free facts.
  var available = min(uint64(CurrentLogicalSourceBytes), min(uint64(limits.bytes), uint64(high(int))))
  let budget = available
  var scratch = 0'u64
  template charge(amount: uint64) =
    block:
      let extent = amount
      if extent > available: fail(LogicalSourceExportError.LimitExceeded)
      available -= extent # Whole output additions cannot overflow under wrapping arithmetic.
  charge(uint64(CurrentLogicalSourceHeader.len)+1)
  for i in 0..<info.services:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = compact.inventoryServiceAt(ordinal).value
    charge(3+decimalWidth(uint32(row.service)))
    for j in 0..<row.storage:
      let key = compact.inventoryStorageAt(ordinal, InventoryStorageIndex(uint64(j))).value
      charge(3)
      if key.keyBytes > uint64(CurrentLogicalSourceKeyBytes) or
          key.keyBytes > uint64(limits.perKey) or key.keyBytes > available div 2: fail(
          LogicalSourceExportError.LimitExceeded)
      charge(key.keyBytes*2) # Hex expands only admitted raw key bytes, including genuine empty keys.
      scratch = max(scratch, key.keyBytes)
    for j in 0..<row.preimages:
      charge(67) # p=, fixed lowercase 32-byte hash and LF; payload contents are never copied.
    for j in 0..<row.requests:
      let request = compact.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
      charge(68+decimalWidth(uint32(request.length))) # r=, hash, colon, canonical E4-domain decimal length and LF.
  let output = budget-available
  if scratch > uint64(limits.bytes)-output or scratch > uint64(high(int))-output:
    fail(LogicalSourceExportError.LimitExceeded) # At most one detached raw key coexists with the exact final text allocation.
  LogicalSourceExportResult[LogicalSourceExportPlan](status: LogicalSourceExportError.None,
    completed: LogicalSourceExportPlan(initialized: true, source: original.value,
      info: LogicalSourceExportInfo(services: info.services, facts: int(info.facts), bytes: output,
          copyBytes: output+scratch)))
proc logicalSourceExportInfo*(plan: LogicalSourceExportPlan): LogicalSourceExportResult[
    LogicalSourceExportInfo] =
  ## Copy exact admitted text/traversal/scratch accounting without materializing identities or values.
  if not plan.initialized: return LogicalSourceExportResult[LogicalSourceExportInfo](
      status: LogicalSourceExportError.InvalidPlan)
  LogicalSourceExportResult[LogicalSourceExportInfo](status: LogicalSourceExportError.None,
      completed: plan.info)
proc putText(output: var string, offset: var int, text: string) =
  ## Fill only preflighted fixed text segments; no growing concatenation or fallback syntax is used.
  for character in text:
    output[offset] = character
    inc offset
proc putDecimal(output: var string, offset: var int, value: uint32) =
  ## Encode one canonical E4-domain decimal using a fixed stack buffer and no heap temporary.
  var digits = default(array[10, char])
  var remaining = value
  var count = 0
  while true:
    digits[count] = char(ord('0')+int(remaining mod 10))
    inc count
    remaining = remaining div 10
    if remaining == 0: break # Every zero value emits exactly one digit; no leading-zero alternative is possible.
  while count > 0:
    dec count
    output[offset] = digits[count]
    inc offset
proc putHex(output: var string, offset: var int, bytes: openArray[byte]) =
  ## Encode preflighted raw identities only; immutable source values never pass through this routine.
  const digits = "0123456789abcdef"
  for octet in bytes:
    output[offset] = digits[int(octet shr 4)]
    output[offset+1] = digits[int(octet and 15)]
    offset += 2
proc executeLogicalSourceExport*(plan: LogicalSourceExportPlan): LogicalSourceExportResult[string] =
  ## Materialize one exact detached text from the frozen original identities; execution accepts no replacement source or limits.
  if not plan.initialized: return LogicalSourceExportResult[string](
      status: LogicalSourceExportError.InvalidPlan)
  let compact = plan.source.suppliedInventory.value
  var output = newString(int(plan.info.bytes))
  var offset = 0
  putText(output, offset, CurrentLogicalSourceHeader)
  putText(output, offset, "\n")
  for i in 0..<plan.info.services:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = compact.inventoryServiceAt(ordinal).value
    putText(output, offset, "s=")
    putDecimal(output, offset, uint32(row.service))
    putText(output, offset, "\n")
    for j in 0..<row.storage:
      let index = InventoryStorageIndex(uint64(j))
      let fact = compact.inventoryStorageAt(ordinal, index).value
      let key = plan.source.copySuppliedStorageKey(ordinal, index, ByteLimit(fact.keyBytes)).value
      putText(output, offset, "k=")
      putHex(output, offset, key)
      putText(output, offset, "\n")
    for j in 0..<row.preimages:
      let fact = compact.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
      putText(output, offset, "p=")
      putHex(output, offset, array[32, byte](fact.hash))
      putText(output, offset, "\n")
    for j in 0..<row.requests:
      let fact = compact.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
      putText(output, offset, "r=")
      putHex(output, offset, array[32, byte](fact.hash))
      putText(output, offset, ":")
      putDecimal(output, offset, uint32(fact.length))
      putText(output, offset, "\n")
  LogicalSourceExportResult[string](status: LogicalSourceExportError.None, completed: output)
