# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Match a complete serialized map to validated globals and explicit service serialization inputs.
## Exact byte coverage is distinct from valid-state consistency, STF execution and root trust.
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ../codec/state_composition as codec_state_composition
import ./global_snapshot as state_global_snapshot
import ./store as state_store

type
  StateManifestLimits* = object ## Caller service traversal, full composition and raw-key hashing have independent ceilings.
    services*: ElementLimit
    serialized*: StateTrieLimits
    storageKeyBytes*: ByteLimit
  StateManifestInfo* = object ## Fixed copied observations report the complete matched mapping, never mutable source bytes.
    services*, entries*: int
    valueBytes*: uint64
  StateManifestError* {.pure.} = enum ## Refusals carry no validated manifest, partial map or replacement source.
    Uninitialized, None, InvalidSource, LimitExceeded, OpaqueValues, CompositionFailure, MappingMismatch
  StateManifestData = ref object # Retain the genuine source certificate after temporary composition retires.
    globals: ValidatedGlobalState
    info: StateManifestInfo
  ValidatedStateManifest* = object ## Only complete exact-map matching constructs a full serialization witness.
    data: nil StateManifestData
  StateManifestResult*[T] = object  ## Private alternatives preserve guarded success and nested reason extraction.
    case status: StateManifestError
    of None:
      completed: T                  # No prefix of matched service rows escapes.
    of CompositionFailure:
      reason: StateCompositionError # Preserve actual codec, key, policy and backend refusals.
    else:
      discard

func error*[T](outcome: StateManifestResult[T]): StateManifestError =
  ## Inspect the result tag without exposing retagging or inactive fields.
  outcome.status
func value*[T](outcome: StateManifestResult[T]): T {.inline,
    requires: outcome.status == StateManifestError.None.} =
  ## Return a complete owner or fixed observation only after successful selection.
  outcome.completed
func compositionError*[T](outcome: StateManifestResult[T]): StateCompositionError {.inline,
    requires: outcome.status == StateManifestError.CompositionFailure.} =
  ## Read only the actual failed composition reason.
  outcome.reason

proc validateStateManifest*(globals: ValidatedGlobalState, services: openArray[StateService],
    limits: StateManifestLimits): StateManifestResult[ValidatedStateManifest] =
  ## Borrow service descriptors synchronously; retain no caller arrays or temporary recomposed map.
  let retained = globals.globalSource
  if retained.error != GlobalStateError.None:
    return StateManifestResult[ValidatedStateManifest](
        status: StateManifestError.InvalidSource) # A default or partial owner cannot provide complete provenance.
  if uint64(services.len) > uint64(limits.services):
    return StateManifestResult[ValidatedStateManifest](
        status: StateManifestError.LimitExceeded) # Bound every service descriptor inspection before traversing nested inputs.
  for service in services:
    if service.captured.len != 0:
      return StateManifestResult[ValidatedStateManifest](
          status: StateManifestError.OpaqueValues) # Opaque hashed keys cannot certify an explicit logical service manifest.
  let source = retained.value
  let commitment = source.commitment
  if uint64(commitment.entries) > uint64(limits.serialized.items) or
      commitment.nodes > uint64(limits.serialized.nodes):
    return StateManifestResult[ValidatedStateManifest](
        status: StateManifestError.LimitExceeded) # Cached complete-map extents refuse before copies or key/root hashing.
  var bytes = 0'u64
  for index in 0..<commitment.entries:
    let key = source.keyAt(state_store.StateEntryIndex(index)).value
    let size = uint64(source.lookup(key).value.byteLength)
    if size > uint64(limits.serialized.perValue) or size > uint64(
        limits.serialized.totalValueBytes)-bytes:
      return StateManifestResult[ValidatedStateManifest](
          status: StateManifestError.LimitExceeded) # Prove aggregate addition and source copy policy before composition.
    bytes += size
  let composed = composeState(globals.globalChapters.value, services, limits.serialized,
    limits.storageKeyBytes)
  if composed.error != StateCompositionError.None:
    return StateManifestResult[ValidatedStateManifest](
      status: StateManifestError.CompositionFailure,
      reason: composed.error) # Existing codecs refuse atomically; no alternate service representation is tried.
  let expected = composed.value
  if expected.stateCommitment.value.entries != commitment.entries:
    return StateManifestResult[ValidatedStateManifest](
        status: StateManifestError.MappingMismatch) # Equal cardinality plus every unique expected key is required for complete coverage.
  for index in 0..<commitment.entries:
    let entry = expected.stateEntryAt(codec_state_composition.StateEntryIndex(uint64(index))).value
    let found = source.lookup(entry.key)
    if found.error != StateStoreError.None:
      return StateManifestResult[ValidatedStateManifest](
          status: StateManifestError.MappingMismatch) # A different hashed identity cannot substitute a declared service row.
    if found.value.byteLength != entry.value.len or found.value.bytes != entry.value:
      return StateManifestResult[ValidatedStateManifest](
          status: StateManifestError.MappingMismatch) # Compare actual complete bytes, not only roots or caller metadata counts.
  StateManifestResult[ValidatedStateManifest](status: StateManifestError.None,
    completed: ValidatedStateManifest(data: StateManifestData(globals: globals,
      info: StateManifestInfo(services: services.len, entries: commitment.entries,
        valueBytes: bytes))))

proc manifestSource*(manifest: ValidatedStateManifest): StateManifestResult[StateStoreSnapshot] =
  ## Return the original exact complete-map identity, without reconstruction or trusted-root selection.
  let data = manifest.data
  if data == nil:
    return StateManifestResult[StateStoreSnapshot](
        status: StateManifestError.Uninitialized) # No source exists for a default witness.
  StateManifestResult[StateStoreSnapshot](status: StateManifestError.None,
    completed: data.globals.globalSource.value)
proc manifestGlobals*(manifest: ValidatedStateManifest): StateManifestResult[ValidatedGlobalState] =
  ## Retain immutable typed globals without exposing private chapter storage.
  let data = manifest.data
  if data == nil:
    return StateManifestResult[ValidatedGlobalState](
        status: StateManifestError.Uninitialized) # Defaults cannot manufacture global validation.
  StateManifestResult[ValidatedGlobalState](status: StateManifestError.None,
    completed: data.globals)
proc manifestInfo*(manifest: ValidatedStateManifest): StateManifestResult[StateManifestInfo] =
  ## Copy validated service/count/byte observations, not caller-authored completeness claims.
  let data = manifest.data
  if data == nil:
    return StateManifestResult[StateManifestInfo](
        status: StateManifestError.Uninitialized) # No initialized observations exist.
  StateManifestResult[StateManifestInfo](status: StateManifestError.None,
    completed: data.info)
