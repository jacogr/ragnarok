# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable complete-map block snapshots, including the configured genesis compatibility adapter.
## Exposes GenesisResult, guarded snapshot accessors, read-only lookup, serviceCount/serviceAt
## and captureBlockSnapshot/captureGenesis. The supplied map is trusted as complete;
## structural validation does not
## establish consensus or validate every chapter. Optional C(4) supplies a cached RPC ticket limit;
## C(8) also supplies erasure geometry.

import std/[algorithm, assertions]
import ./parameters
import ../codec/[header, assurances, bounded, state_layout, state_trie, state_safrole,
    state_accounts, state_consensus]
import ../state/store
import ../crypto/primitives

type
  ## Original data bytes in one basic erasure-coding piece, derived from active validators.
  ErasurePieceLength* = distinct uint64
  ## Number of basic pieces in one fixed 4104-byte segment.
  SegmentPieceCount* = distinct uint64
  ## Advertised ticket-attempt limit; zero explicitly represents an unavailable derivation.
  RpcTicketAttempts* = distinct uint64
  ## An ordinal in the retained service list, distinct from a service ID or state key.
  ServiceListIndex* = distinct int
  ## Ordinal in the retained sorted serialized-key index, bound to its genesis owner.
  StateKeyIndex* = distinct int
  ## Block identity is a full sealed-header hash, never a state root.
  BlockHash* = distinct array[32, byte]
  ## Private immutable retained state with copied descriptor fields; no mutable store escapes.
  BlockSnapshot* = object
    ready: bool
    state: StateStoreSnapshot
    sealedHeader: OwnedHeader        # Retain the codec owner of the exact hashed wire bytes.
    identity: BlockHash
    parentIdentity: BlockHash
    priorCommitment: StateRoot
    configuration: Parameters        # Complete immutable fetch tuple, used to reject mixed chain profiles.
    timeslot: uint32
    epochLength: EpochSlots          # Captured with the same parameters as header validation.
    corePopulation: CoreCount
    pieceLength: ErasurePieceLength  # Derived once from the validated active C(8) population.
    ticketLimit: RpcTicketAttempts   # Cached at capture; optional C(4) never runs in the dispatcher.
    activePopulation: ValidatorCount # Actual C(8) population used for header validation.
    keys: seq[StateKey]              # Private fixed-width copies; at most 16384 entries.
    services: seq[ServiceIndex]      # Private sorted IDs captured with the same immutable state.
  ## Compatibility name for the configured genesis snapshot; storage is shared with block snapshots.
  Genesis* = BlockSnapshot
  ## Absent configuration differs from a supplied but invalid genesis pair.
  GenesisError* {.pure.} = enum
    Unavailable, None, Invalid
  ## Only success contains a usable immutable block snapshot.
  GenesisResult* = object
    case status: GenesisError
    of None:
      completed: BlockSnapshot
    else:
      discard # Failed and default alternatives carry no chain data.

## Generic name for the same guarded capture result used by startup genesis loading.
type BlockSnapshotResult* = GenesisResult

## Read status without exposing the discriminator to mutation.
func error*(value: GenesisResult): GenesisError = value.status
## Extract only a successful chain snapshot.
func value*(value: GenesisResult): BlockSnapshot {.requires: value.status ==
    GenesisError.None.} = value.completed
## Construct an explicit unavailable result for absent snapshot/configuration.
func unavailableGenesis*(): GenesisResult = GenesisResult(status: GenesisError.Unavailable)
## Construct a failed result for malformed explicit configuration.
func invalidGenesis*(): GenesisResult = GenesisResult(status: GenesisError.Invalid)
## Return the copied block identity.
func blockHash*(value: BlockSnapshot): BlockHash {.requires: value.ready.} = value.identity
## Return the header's claimed parent identity; only a provider lookup establishes parent availability.
func parentHash*(value: BlockSnapshot): BlockHash {.requires: value.ready.} = value.parentIdentity
## Return the header's prior root, distinct from the captured posterior state commitment.
func priorStateRoot*(value: BlockSnapshot): StateRoot {.requires: value.ready.} = value.priorCommitment
## Compare complete protocol tuples so retained history cannot silently mix startup chain profiles.
func sameParameters*(left, right: BlockSnapshot): bool {.requires: left.ready and right.ready.} =
  for field in low(Parameter)..high(Parameter):
    if left.configuration.get(field) != right.configuration.get(field):
      return false # Every encoded fetch field participates, not only cores and epoch length.
  true

## Retain the validated immutable sealed-header owner, independent of the genesis handle lifetime.
func header*(value: BlockSnapshot): OwnedHeader {.requires: value.ready.} = value.sealedHeader
## Return the retained core configuration used to decode this snapshot.
func cores*(value: BlockSnapshot): CoreCount {.requires: value.ready.} = value.corePopulation
## Return the copied active validator population from the exactly decoded C(8) roster.
func activeValidators*(value: BlockSnapshot): ValidatorCount {.requires: value.ready.} = value.activePopulation
## Return the cached GP 0.8.0 basic piece length, independent of optional pending-roster state.
func basicPieceLength*(value: BlockSnapshot): ErasurePieceLength {.requires: value.ready.} = value.pieceLength
## Return the exact number of basic pieces in a segment; capture proves positive divisibility.
func segmentPieces*(value: BlockSnapshot): SegmentPieceCount {.requires: value.ready.} =
  SegmentPieceCount(4104 div uint64(value.pieceLength))
## Return the cached RPC ticket limit, or its documented zero when C(4) cannot be derived.
func ticketAttempts*(value: BlockSnapshot): RpcTicketAttempts {.requires: value.ready.} = value.ticketLimit
## Return the captured epoch-ring length used to decode retained ready state.
func epochSlots*(value: BlockSnapshot): EpochSlots {.requires: value.ready.} = value.epochLength
## Return the copied genesis timeslot.
func slot*(value: BlockSnapshot): uint32 {.requires: value.ready.} = value.timeslot
## Return the bounded number of structurally valid service accounts discovered at capture.
func serviceCount*(value: BlockSnapshot): int {.requires: value.ready.} = value.services.len
## Return a copied ID by owner-bound ordinal; no mutable sequence or detached view escapes.
func serviceAt*(value: BlockSnapshot, index: ServiceListIndex): ServiceIndex {.requires: value.ready and
    int(index) >= 0 and int(index) < value.services.len.} = value.services[int(index)]

## Return the number of exact serialized keys retained with this snapshot.
func keyCount*(value: BlockSnapshot): int {.requires: value.ready.} = value.keys.len
## Copy one key without exporting mutable index storage.
func keyAt*(value: BlockSnapshot, index: StateKeyIndex): StateKey {.requires: value.ready and
    int(index) >= 0 and int(index) < value.keys.len.} = value.keys[int(index)]

## Compare full serialized keys by unsigned octet order, independent of Base64 spelling.
func compareStateKey(left, right: StateKey): int =
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    # The first differing octet determines dictionary order.
    if a[index] < b[index]: return -1 # Smaller octets precede larger ones.
    if a[index] > b[index]: return 1 # Distinct keys never compare equal.
  0

## Locate the first strictly greater key; keyCount is the valid end sentinel.
proc keyAfter*(value: BlockSnapshot, key: StateKey): StateKeyIndex {.requires: value.ready.} =
  var low = 0
  var high = value.keys.len
  while low < high:
    # Upper-bound search also accepts a cursor absent from this immutable snapshot.
    let middle = low + (high - low) div 2
    if compareStateKey(value.keys[middle], key) <= 0:
      low = middle + 1 # The cursor itself must not repeat on the next page.
    else:
      high = middle # Preserve the first possible strictly greater key.
  StateKeyIndex(low)

## Capture a bounded sorted key index only after the complete map has validated.
proc captureKeys(entries: openArray[StateEntry]): seq[StateKey] =
  result = newSeq[StateKey](entries.len)
  for index in 0..<entries.len:
    # Copy fixed keys; no value bytes or caller-owned arrays are retained here.
    result[index] = entries[index].key
  result.sort(compareStateKey) # Store validation has already rejected duplicates.

## Sort numeric IDs rather than the little-endian interleaved serialized account keys.
proc compareService(left, right: ServiceIndex): int =
  if uint32(left) < uint32(right): return -1 # Smaller numeric IDs precede larger IDs.
  if uint32(left) > uint32(right): return 1 # Preserve the complete unsigned domain.
  0

## Discover only exact C(255, service) keys with complete supported metadata in a validated bounded map.
## Borrow input solely during capture; the returned scalar sequence owns no caller aliases.
proc discoverServices(entries: openArray[StateEntry]): seq[ServiceIndex] =
  result = @[]
  for entry in entries:
    # Hash-derived storage keys cannot be classified as accounts from one prefix byte alone.
    let key = array[31, byte](entry.key)
    if key[0] != 255 or entry.value.len != ServiceMetadataBytes: continue
    var service = 0'u32
    for i in 0..<4: # C(255, service) interleaves four little-endian ID octets at odd offsets.
      service = service or (uint32(key[1 + i * 2]) shl (8 * i))
    if key != array[31, byte](chapterServiceKey(StateChapter(255), ServiceIndex(service))):
      continue # Every fixed zero octet must match the maintained key constructor too.
    let metadata = decodeServiceMetadata(entry.value, ByteLimit(ServiceMetadataBytes))
    if metadata.error != ServiceMetadataError.None:
      continue # Best-effort discovery excludes malformed or unsupported records.
    result.add(ServiceIndex(service))
  result.sort(compareService) # The validated map already rejects duplicate keys and therefore IDs.

## Read the computed posterior root of the supplied genesis map, not the header's prior-state field.
proc stateRoot*(value: BlockSnapshot): StateRoot {.requires: value.ready.} = value.state.commitment.root

## Read a serialized key from this retained snapshot; the view owns its lifetime, and default owners fail.
proc lookup*(value: BlockSnapshot, key: StateKey): StateStoreResult[StateValue] =
  store.lookup(value.state, key)

## Select GP ecoriginalshards from an already validated active roster, then return twice that count.
## At most 342 candidates are checked; no allocation or erasure encoding occurs here.
proc capturePieceLength(validators: ValidatorCount): ErasurePieceLength =
  let count = uint64(validators)
  assert count >= 6 and count <= 1023 and count mod 3 == 0
  var shards = count div 3 + 1
  while 4104 mod (2 * shards) != 0:
    dec shards # One always divides 2052, so the search terminates before a zero divisor.
  ErasurePieceLength(2 * shards)

## Derive the advertised limit from complete C(4), borrowing only a validated immutable store.
## Missing, malformed or policy-limited optional state maps to the documented RPC zero placeholder.
## This checks serialization, not key validity, ticket eligibility or Safrole consensus transitions.
proc captureTicketAttempts(state: StateStoreSnapshot, cores: CoreCount,
    epoch: EpochSlots): RpcTicketAttempts =
  let slots = uint64(epoch)
  if slots == 0 or slots > 4096:
    return RpcTicketAttempts(0) # Bound schedule and accumulator work independently of wire size.
  let found = state.lookup(chapterKey(StateChapter(4)))
  if found.error != StateStoreError.None:
    return RpcTicketAttempts(0) # Optional state must not manufacture a pending roster.
  if found.value.byteLength > 1024 * 1024:
    return RpcTicketAttempts(0) # Bound copying before obtaining the chapter bytes.
  let wire = found.value.bytes
  let decoded = decodeSafroleState(wire, SafroleStateConfig(
    validators: ValidatorStateConfig(cores: cores, validators: ElementLimit(1023),
      maxBytes: ByteLimit(1024 * 1024)), epochSlots: epoch,
    maxAccumulator: ElementLimit(4096), maxBytes: ByteLimit(1024 * 1024)))
  if decoded.error != StateComponentError.None:
    return RpcTicketAttempts(0) # A valid roster prefix alone cannot authorize a derived value.
  if decoded.value.consumed != wire.len:
    return RpcTicketAttempts(0) # Reject trailing bytes after the complete Safrole chapter.
  let metadata = safroleInfo(decoded.value.snapshot)
  if metadata.error != StateComponentError.None:
    return RpcTicketAttempts(0) # Only the successful owner supplies the pending population.
  let pending = uint64(metadata.value.validators)
  assert pending >= 6 # The exact roster decoder established a nonzero valid population.
  # The 4096-slot ceiling proves multiplication and ceiling-division addition cannot overflow.
  RpcTicketAttempts((2 * slots + pending - 1) div pending)

## Capture a structurally checked header and supplied posterior map, using its active roster and time.
## Input bytes are borrowed only during this call; no signature or whole-state validation is claimed.
proc captureBlockSnapshot*(wire: openArray[byte], entries: openArray[StateEntry],
    parameters: Parameters): BlockSnapshotResult =
  let cores = parameters.get(coreCount)
  if cores > 341 or wire.len == 0 or wire.len > 256 * 1024 or entries.len > 16384:
    return invalidGenesis() # Bound profile, header and map before owned construction.
  var roster: seq[byte] = @[]
  var time: seq[byte] = @[]
  # Required context is obtained from actual serialized state, never inferred from core count.
  for entry in entries:
    let key = array[31, byte](entry.key)
    if key == array[31, byte](chapterKey(StateChapter(8))): roster = entry.value # Active author population.
    elif key == array[31, byte](chapterKey(StateChapter(11))): time = entry.value # State/header slot consistency.
  let validators = decodeStateValidators(roster, ValidatorStateConfig(cores: CoreCount(cores),
    validators: ElementLimit(1023), maxBytes: ByteLimit(1024 * 1024)))
  if validators.error != StateComponentError.None: return invalidGenesis() # Missing or malformed C(8).
  if validators.value.consumed != roster.len: return invalidGenesis() # No trailing state bytes.
  let count = validatorCount(validators.value.value)
  if count.error != StateComponentError.None: return invalidGenesis() # Only owned rosters supply context.
  let clock = decodeStateTime(time)
  if clock.error != StateComponentError.None: return invalidGenesis() # C(11) must encode an exact slot.
  if clock.value.consumed != time.len: return invalidGenesis() # Reject extended time encodings.
  let decoded = decodeHeader(wire, HeaderConfig(cores: CoreCount(cores),
    authorValidators: ValidatorCount(count.value), epochSlots: EpochSlots(parameters.get(
        epochPeriod)),
    maxBytes: ByteLimit(256 * 1024)))
  if decoded.error != HeaderError.None: return invalidGenesis() # Canonical header framing and author range.
  let info = headerInfo(decoded.value.owner)
  if info.error != HeaderError.None: return invalidGenesis() # Bind metadata to its validated owner.
  if info.value.consumed != wire.len or uint32(info.value.unsigned.slot) != uint32(
      clock.value.value):
    return invalidGenesis() # Header and state describe one exact configured genesis slot.
  let retained = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(
    items: ElementLimit(16384), perValue: ByteLimit(4 * 1024 * 1024),
    totalValueBytes: ByteLimit(4 * 1024 * 1024), nodes: TrieNodeLimit(1048576)),
    writes: ElementLimit(0), writeValueBytes: ByteLimit(0)))
  if retained.error != StateStoreError.None: return invalidGenesis() # Includes duplicate decoded keys.
  let saved = snapshot(retained.value)
  if saved.error != StateStoreError.None: return invalidGenesis() # Never publish a default store.
  let hashed = blake2b256(wire)
  if hashed.error != CryptoError.None: return invalidGenesis() # A native hash failure is not a zero identity.
  GenesisResult(status: GenesisError.None, completed: BlockSnapshot(ready: true, state: saved.value,
    pieceLength: capturePieceLength(ValidatorCount(count.value)),
    ticketLimit: captureTicketAttempts(saved.value, CoreCount(cores), EpochSlots(parameters.get(
        epochPeriod))),
    sealedHeader: decoded.value.owner, activePopulation: ValidatorCount(count.value),
    identity: BlockHash(array[32, byte](hashed.value)),
    parentIdentity: BlockHash(array[32, byte](info.value.unsigned.parent)),
    priorCommitment: StateRoot(array[32, byte](info.value.unsigned.priorState)),
    configuration: parameters, epochLength: EpochSlots(parameters.get(
        epochPeriod)), corePopulation: CoreCount(cores), timeslot: uint32(info.value.unsigned.slot),
            keys: captureKeys(entries), services: discoverServices(entries)))

## Preserve the startup genesis loader contract using the general structurally checked snapshot capture.
## Neither entry point verifies execution, signatures, consensus or completeness of the supplied map.
proc captureGenesis*(wire: openArray[byte], entries: openArray[StateEntry],
    parameters: Parameters): GenesisResult =
  captureBlockSnapshot(wire, entries, parameters)
