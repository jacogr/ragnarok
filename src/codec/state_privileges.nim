# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T chapter 12: E4 role services and a count-prefixed E4-service/E8-gas dictionary.
## Serialization preserves privileges; it does not authorize services or execute privilege
## changes.
##
## Exposes privilege profiles and snapshots, chapter-12 entry construction/decoding and
## assigner/accumulation-service access.

import std/assertions
import ./[natural, bounded, composite, assurances, state_layout, state_trie]
export ServiceIndex, CoreCount

type
  ## Gas allowance has the full unsigned 64-bit domain, distinct from service IDs and byte limits.
  PrivilegeGas* = distinct uint64
  ## A core position is not a service ID or an ordinal in the always-accumulate dictionary.
  PrivilegeCoreIndex* = distinct uint64
  ## Dictionary extraction uses its own ordinal, not a protocol service identifier.
  PrivilegeEntryIndex* = distinct uint64
  ## Fixed service/gas pair; numeric service keys must be strictly increasing in source order.
  AlwaysAccumulate* = object
    service*: ServiceIndex
    gas*: PrivilegeGas
  ## Stable synchronous source; assigners have exactly the configured core count, without a wire count.
  PrivilegeState* = object
    manager*, delegator*, registrar*: ServiceIndex
    assigners*: seq[ServiceIndex]
    always*: seq[AlwaysAccumulate]
  ## Supported chain profile plus caller ceilings on dictionary work and the complete component bytes.
  PrivilegeConfig* = object
    cores*: CoreCount
    maxAlways*: ElementLimit
    maxBytes*: ByteLimit
  ## Failed/default results contain only reasons, never owners, source values or partial cursors.
  PrivilegeError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical,
    LimitExceeded, LengthOverflow, InvalidService, InvalidOwner, InvalidIndex
  ## Success is the only alternative that contains a usable payload.
  PrivilegeResult*[T] = object
    case status: PrivilegeError
    of None:
      completed: T # Select success before reading application data.
    else:
      discard      # Defaults and failures carry no fabricated state.
  ## Private immutable acyclic ARC storage contains independent fixed values only.
  PrivilegeData = ref object
    state: PrivilegeState
  ## Value handles share retained storage; caller replacement never changes another handle's state.
  PrivilegeSnapshot* = object
    data: nil PrivilegeData
  ## Complete prefix success binds the retained component to its exact consumed extent.
  PrivilegeRead* = object
    snapshot*: PrivilegeSnapshot
    consumed*: int
  ## Scalar metadata is copied without exposing the retained assigner/dictionary arrays.
  PrivilegeInfo* = object
    manager*, delegator*, registrar*: ServiceIndex
    cores*, always*: int
  ## Private scan proof contains only bounded offsets/counts and never escapes to callers.
  Layout = object
    start, count, consumed: int

## A reason is read-only and never authorizes values or partial parsing progress.
func error*[T](value: PrivilegeResult[T]): PrivilegeError = value.status
## Public payloads and internal scalar/layout proofs require success under optimized builds too.
func value*[T](value: PrivilegeResult[T]): T {.inline, requires: value.status ==
    PrivilegeError.None.} =
  value.completed

## Reject unsupported profiles before any field access or native count conversion.
proc validate(config: PrivilegeConfig): PrivilegeError =
  if uint64(config.cores) < 2 or uint64(config.cores) > 341:
    return PrivilegeError.InvalidConfig # Match the existing tiny/full core-profile domain.
  if uint64(config.maxBytes) < 4*(uint64(config.cores)+3):
    return PrivilegeError.LimitExceeded # All fixed E4 roles consume parent budget even before the dictionary count.
  PrivilegeError.None

## Charge a proved nonnegative byte extent before arithmetic or a subsequent read/write.
proc grow(cursor: var int, amount: int, config: PrivilegeConfig): PrivilegeError =
  if amount > high(int)-cursor: return PrivilegeError.LengthOverflow # Check before native addition.
  cursor += amount
  if uint64(cursor) > uint64(config.maxBytes): return PrivilegeError.LimitExceeded # Count/key/value bytes share one budget.
  PrivilegeError.None

## Bound announced dictionary work and native typed storage before traversing any pair.
proc countError(count: uint64, config: PrivilegeConfig): PrivilegeError =
  if count > uint64(config.maxAlways): return PrivilegeError.LimitExceeded # Caller policy precedes work/allocation.
  if count > uint64(high(int) div sizeof(AlwaysAccumulate)):
    return PrivilegeError.LengthOverflow # Typed storage must fit, not just minimal wire size.
  PrivilegeError.None

## Read one canonical natural into a local fixed result; only success advances the private cursor.
proc readNatural(input: openArray[byte], cursor: var int,
    config: PrivilegeConfig): PrivilegeResult[uint64] =
  let parsed = natural.decode(input.toOpenArray(cursor, input.len-1))
  if not parsed.ok:
    if parsed.error == DecodeError.truncated:
      return PrivilegeResult[uint64](status: PrivilegeError.Truncated) # Missing fields publish no partial progress.
    else:
      return PrivilegeResult[uint64](status: PrivilegeError.NonCanonical) # No alternate dictionary count representation.
  let error = grow(cursor, parsed.consumed, config)
  if error != PrivilegeError.None: return PrivilegeResult[uint64](
      status: error) # Complete scalar still consumes policy.
  PrivilegeResult[uint64](status: PrivilegeError.None, completed: uint64(parsed.value))

## Copy one prevalidated E4 service with explicit little-endian shifts, retaining no input coordinates.
proc serviceAt(input: openArray[byte], offset: int): ServiceIndex =
  var value = 0'u32
  # Every caller has already proved all four bytes present.
  for j in 0..<4: value = value or (uint32(input[offset+j]) shl (j*8))
  ServiceIndex(value)

## Copy one proved E8 gas allowance without alignment or host-endian assumptions.
proc gasAt(input: openArray[byte], offset: int): PrivilegeGas =
  var value = 0'u64
  # Whole-parent preflight proves all eight source bytes exist before capture.
  for j in 0..<8: value = value or (uint64(input[offset+j]) shl (j*8))
  PrivilegeGas(value)

## Preflight the full parent without allocation; key order is numeric, never encoded-octet order.
proc scan(input: openArray[byte], config: PrivilegeConfig): PrivilegeResult[Layout] =
  let valid = validate(config)
  if valid != PrivilegeError.None: return PrivilegeResult[Layout](
      status: valid) # Invalid policy precedes input work.
  var cursor = 4*(int(uint64(config.cores))+3)
  if input.len < cursor: return PrivilegeResult[Layout](
      status: PrivilegeError.Truncated) # All fixed roles must be present.
  let count = readNatural(input, cursor, config)
  if count.error != PrivilegeError.None: return PrivilegeResult[Layout](
      status: count.error) # Require canonical dictionary count.
  let error = countError(count.value, config)
  if error != PrivilegeError.None: return PrivilegeResult[Layout](status: error) # No announced-count allocation.
  let start = cursor
  var previous = 0'u64
  # Fixed E4 keys and E8 gas are fully present and numerically ordered before any owner allocation.
  for i in 0..<int(count.value):
    let start = cursor
    let keyError = grow(cursor, 4, config)
    if keyError != PrivilegeError.None: return PrivilegeResult[Layout](
        status: keyError) # Key padding consumes budget.
    if cursor > input.len: return PrivilegeResult[Layout](
        status: PrivilegeError.Truncated) # Require every E4 octet.
    let key = uint64(uint32(serviceAt(input, start)))
    if i > 0 and key <= previous:
      return PrivilegeResult[Layout](status: PrivilegeError.NonCanonical) # Compare decoded numeric IDs, not little-endian octets.
    previous = key
    let gasError = grow(cursor, 8, config)
    if gasError != PrivilegeError.None: return PrivilegeResult[Layout](
        status: gasError) # Full E8 gas shares parent policy.
    if cursor > input.len: return PrivilegeResult[Layout](
        status: PrivilegeError.Truncated) # Late gas failure publishes no owner.
  PrivilegeResult[Layout](status: PrivilegeError.None,
    completed: Layout(start: start, count: int(count.value), consumed: cursor))

## Capture the complete component only after every late dictionary key/value has passed preflight.
proc decodePrivilegeState*(input: openArray[byte], config: PrivilegeConfig): PrivilegeResult[
    PrivilegeRead] =
  let checked = scan(input, config)
  if checked.error != PrivilegeError.None: return PrivilegeResult[PrivilegeRead](
      status: checked.error) # No failed owner/progress.
  let cores = int(uint64(config.cores))
  let data = PrivilegeData(state: PrivilegeState(manager: serviceAt(input, 0),
    delegator: serviceAt(input, 4*(cores+1)), registrar: serviceAt(input, 4*(cores+2)),
    assigners: newSeq[ServiceIndex](cores), always: newSeq[AlwaysAccumulate](checked.value.count)))
  # Fixed core positions have no per-array count prefix.
  for i in 0..<cores: data.state.assigners[i] = serviceAt(input, 4*(i+1))
  var cursor = checked.value.start
  # Repeat only proved fixed reads to copy values into independent immutable storage.
  for i in 0..<checked.value.count:
    data.state.always[i] = AlwaysAccumulate(service: serviceAt(input, cursor), gas: gasAt(input, cursor+4))
    cursor += 12
  PrivilegeResult[PrivilegeRead](status: PrivilegeError.None,
    completed: PrivilegeRead(snapshot: PrivilegeSnapshot(data: data),
        consumed: checked.value.consumed))

## Commit a canonical natural after the whole source has passed sizing, order and byte-policy checks.
proc putNatural(value: uint64, output: var seq[byte], cursor: var int) =
  let encoded = natural.encode(JamNatural(value))
  # The measured final destination already contains space for every canonical scalar byte.
  for i in 0..<encoded.len:
    output[cursor] = encoded.bytes[i]
    inc cursor

## Commit an E4 service identifier for either a fixed role or a dictionary key.
proc putService(value: ServiceIndex, output: var seq[byte], cursor: var int) =
  # Fixed E4 retains leading zeroes and every high service-index octet.
  for j in 0..<4:
    output[cursor] = byte((uint32(value) shr (j*8)) and 255)
    inc cursor

## Commit an E8 gas allowance only after complete parent extent and order validation.
proc putGas(value: PrivilegeGas, output: var seq[byte], cursor: var int) =
  # Every high and low gas octet is retained, including zero padding and uint64 maximum.
  for j in 0..<8:
    output[cursor] = byte((uint64(value) shr (j*8)) and 255)
    inc cursor

## Encode a stable exact-shape source into independent C(12) bytes after complete preflight.
proc privilegeStateEntry*(source: PrivilegeState, config: PrivilegeConfig): PrivilegeResult[StateEntry] =
  let valid = validate(config)
  if valid != PrivilegeError.None: return PrivilegeResult[StateEntry](
      status: valid) # Policy precedes source traversal.
  if uint64(source.assigners.len) != uint64(config.cores):
    return PrivilegeResult[StateEntry](status: PrivilegeError.InvalidCount) # No missing core or extra array count is inferred.
  let count = countError(uint64(source.always.len), config)
  if count != PrivilegeError.None: return PrivilegeResult[StateEntry](
      status: count) # Bound work before sizing pairs.
  var size = 4*(source.assigners.len+3)
  var error = grow(size, natural.encode(JamNatural(source.always.len)).len, config)
  if error != PrivilegeError.None: return PrivilegeResult[StateEntry](
      status: error) # Empty dictionary still emits its count.
  # Numeric dictionary order is required from sources; no silent sorting or last-key-wins repair.
  for i, pair in source.always:
    if i > 0 and uint32(pair.service) <= uint32(source.always[i-1].service):
      return PrivilegeResult[StateEntry](status: PrivilegeError.NonCanonical) # Even a late duplicate invalidates all output.
    error = grow(size, 4, config)
    if error != PrivilegeError.None: return PrivilegeResult[StateEntry](
        status: error) # All four key bytes consume parent policy.
    error = grow(size, 8, config)
    if error != PrivilegeError.None: return PrivilegeResult[StateEntry](
        status: error) # All eight gas bytes consume parent policy.
  var entry = StateEntry(key: chapterKey(StateChapter(12)), value: newSeq[byte](size))
  var cursor = 0
  putService(source.manager, entry.value, cursor)
  # Core-position order is preserved, including duplicate service IDs across distinct roles/cores.
  for service in source.assigners: putService(service, entry.value, cursor)
  putService(source.delegator, entry.value, cursor)
  putService(source.registrar, entry.value, cursor)
  putNatural(uint64(source.always.len), entry.value, cursor)
  # All dictionary pairs now fit and have unique ascending numeric service keys.
  for pair in source.always:
    putService(pair.service, entry.value, cursor)
    putGas(pair.gas, entry.value, cursor)
  PrivilegeResult[StateEntry](status: PrivilegeError.None, completed: entry)

## Return copied scalar roles and cardinalities without exporting retained arrays.
proc privilegeInfo*(owner: PrivilegeSnapshot): PrivilegeResult[PrivilegeInfo] =
  let data = owner.data
  if data == nil: return PrivilegeResult[PrivilegeInfo](
      status: PrivilegeError.InvalidOwner) # Defaults are not valid empty state.
  PrivilegeResult[PrivilegeInfo](status: PrivilegeError.None,
    completed: PrivilegeInfo(manager: data.state.manager, delegator: data.state.delegator,
      registrar: data.state.registrar,
      cores: data.state.assigners.len, always: data.state.always.len))

## Extract one fixed assigner by nominal core position, keeping dictionary ordinals separate.
proc privilegeAssignerAt*(owner: PrivilegeSnapshot, index: PrivilegeCoreIndex): PrivilegeResult[ServiceIndex] =
  let data = owner.data
  if data == nil: return PrivilegeResult[ServiceIndex](
      status: PrivilegeError.InvalidOwner) # No default service on absent storage.
  if uint64(index) >= uint64(data.state.assigners.len):
    return PrivilegeResult[ServiceIndex](status: PrivilegeError.InvalidIndex) # Bound before narrowing/access.
  PrivilegeResult[ServiceIndex](status: PrivilegeError.None, completed: data.state.assigners[int(
      uint64(index))])

## Extract one copied service/gas pair, independent of both its snapshot and source arrays.
proc alwaysAccumulateAt*(owner: PrivilegeSnapshot, index: PrivilegeEntryIndex): PrivilegeResult[
    AlwaysAccumulate] =
  let data = owner.data
  if data == nil: return PrivilegeResult[AlwaysAccumulate](
      status: PrivilegeError.InvalidOwner) # No fabricated pair on default owners.
  if uint64(index) >= uint64(data.state.always.len):
    return PrivilegeResult[AlwaysAccumulate](status: PrivilegeError.InvalidIndex) # Dictionary has its own cardinality.
  PrivilegeResult[AlwaysAccumulate](status: PrivilegeError.None, completed: data.state.always[int(
      uint64(index))])
