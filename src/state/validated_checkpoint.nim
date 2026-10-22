# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restore existing complete-map checkpoint bytes under explicit root authority, then validate declared serialization.
## This synchronous adapter preserves format, ownership and precise phase refusals without installing application state.
import ../codec/[bounded, state_trie, state_composition]
import ./[checkpoint, store, global_snapshot, manifest]

type
  StateCheckpointLimits* = object ## Envelope restoration and subsequent global/manifest validation retain independent policies.
    checkpointBytes*: ByteLimit
    store*: StateStoreLimits
    globals*: GlobalStateLimits
    manifest*: StateManifestLimits
  ValidatedCheckpointError* {.pure.} = enum ## Default and failed alternatives cannot expose a restored complete-map owner.
    Uninitialized, None, CheckpointFailure, GlobalFailure, ManifestFailure
  ValidatedCheckpointResult* = object ## Private phase alternatives retain only genuinely failed reason objects.
    case status: ValidatedCheckpointError
    of None:
      completed: ValidatedStateManifest # Only all three completed stages grant a serialization witness.
    of CheckpointFailure:
      checkpointReason: CheckpointError
    of GlobalFailure:
      globalReason: GlobalStateResult[ValidatedGlobalState] # Failed chapter/configuration details carry no owner.
    of ManifestFailure:
      manifestReason: StateManifestResult[ValidatedStateManifest] # Failed exact matching carries no source prefix.
    else:
      discard

func error*(outcome: ValidatedCheckpointResult): ValidatedCheckpointError =
  ## Inspect the active phase without exposing raw discriminators or mutable source storage.
  outcome.status
func value*(outcome: ValidatedCheckpointResult): ValidatedStateManifest {.inline,
    requires: outcome.status == ValidatedCheckpointError.None.} =
  ## Extract only a complete expected-root-bound serialization witness.
  outcome.completed
func checkpointError*(outcome: ValidatedCheckpointResult): CheckpointError {.inline,
    requires: outcome.status == ValidatedCheckpointError.CheckpointFailure.} =
  ## Preserve exact format, resource, backend and independently expected-root refusal.
  outcome.checkpointReason
func globalFailure*(outcome: ValidatedCheckpointResult): GlobalStateResult[
    ValidatedGlobalState] {.inline,

requires: outcome.status == ValidatedCheckpointError.GlobalFailure.} =
  ## Return only the actual failed global result, retaining missing/invalid/resource distinctions.
  outcome.globalReason
func manifestFailure*(outcome: ValidatedCheckpointResult): StateManifestResult[
    ValidatedStateManifest] {.inline,

requires: outcome.status == ValidatedCheckpointError.ManifestFailure.} =
  ## Return only the actual failed manifest result and its guarded nested reason.
  outcome.manifestReason

proc decodeValidatedCheckpoint*(input: openArray[byte], expected: StateRoot,
    services: openArray[StateService], profile: StateProfile,
    limits: StateCheckpointLimits): ValidatedCheckpointResult =
  ## Borrow input bytes/manifest only for this call; no raw restored store escapes before all validation completes.
  let decoded = decodeFullCheckpoint(input, expected, limits.store, limits.checkpointBytes)
  if decoded.error != CheckpointError.None:
    return ValidatedCheckpointResult(status: ValidatedCheckpointError.CheckpointFailure,
      checkpointReason: decoded.error) # Embedded identity alone never supplies caller authority.
  let globals = validateGlobalState(decoded.value.snapshot.value, profile, limits.globals)
  if globals.error != GlobalStateError.None:
    return ValidatedCheckpointResult(status: ValidatedCheckpointError.GlobalFailure,
      globalReason: globals) # A valid checkpoint envelope may still contain absent or malformed global state.
  let matched = validateStateManifest(globals.value, services, limits.manifest)
  if matched.error != StateManifestError.None:
    return ValidatedCheckpointResult(status: ValidatedCheckpointError.ManifestFailure,
      manifestReason: matched) # Declared complete service serialization must match every restored row.
  ValidatedCheckpointResult(status: ValidatedCheckpointError.None, completed: matched.value)
