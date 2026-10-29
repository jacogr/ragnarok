# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Read-only Safrole authentication context before publishing the new entropy/time accumulator.
##
## Exposes authenticateSafroleHeaderState to authenticate a header using retained parent and
## staged state snapshots.

import ../codec/state/[safrole as state_safrole, consensus as state_consensus,
    layout as state_layout]
import ../codec/header
import ./safrole/authentication as safrole_authentication
import ./store

## Retain initialized/missing/resource distinctions when selecting immutable required state views.
func stateError(reason: StateStoreError): SafroleAuthError =
  case reason
  of StateStoreError.Uninitialized: SafroleAuthError.Uninitialized # Default snapshots cannot provide an authenticated context.
  of StateStoreError.MissingKey: SafroleAuthError.MissingState # No implicit genesis entropy, slot or active keys.
  of StateStoreError.LimitExceeded: SafroleAuthError.LimitExceeded # Keep caller resource refusal explicit.
  of StateStoreError.LengthOverflow: SafroleAuthError.LengthOverflow # Preserve checked native extent refusal.
  else: SafroleAuthError.InvalidState # Lookup does no backend work and cannot legitimately report other successful state.

proc authenticateSafroleHeaderState*(parent, staged: StateStoreSnapshot, candidate: OwnedHeader,
    config: SafroleAuthConfig): SafroleAuthResult =
  ## Authenticate against parent C(6)/C(11), and already selected posterior C(4)/C(8), without modifying either map.
  ## Staged C(6)/C(11) are intentionally not read: authentication yields entropy needed to advance them.
  ## Earlier rotation/schedule lineage and marker/commitment/clock checks remain caller responsibilities.
  let entropy = parent.lookup(chapterKey(StateChapter(6)))
  if entropy.error != StateStoreError.None:
    return safroleAuthFailure(stateError(entropy.error)) # Parent history is required before any dynamic copy or verification.
  let time = parent.lookup(chapterKey(StateChapter(11)))
  if time.error != StateStoreError.None:
    return safroleAuthFailure(stateError(time.error)) # Missing parent time is not slot zero.
  let schedule = staged.lookup(chapterKey(StateChapter(4)))
  if schedule.error != StateStoreError.None:
    return safroleAuthFailure(stateError(schedule.error)) # Sealing uses the posterior selected schedule.
  let active = staged.lookup(chapterKey(StateChapter(8)))
  if active.error != StateStoreError.None:
    return safroleAuthFailure(stateError(active.error)) # The header index selects actual posterior active records.
  if entropy.value.byteLength != 128 or time.value.byteLength != 4:
    return safroleAuthFailure(SafroleAuthError.InvalidState) # Bound fixed copies and reject suffixes/truncations.
  let oversizedSchedule = uint64(schedule.value.byteLength) > uint64(config.state.maxBytes)
  let oversizedActive = uint64(active.value.byteLength) > uint64(config.state.validators.maxBytes)
  if oversizedSchedule or oversizedActive:
    return safroleAuthFailure(SafroleAuthError.LimitExceeded) # Check both dynamic byte ceilings before copying either chapter.
  let decodedEntropy = decodeStateEntropy(entropy.value.bytes)
  let decodedTime = decodeStateTime(time.value.bytes)
  if decodedEntropy.error != StateComponentError.None or decodedTime.error !=
      StateComponentError.None:
    return safroleAuthFailure(SafroleAuthError.InvalidState) # Select fixed-codec success before extracting any values.
  authenticateSafroleSeal(candidate, schedule.value.bytes, active.value.bytes,
    decodedTime.value.value, decodedEntropy.value.value, config)
