# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 recent_history.tex and merklization.tex: parent correction, output tree and belt
## advancement. Inputs project already validated headers/guarantees and completed accumulation,
## not block validity.
##
## Exposes parent-history correction, accumulationRoot, advanceHistory and advanceHistoryState.

import std/algorithm
import ../codec/natural
import ../codec/state/[history as state_history, outputs as state_outputs, layout as state_layout,
    trie as state_trie]
import ../codec/bounded
import ../crypto/primitives
import ./store

type
  AccumulationRoot* = distinct array[32, byte] ## Well-balanced Keccak root of the ordered E4-service/output-commitment sequence.
  HistoryAdvance* = object ## Header-derived fields and precomputed accumulation root; reported packages are supplied separately.
    header*: HistoryHeaderHash
    parentState*: HistoryStateRoot
    slot*: HistorySlot
    accumulation*: AccumulationRoot
  HistoryTransitionError* {.pure.} = enum ## Failures retain their cause without proposed bytes or committed state.
    Uninitialized, None, InvalidConfig, InvalidState, NonCanonical, LimitExceeded,
    LengthOverflow, MissingState, BackendFailure
  HistoryTransitionResult*[T] = object ## Private success payloads require checked selection; default results are failures.
    case status: HistoryTransitionError
    of None:
      completed: T # Never expose mutable discriminators or unchecked variant fields.
    else:
      discard      # Failed alternatives contain only their reason.
  ## Binary-tree children may be raw 36-byte leaves or 32-byte internal hashes.
  OutputNode = object
    bytes: array[36, byte]
    size: int

func error*[T](outcome: HistoryTransitionResult[T]): HistoryTransitionError =
  ## Read a reason without granting access to any payload.
  outcome.status
func value*[T](outcome: HistoryTransitionResult[T]): T {.inline,
    requires: outcome.status == HistoryTransitionError.None.} =
  ## Only complete success permits extraction, including in checked optimized builds.
  outcome.completed

## Preserve resource and canonicality failures from the existing component codec.
func codecError(reason: HistoryError): HistoryTransitionError =
  case reason
  of HistoryError.None: HistoryTransitionError.None # Complete encoding/decoding only.
  of HistoryError.InvalidConfig: HistoryTransitionError.InvalidConfig # Do not infer a profile.
  of HistoryError.LimitExceeded: HistoryTransitionError.LimitExceeded # Preserve caller ceilings.
  of HistoryError.LengthOverflow: HistoryTransitionError.LengthOverflow # Never narrow unsafe sizes.
  of HistoryError.NonCanonical: HistoryTransitionError.NonCanonical # Reject duplicate/descending dictionary keys.
  else: HistoryTransitionError.InvalidState # Invalid owners, shapes and framing are not valid state.

## Preserve atomic-store failure causes without manufacturing a root or empty component.
func storeError(reason: StateStoreError): HistoryTransitionError =
  case reason
  of StateStoreError.None: HistoryTransitionError.None # Complete publication only.
  of StateStoreError.Uninitialized: HistoryTransitionError.Uninitialized # Default store is not empty state.
  of StateStoreError.MissingKey: HistoryTransitionError.MissingState # C(3) must exist explicitly.
  of StateStoreError.LimitExceeded: HistoryTransitionError.LimitExceeded # Old head remains valid.
  of StateStoreError.LengthOverflow: HistoryTransitionError.LengthOverflow # Keep native limits explicit.
  of StateStoreError.BackendFailure: HistoryTransitionError.BackendFailure # No root on primitive refusal.
  else: HistoryTransitionError.InvalidState # Unexpected store failure cannot be success.

## Copy immutable history into private synchronous scratch, after applying the caller's input policy.
proc capture(owner: HistorySnapshot, config: HistoryConfig): HistoryTransitionResult[HistoryState] =
  let info = historyInfo(owner)
  if info.error != HistoryError.None:
    return HistoryTransitionResult[HistoryState](status: HistoryTransitionError.InvalidState) # No default owners.
  if uint64(config.cores) < 2:
    return HistoryTransitionResult[HistoryState](status: HistoryTransitionError.InvalidConfig) # Explicit population.
  if uint64(info.value.blocks) > uint64(config.blocks) or uint64(info.value.peaks) > uint64(config.peaks):
    return HistoryTransitionResult[HistoryState](status: HistoryTransitionError.LimitExceeded) # Bound descriptor copies.
  var size = uint64(natural.encode(JamNatural(info.value.blocks)).len +
      natural.encode(JamNatural(info.value.peaks)).len) # Both exact canonical parent counts.
  var total = 0'u64
  # Validate nested extents before allocating any dictionary copies.
  for i in 0..<info.value.blocks:
    let record = historyBlockAt(owner, HistoryBlockIndex(uint64(i))).value
    let count = uint64(record.packages)
    let tooMany = count > uint64(config.perBlock) or count > uint64(config.cores)
    if tooMany or count > uint64(config.totalPackages)-total:
      return HistoryTransitionResult[HistoryState](
          status: HistoryTransitionError.LimitExceeded) # No aggregate overflow.
    total += uint64(record.packages)
    let fixedSize = uint64(100 + natural.encode(JamNatural(record.packages)).len)
    if size > uint64(config.maxBytes) or uint64(config.maxBytes)-size < fixedSize:
      return HistoryTransitionResult[HistoryState](
          status: HistoryTransitionError.LimitExceeded) # Fixed record plus count.
    size += fixedSize
    if uint64(record.packages) > (uint64(config.maxBytes)-size) div 64:
      return HistoryTransitionResult[HistoryState](
          status: HistoryTransitionError.LimitExceeded) # Check before multiplication.
    size += uint64(record.packages)*64
  # Bound complete peak storage before allocating copies, including trailing absent peaks.
  for i in 0..<info.value.peaks:
    let peak = historyPeakAt(owner, HistoryPeakIndex(uint64(i))).value
    let width = if peak.present: 33'u64 else: 1'u64 # Presence determines exact wire extent.
    if size > uint64(config.maxBytes) or width > uint64(config.maxBytes)-size:
      return HistoryTransitionResult[HistoryState](status: HistoryTransitionError.LimitExceeded)
    size += width
  if size > uint64(config.maxBytes):
    return HistoryTransitionResult[HistoryState](status: HistoryTransitionError.LimitExceeded) # Empty framing is bounded too.
  var source = HistoryState(blocks: newSeq[HistoryBlock](info.value.blocks),
      peaks: newSeq[HistoryPeak](info.value.peaks))
  # Copy dictionary associations without exposing or mutating retained storage.
  for i in 0..<source.blocks.len:
    let index = HistoryBlockIndex(uint64(i))
    let record = historyBlockAt(owner, index).value
    source.blocks[i] = HistoryBlock(header: record.header, state: record.state,
        superPeak: record.superPeak, slot: record.slot, packages: newSeq[ReportedPackage](
            record.packages))
    for j in 0..<record.packages:
      source.blocks[i].packages[j] = historyPackageAt(owner, index, HistoryPackageIndex(uint64(
          j))).value # Owned pair copy.
  # Presence and trailing holes are semantically retained, never normalized.
  for i in 0..<source.peaks.len:
    source.peaks[i] = historyPeakAt(owner, HistoryPeakIndex(uint64(i))).value
  let checked = historyStateEntry(source, config)
  if checked.error != HistoryError.None:
    return HistoryTransitionResult[HistoryState](status: codecError(
        checked.error)) # Exact byte policy also applies.
  HistoryTransitionResult[HistoryState](status: HistoryTransitionError.None, completed: source)

proc correctHistoryParent*(owner: HistorySnapshot, parent: HistoryStateRoot,
    config: HistoryConfig): HistoryTransitionResult[StateEntry] =
  ## Correct the latest parent record for accumulation's view; empty genesis history remains empty.
  let captured = capture(owner, config)
  if captured.error != HistoryTransitionError.None:
    return HistoryTransitionResult[StateEntry](status: captured.error) # No output after invalid input.
  var source = captured.value
  if source.blocks.len > 0:
    source.blocks[^1].state = parent # Earlier roots and every other parent field remain unchanged.
  let encoded = historyStateEntry(source, config)
  if encoded.error != HistoryError.None:
    return HistoryTransitionResult[StateEntry](status: codecError(encoded.error)) # No partial encoding.
  HistoryTransitionResult[StateEntry](status: HistoryTransitionError.None, completed: encoded.value)

## Build N recursively with logarithmic depth and fixed-size children, preserving raw singleton leaves.
proc outputNode(values: openArray[AccumulationOutput], start, count: int): HistoryTransitionResult[OutputNode] =
  if count == 1:
    # N(singleton) is the raw E4-service/hash blob, not a prehashed leaf.
    var node = OutputNode(size: 36, bytes: default(array[36, byte]))
    for i in 0..<4:
      node.bytes[i] = byte((uint32(values[start].service) shr (i*8)) and 255) # Explicit E4 little endian.
    for i in 0..<32:
      node.bytes[4+i] = array[32, byte](values[start].commitment)[i] # No implicit domain transform.
    return HistoryTransitionResult[OutputNode](status: HistoryTransitionError.None, completed: node)
  let half = count div 2 + count mod 2 # ceil(count/2), without count+1 overflow.
  let left = outputNode(values, start, half)
  if left.error != HistoryTransitionError.None:
    return left # Stop at the first primitive refusal.
  let right = outputNode(values, start+half, count-half)
  if right.error != HistoryTransitionError.None:
    return right # No parent hash from an incomplete child.
  var bytes = default(array[76, byte])
  let prefix = "node"
  for i in 0..<4: bytes[i] = byte(prefix[i]) # Domain-separated internal nodes only.
  for i in 0..<left.value.size: bytes[4+i] = left.value.bytes[i] # Child may still be 36 bytes.
  for i in 0..<right.value.size: bytes[4+left.value.size+i] = right.value.bytes[i] # Preserve left/right order.
  let digest = keccak256(bytes.toOpenArray(0, 3+left.value.size+right.value.size))
  if digest.error != CryptoError.None:
    return HistoryTransitionResult[OutputNode](status: HistoryTransitionError.BackendFailure) # No default digest.
  var node = OutputNode(size: 32, bytes: default(array[36, byte]))
  for i in 0..<32: node.bytes[i] = array[32, byte](digest.value)[i] # Internal child is exactly one hash.
  HistoryTransitionResult[OutputNode](status: HistoryTransitionError.None, completed: node)

proc accumulationRoot*(values: openArray[AccumulationOutput],
    config: OutputLogConfig): HistoryTransitionResult[AccumulationRoot] =
  ## Derive the well-balanced Keccak root from stable ordered output pairs; no sorting or deduplication.
  if uint64(values.len) > uint64(config.items):
    return HistoryTransitionResult[AccumulationRoot](
        status: HistoryTransitionError.LimitExceeded) # Bound work first.
  let checked = outputLogEntry(values, config)
  if checked.error != OutputLogError.None:
    # Reuse exact E4/hash framing and native extent validation; this temporary does not escape.
    let reason = if checked.error == OutputLogError.LengthOverflow: HistoryTransitionError.LengthOverflow else: HistoryTransitionError.LimitExceeded
    return HistoryTransitionResult[AccumulationRoot](status: reason)
  if values.len == 0:
    return HistoryTransitionResult[AccumulationRoot](status: HistoryTransitionError.None,
        completed: AccumulationRoot(default(array[32, byte]))) # Empty N is zero, not Keccak(empty).
  let node = outputNode(values, 0, values.len)
  if node.error != HistoryTransitionError.None:
    return HistoryTransitionResult[AccumulationRoot](status: node.error) # No root after hash refusal.
  var root = default(array[32, byte])
  if values.len == 1:
    # The well-balanced wrapper hashes a single raw leaf exactly once.
    let digest = keccak256(node.value.bytes)
    if digest.error != CryptoError.None:
      return HistoryTransitionResult[AccumulationRoot](
          status: HistoryTransitionError.BackendFailure)
    root = array[32, byte](digest.value)
  else:
    for i in 0..<32: root[i] = node.value.bytes[i] # N already hashed the internal root.
  HistoryTransitionResult[AccumulationRoot](status: HistoryTransitionError.None,
      completed: AccumulationRoot(root))

## Canonical dictionary order is by package octets, independent of guarantee/core order.
func comparePackages(a, b: ReportedPackage): int =
  for i in 0..<32:
    if a.package.bytes[i] < b.package.bytes[i]: return -1 # First unequal octet determines order.
    if a.package.bytes[i] > b.package.bytes[i]: return 1 # Values never decide dictionary order.
  0 # Duplicate keys are rejected by the existing canonical encoder after sorting.

proc advanceHistory*(owner: HistorySnapshot, input: HistoryAdvance,
    packages: openArray[ReportedPackage], config: HistoryConfig): HistoryTransitionResult[StateEntry] =
  ## Correct parent, append the accumulation root to the belt, bag peaks and retain the newest eight records.
  let captured = capture(owner, config)
  if captured.error != HistoryTransitionError.None:
    return HistoryTransitionResult[StateEntry](status: captured.error) # No hashing under invalid input policy.
  let packageCount = uint64(packages.len)
  let tooMany = packageCount > uint64(config.cores) or packageCount > uint64(config.perBlock)
  if tooMany or packageCount > uint64(config.totalPackages):
    return HistoryTransitionResult[StateEntry](status: HistoryTransitionError.LimitExceeded) # Bound new dictionary copy.
  if packages.len > high(int) div sizeof(ReportedPackage) or
      uint64(packages.len) > uint64(config.maxBytes) div 64:
    return HistoryTransitionResult[StateEntry](status: HistoryTransitionError.LimitExceeded) # Before dictionary allocation.
  var reported = @packages
  reported.sort(comparePackages) # The mathematical dictionary is independent of guarantee/core order.
  var source = captured.value
  if source.blocks.len > 0:
    source.blocks[^1].state = input.parentState # Safe to repeat after the explicit pre-accumulation correction.
  if source.blocks.len == 8:
    source.blocks.delete(0) # Discard only the oldest record, retaining seven prior records.
  source.blocks.add HistoryBlock(header: input.header, state: HistoryStateRoot(default(array[32,
      byte])), superPeak: HistorySuperPeak(default(array[32, byte])), slot: input.slot,
          packages: reported)
  var position = 0
  while position < source.peaks.len and source.peaks[position].present:
    inc position # Determine carry extent without hashing or changing the source peaks.
  if position == source.peaks.len:
    if uint64(source.peaks.len) >= uint64(config.peaks) or source.peaks.len >= high(int) div sizeof(HistoryPeak):
      return HistoryTransitionResult[StateEntry](status: HistoryTransitionError.LimitExceeded) # Bound new peak before append.
    source.peaks.add absentHistoryPeak()
  # Preflight the exact prospective output shape, including dictionary canonicality and byte budgets.
  for i in 0..<position: source.peaks[i] = absentHistoryPeak() # Carried peaks become absent.
  source.peaks[position] = presentHistoryPeak(HistoryPeakHash(array[32, byte](input.accumulation)))
  let planned = historyStateEntry(source, config)
  if planned.error != HistoryError.None:
    return HistoryTransitionResult[StateEntry](status: codecError(planned.error)) # No hash on invalid output.
  var carry = array[32, byte](input.accumulation)
  for i in 0..<position:
    # Belt carries hash old peak || new carry, without a tree-node prefix.
    let old = historyPeakAt(owner, HistoryPeakIndex(uint64(i))).value
    var bytes = default(array[64, byte])
    for j in 0..<32:
      bytes[j] = array[32, byte](old.hash)[j]
      bytes[32+j] = carry[j]
    let digest = keccak256(bytes)
    if digest.error != CryptoError.None:
      return HistoryTransitionResult[StateEntry](status: HistoryTransitionError.BackendFailure) # Discard private scratch.
    carry = array[32, byte](digest.value)
  source.peaks[position] = presentHistoryPeak(HistoryPeakHash(carry))
  var superPeak = default(array[32, byte])
  var seen = false
  for peak in source.peaks:
    if peak.present:
      if not seen:
        superPeak = array[32, byte](peak.hash) # A sole present peak is returned without hashing.
        seen = true
      else:
        var bytes = default(array[68, byte])
        let prefix = "peak"
        for i in 0..<4: bytes[i] = byte(prefix[i]) # Bag present peaks in ascending belt-position order.
        for i in 0..<32:
          bytes[4+i] = superPeak[i]
          bytes[36+i] = array[32, byte](peak.hash)[i]
        let digest = keccak256(bytes)
        if digest.error != CryptoError.None:
          return HistoryTransitionResult[StateEntry](
              status: HistoryTransitionError.BackendFailure) # No partial commitment.
        superPeak = array[32, byte](digest.value)
  source.blocks[^1].superPeak = HistorySuperPeak(superPeak)
  let encoded = historyStateEntry(source, config)
  if encoded.error != HistoryError.None:
    return HistoryTransitionResult[StateEntry](status: codecError(
        encoded.error)) # Payload shape already preflighted.
  HistoryTransitionResult[StateEntry](status: HistoryTransitionError.None, completed: encoded.value)

proc advanceHistoryState*(state: var StateStore, input: HistoryAdvance,
    packages: openArray[ReportedPackage], config: HistoryConfig): HistoryTransitionResult[
        StateStoreSnapshot] =
  ## Read exact C(3), advance privately and publish one atomic write; all unrelated state remains unchanged.
  let before = state.snapshot
  if before.error != StateStoreError.None:
    return HistoryTransitionResult[StateStoreSnapshot](status: storeError(before.error)) # No default store.
  let entry = before.value.lookup(chapterKey(StateChapter(3)))
  if entry.error != StateStoreError.None:
    return HistoryTransitionResult[StateStoreSnapshot](status: storeError(
        entry.error)) # Missing is not empty history.
  if uint64(entry.value.byteLength) > uint64(config.maxBytes):
    return HistoryTransitionResult[StateStoreSnapshot](
        status: HistoryTransitionError.LimitExceeded) # Before copying.
  let bytes = entry.value.bytes
  let decoded = decodeHistoryState(bytes, config)
  if decoded.error != HistoryError.None:
    return HistoryTransitionResult[StateStoreSnapshot](status: codecError(
        decoded.error)) # Reject malformed stored state.
  if decoded.value.consumed != bytes.len:
    return HistoryTransitionResult[StateStoreSnapshot](
        status: HistoryTransitionError.InvalidState) # No suffix acceptance.
  let advanced = advanceHistory(decoded.value.snapshot, input, packages, config)
  if advanced.error != HistoryTransitionError.None:
    return HistoryTransitionResult[StateStoreSnapshot](status: advanced.error) # No write from failed computation.
  let committed = state.apply(@[StateWrite(key: advanced.value.key, kind: StateWriteKind.Put,
      value: advanced.value.value)])
  if committed.error != StateStoreError.None:
    return HistoryTransitionResult[StateStoreSnapshot](status: storeError(
        committed.error)) # Store preserves old head.
  HistoryTransitionResult[StateStoreSnapshot](status: HistoryTransitionError.None,
      completed: committed.value)
