# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable complete-map block snapshots, including the configured genesis compatibility adapter.
## Exposes GenesisResult, guarded snapshot accessors, read-only lookup, serviceCount/serviceAt
## and captureBlockSnapshot/captureGenesis. Capture accepts raw entries or retains an exact StateStoreSnapshot;
## stateSnapshot returns that immutable version with its inherited policy. The supplied map is trusted as complete;
## structural validation does not
## establish consensus or validate every chapter. Optional C(4) supplies a cached RPC ticket limit;
## C(8) also supplies erasure geometry.

import std/algorithm
import std/assertions
import ./parameters as chain_parameters
import ../codec/header as codec_header
import ../codec/assurances as codec_assurances
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ../codec/state_safrole as codec_state_safrole
import ../codec/state_accounts as codec_state_accounts
import ../codec/state_consensus as codec_state_consensus
import ../state/store as state_store
import ../crypto/primitives as crypto_primitives

type
  ErasurePieceLength* = distinct uint64 ## Original data bytes in one basic erasure-coding piece, derived from active validators.
  SegmentPieceCount* = distinct uint64 ## Number of basic pieces in one fixed 4104-byte segment.
  RpcTicketAttempts* = distinct uint64 ## Advertised ticket-attempt limit; zero explicitly represents an unavailable derivation.
  ServiceListIndex* = distinct int ## An ordinal in the retained service list, distinct from a service ID or state key.
  StateKeyIndex* = distinct int ## Ordinal in the retained sorted serialized-key index, bound to its genesis owner.
  BlockHash* = distinct array[32, byte] ## Block identity is a full sealed-header hash, never a state root.
  BlockSnapshotContext* = object ## Copied fixed context excludes RPC indexes; mutable copies are facts, never a snapshot certificate.
    state*: StateStoreSnapshot
    parameters*: Parameters
    header*: OwnedHeader
    hash*: BlockHash
    slot*: uint32
    validators*: ValidatorCount
  BlockSnapshot* = object ## Private immutable retained state with copied descriptor fields; no mutable store escapes.
    ready: bool
    fuzzSeed: bool                   # Only explicit fuzzer capture may retain unrelated seed header/state clocks.
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
  Genesis* = BlockSnapshot ## Compatibility name for the configured genesis snapshot; storage is shared with block snapshots.
  GenesisError* {.pure.} = enum ## Absent configuration differs from a supplied but invalid genesis pair.
    Unavailable, None, Invalid
  GenesisResult* = object ## Only success contains a usable immutable block snapshot.
    case status: GenesisError
    of None:
      completed: BlockSnapshot
    else:
      discard             # Failed and default alternatives carry no chain data.

type BlockSnapshotResult* = GenesisResult ## Generic name for the same guarded capture result used by startup genesis loading.

func error*(value: GenesisResult): GenesisError =
  ## Read status without exposing the discriminator to mutation.
  value.status
func value*(value: GenesisResult): BlockSnapshot {.requires: value.status ==
    GenesisError.None.} =
  ## Extract only a successful chain snapshot.
  value.completed
func blockSnapshotContext*(outcome: BlockSnapshotResult): BlockSnapshotContext
    {.requires: outcome.status == GenesisError.None.} =
  ## Project fixed facts/immutable handles directly, without copying the snapshot's key/service indexes.
  BlockSnapshotContext(state: outcome.completed.state, parameters: outcome.completed.configuration,
    header: outcome.completed.sealedHeader, hash: outcome.completed.identity,
    slot: outcome.completed.timeslot, validators: outcome.completed.activePopulation)
type BlockSnapshotRetentionInfo* = object ## Copied exact index-array extents exclude shared immutable state/header payloads and fixed wrapper bytes.
  keys*, services*: int
  indexBytes*: uint64
func blockSnapshotRetention*(outcome: BlockSnapshotResult): BlockSnapshotRetentionInfo
    {.requires: outcome.status == GenesisError.None.} =
  ## Project private array lengths without returning/copying the snapshot indexes; capture bounds each count to 16384.
  let keys = outcome.completed.keys.len
  let services = outcome.completed.services.len
  BlockSnapshotRetentionInfo(keys: keys, services: services,
    indexBytes: uint64(keys) * uint64(sizeof(StateKey)) + uint64(services) * uint64(sizeof(ServiceIndex)))

func unavailableGenesis*(): GenesisResult =
  ## Construct an explicit unavailable result for absent snapshot/configuration.
  GenesisResult(status: GenesisError.Unavailable)
func invalidGenesis*(): GenesisResult =
  ## Construct a failed result for malformed explicit configuration.
  GenesisResult(status: GenesisError.Invalid)
func blockHash*(value: BlockSnapshot): BlockHash {.requires: value.ready.} =
  ## Return the copied block identity.
  value.identity
func parentHash*(value: BlockSnapshot): BlockHash {.requires: value.ready.} =
  ## Return the header's claimed parent identity; only a provider lookup establishes parent availability.
  value.parentIdentity
func priorStateRoot*(value: BlockSnapshot): StateRoot {.requires: value.ready.} =
  ## Return the header's prior root, distinct from the captured posterior state commitment.
  value.priorCommitment
func sameParameters*(left, right: BlockSnapshot): bool {.requires: left.ready and right.ready.} =
  ## Compare complete protocol tuples so retained history cannot silently mix startup chain profiles.
  sameParameterProfile(left.configuration, right.configuration)

func chainParameters*(value: BlockSnapshot): Parameters {.requires: value.ready.} =
  ## Copy the exact captured protocol tuple so state/chain adoption cannot substitute a caller profile.
  value.configuration

func stateSnapshot*(value: BlockSnapshot): StateStoreSnapshot {.requires: value.ready.} =
  ## Retain the exact complete-map version for state application without rebuilding or loosening its policy.
  value.state

func header*(value: BlockSnapshot): OwnedHeader {.requires: value.ready.} =
  ## Retain the validated immutable sealed-header owner, independent of the genesis handle lifetime.
  value.sealedHeader
func cores*(value: BlockSnapshot): CoreCount {.requires: value.ready.} =
  ## Return the retained core configuration used to decode this snapshot.
  value.corePopulation
func activeValidators*(value: BlockSnapshot): ValidatorCount {.requires: value.ready.} =
  ## Return the copied active validator population from the exactly decoded C(8) roster.
  value.activePopulation
func basicPieceLength*(value: BlockSnapshot): ErasurePieceLength {.requires: value.ready.} =
  ## Return the cached GP 0.8.0 basic piece length, independent of optional pending-roster state.
  value.pieceLength
func segmentPieces*(value: BlockSnapshot): SegmentPieceCount {.requires: value.ready.} =
  ## Return the exact number of basic pieces in a segment; capture proves positive divisibility.
  SegmentPieceCount(4104 div uint64(value.pieceLength))
func ticketAttempts*(value: BlockSnapshot): RpcTicketAttempts {.requires: value.ready.} =
  ## Return the cached RPC ticket limit, or its documented zero when C(4) cannot be derived.
  value.ticketLimit
func epochSlots*(value: BlockSnapshot): EpochSlots {.requires: value.ready.} =
  ## Return the captured epoch-ring length used to decode retained ready state.
  value.epochLength
func slot*(value: BlockSnapshot): uint32 {.requires: value.ready.} =
  ## Return the copied genesis timeslot.
  value.timeslot
func serviceCount*(value: BlockSnapshot): int {.requires: value.ready.} =
  ## Return the bounded number of structurally valid service accounts discovered at capture.
  value.services.len
func serviceAt*(value: BlockSnapshot, index: ServiceListIndex): ServiceIndex {.requires: value.ready and
    int(index) >= 0 and int(index) < value.services.len.} =
  ## Return a copied ID by owner-bound ordinal; no mutable sequence or detached view escapes.
  value.services[int(index)]

func keyCount*(value: BlockSnapshot): int {.requires: value.ready.} =
  ## Return the number of exact serialized keys retained with this snapshot.
  value.keys.len
func keyAt*(value: BlockSnapshot, index: StateKeyIndex): StateKey {.requires: value.ready and
    int(index) >= 0 and int(index) < value.keys.len.} =
  ## Copy one key without exporting mutable index storage.
  value.keys[int(index)]

## Compare full serialized keys by unsigned octet order, independent of Base64 spelling.
func compareStateKey(left, right: StateKey): int =
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    # The first differing octet determines dictionary order.
    if a[index] < b[index]: return -1 # Smaller octets precede larger ones.
    if a[index] > b[index]: return 1 # Distinct keys never compare equal.
  0

proc keyAfter*(value: BlockSnapshot, key: StateKey): StateKeyIndex {.requires: value.ready.} =
  ## Locate the first strictly greater key; keyCount is the valid end sentinel.
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

## Copy the store's already sorted fixed keys without copying values or sorting a second time.
proc captureKeys(state: StateStoreSnapshot): seq[StateKey] =
  result = newSeq[StateKey](state.commitment.entries)
  for index in 0..<result.len:
    result[index] = state.keyAt(StateEntryIndex(index)).value # Commitment and owner establish the exact extent.

## Sort numeric IDs rather than the little-endian interleaved serialized account keys.
proc compareService(left, right: ServiceIndex): int =
  if uint32(left) < uint32(right): return -1 # Smaller numeric IDs precede larger IDs.
  if uint32(left) > uint32(right): return 1 # Preserve the complete unsigned domain.
  0

## Discover only exact C(255, service) keys with complete supported metadata in a validated bounded map.
## Borrow input solely during capture; the returned scalar sequence owns no caller aliases.
proc discoverServices(state: StateStoreSnapshot): seq[ServiceIndex] =
  result = @[]
  for index in 0..<state.commitment.entries:
    let entryKey = state.keyAt(StateEntryIndex(index)).value
    # Hash-derived storage keys cannot be classified as accounts from one prefix byte alone.
    let key = array[31, byte](entryKey)
    if key[0] != 255: continue # Only account-prefixed keys can contribute a service ID.
    var service = 0'u32
    for i in 0..<4: # C(255, service) interleaves four little-endian ID octets at odd offsets.
      service = service or (uint32(key[1 + i * 2]) shl (8 * i))
    if key != array[31, byte](chapterServiceKey(StateChapter(255), ServiceIndex(service))):
      continue # Every fixed zero octet must match the maintained key constructor too.
    let found = state.lookup(entryKey).value
    if found.byteLength != ServiceMetadataBytes: continue # Bound metadata before copying any bytes.
    let metadata = decodeServiceMetadata(found.bytes, ByteLimit(ServiceMetadataBytes))
    if metadata.error != ServiceMetadataError.None:
      continue # Best-effort discovery excludes malformed or unsupported records.
    result.add(ServiceIndex(service))
  result.sort(compareService) # The validated map already rejects duplicate keys and therefore IDs.

proc stateRoot*(value: BlockSnapshot): StateRoot {.requires: value.ready.} =
  ## Read the computed posterior root of the supplied genesis map, not the header's prior-state field.
  value.state.commitment.root

proc lookup*(value: BlockSnapshot, key: StateKey): StateStoreResult[StateValue] =
  ## Read a serialized key from this retained snapshot; the view owns its lifetime, and default owners fail.
  state_store.lookup(value.state, key)

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

proc captureSnapshot(wire: openArray[byte], state: StateStoreSnapshot,
    parameters: Parameters, fuzzSeed: bool): BlockSnapshotResult =
  ## Capture a structurally checked header and supplied posterior map, using its active roster and time.
  ## Retain the exact immutable map without Merklization; borrowed header bytes become an owned codec value.
  ## This checks framing and local bounds, not signatures, execution, completeness or finality.
  let cores = parameters.get(coreCount)
  if cores > 341 or wire.len == 0 or wire.len > 256 * 1024:
    return invalidGenesis() # Bound profile, header and map before owned construction.
  if forkStateStore(state).error != StateStoreError.None:
    return invalidGenesis() # A default owner cannot stand for a complete empty map.
  if state.commitment.entries > 16384 or state.commitment.nodes > 1048576:
    return invalidGenesis() # Retained stores may have a larger policy than chain capture permits.
  var remaining = 4 * 1024 * 1024
  for index in 0..<state.commitment.entries:
    let key = state.keyAt(StateEntryIndex(index)).value
    let size = state.lookup(key).value.byteLength
    if size > remaining:
      return invalidGenesis() # Subtraction bounds both each value and the aggregate before any copy.
    remaining -= size
  var roster: seq[byte] = @[]
  var time: seq[byte] = @[]
  # Required context is obtained from actual serialized state, never inferred from core count.
  let active = state.lookup(chapterKey(StateChapter(8)))
  if active.error != StateStoreError.None or active.value.byteLength > 1024 * 1024:
    return invalidGenesis() # Missing or oversized required rosters never reach a copy.
  roster = active.value.bytes
  let clockBytes = state.lookup(chapterKey(StateChapter(11)))
  if clockBytes.error != StateStoreError.None or clockBytes.value.byteLength != 4:
    return invalidGenesis() # Required time is exactly one E4 slot.
  time = clockBytes.value.bytes
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
  if info.value.consumed != wire.len or (not fuzzSeed and uint32(info.value.unsigned.slot) !=
      uint32(clock.value.value)):
    return invalidGenesis() # Header and state describe one exact configured genesis slot.
  let hashed = blake2b256(wire)
  if hashed.error != CryptoError.None: return invalidGenesis() # A native hash failure is not a zero identity.
  GenesisResult(status: GenesisError.None, completed: BlockSnapshot(ready: true, fuzzSeed: fuzzSeed,
    state: state,
    pieceLength: capturePieceLength(ValidatorCount(count.value)),
    ticketLimit: captureTicketAttempts(state, CoreCount(cores), EpochSlots(parameters.get(
        epochPeriod))),
    sealedHeader: decoded.value.owner, activePopulation: ValidatorCount(count.value),
    identity: BlockHash(array[32, byte](hashed.value)),
    parentIdentity: BlockHash(array[32, byte](info.value.unsigned.parent)),
    priorCommitment: StateRoot(array[32, byte](info.value.unsigned.priorState)),
    configuration: parameters, epochLength: EpochSlots(parameters.get(
        epochPeriod)), corePopulation: CoreCount(cores), timeslot: uint32(info.value.unsigned.slot),
            keys: captureKeys(state), services: discoverServices(state)))

func fuzzSeedOnly*(value: BlockSnapshot): bool =
  ## A marked seed can initialize only a fuzz-domain view, never an ordinary genesis view.
  value.ready and value.fuzzSeed
proc captureBlockSnapshot*(wire: openArray[byte], state: StateStoreSnapshot,
    parameters: Parameters): BlockSnapshotResult =
  ## Ordinary snapshots require exact equality between header slot and posterior state clock.
  captureSnapshot(wire, state, parameters, false)
proc captureFuzzSeedSnapshot*(wire: openArray[byte], state: StateStoreSnapshot,
    parameters: Parameters): BlockSnapshotResult =
  ## Preserve the explicit fuzz-v1 genesis-like pair exactly, retaining all structural bounds and a permanent seed marker.
  captureSnapshot(wire, state, parameters, true)

func genesisStoreLimits*(): StateStoreLimits =
  ## Preserve the legacy read-only complete-map capture policy; callers must explicitly choose any write budget.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(16384),
    perValue: ByteLimit(4 * 1024 * 1024), totalValueBytes: ByteLimit(4 * 1024 * 1024),
    nodes: TrieNodeLimit(1048576)), writes: ElementLimit(0), writeValueBytes: ByteLimit(0))

proc captureBlockSnapshot*(wire: openArray[byte], entries: openArray[StateEntry],
    parameters: Parameters, limits = genesisStoreLimits()): BlockSnapshotResult =
  ## Copy/commit a borrowed complete map once under an explicit policy, then share exact-owner structural capture.
  ## Omitting limits preserves legacy readonly capture; explicit write budgets are retained unchanged.
  if parameters.get(coreCount) > 341 or wire.len == 0 or wire.len > 256 * 1024 or entries.len > 16384:
    return invalidGenesis() # Bound input before Merklization and retained allocation.
  let ceiling = genesisStoreLimits()
  if uint64(limits.trie.items) > uint64(ceiling.trie.items) or
      uint64(limits.trie.perValue) > uint64(ceiling.trie.perValue) or
      uint64(limits.trie.totalValueBytes) > uint64(ceiling.trie.totalValueBytes) or
      uint64(limits.trie.nodes) > uint64(ceiling.trie.nodes):
    return invalidGenesis() # Explicit startup policies must fit fixed chain bounds; never silently clamp or widen them.
  let retained = newStateStore(entries, limits)
  if retained.error != StateStoreError.None:
    return invalidGenesis() # Includes duplicate keys, local limits and primitive refusal.
  captureBlockSnapshot(wire, retained.value.snapshot.value, parameters)

proc captureGenesis*(wire: openArray[byte], entries: openArray[StateEntry],
    parameters: Parameters, limits = genesisStoreLimits()): GenesisResult =
  ## Preserve the startup genesis loader contract using the general structurally checked snapshot capture.
  ## Neither entry point verifies execution, signatures, consensus or completeness of the supplied map.
  captureBlockSnapshot(wire, entries, parameters, limits)
