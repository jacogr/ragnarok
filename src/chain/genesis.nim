# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable configured genesis view, rooted with the existing complete-map store.
## Exposes GenesisResult, guarded snapshot accessors, read-only lookup and captureGenesis. The configured map is
## trusted as complete; structural validation does not establish consensus or validate every chapter.

import ./parameters
import ../codec/[header, assurances, bounded, state_layout, state_trie, state_safrole]
import ../state/store
import ../crypto/primitives

type
  ## Genesis identity is a full sealed-header hash, never a state root.
  BlockHash* = distinct array[32, byte]
  ## Private immutable retained state with copied descriptor fields; no mutable store escapes.
  Genesis* = object
    ready: bool
    state: StateStoreSnapshot
    identity: BlockHash
    timeslot: uint32
  ## Absent configuration differs from a supplied but invalid genesis pair.
  GenesisError* {.pure.} = enum
    Unavailable, None, Invalid
  ## Only success contains a usable immutable genesis view.
  GenesisResult* = object
    case status: GenesisError
    of None:
      completed: Genesis
    else:
      discard # Failed and default alternatives carry no chain data.

## Read status without exposing the discriminator to mutation.
func error*(value: GenesisResult): GenesisError = value.status
## Extract only a successful chain snapshot.
func value*(value: GenesisResult): Genesis {.requires: value.status ==
    GenesisError.None.} = value.completed
## Construct an explicit unavailable result for optional server configuration.
func unavailableGenesis*(): GenesisResult = GenesisResult(status: GenesisError.Unavailable)
## Construct a failed result for malformed explicit configuration.
func invalidGenesis*(): GenesisResult = GenesisResult(status: GenesisError.Invalid)
## Return the copied block identity.
func blockHash*(value: Genesis): BlockHash {.requires: value.ready.} = value.identity
## Return the copied genesis timeslot.
func slot*(value: Genesis): uint32 {.requires: value.ready.} = value.timeslot
## Read the computed posterior root of the supplied genesis map, not the header's prior-state field.
proc stateRoot*(value: Genesis): StateRoot {.requires: value.ready.} = value.state.commitment.root

## Read a serialized key from this retained snapshot; the view owns its lifetime, and default owners fail.
proc lookup*(value: Genesis, key: StateKey): StateStoreResult[StateValue] =
  store.lookup(value.state, key)

## Validate header framing against the supplied active roster and time, then own the complete map.
## Input bytes are borrowed only during this call; no signature or whole-state validation is claimed.
proc captureGenesis*(wire: openArray[byte], entries: openArray[StateEntry],
    parameters: Parameters): GenesisResult =
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
  GenesisResult(status: GenesisError.None, completed: Genesis(ready: true, state: saved.value,
    identity: BlockHash(array[32, byte](hashed.value)), timeslot: uint32(info.value.unsigned.slot)))
