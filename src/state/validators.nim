## GP 0.8.0 safrole.tex key rotation and blacklistfilter; this module plans rosters without publishing state.
## Posterior offenders come from the completed disputes stage; ring-root computation is a subsequent step.
import ../codec/[state_safrole, assurances, bounded]
from ../codec/disputes import OffenderKey
from ../codec/header import EpochSlots

type
  ## Explicit per-roster population/byte policy and independent offender work ceiling.
  ValidatorRotationConfig* = object
    roster*: ValidatorStateConfig
    offenders*: ElementLimit
  ## Complete posterior roster handles share only immutable codec-owned storage.
  ValidatorRotation* = object
    pending*, active*, previous*: ValidatorStateSnapshot
    epochChanged*: bool
  ## Invalid/default results expose no posterior roster handles or partial work.
  ValidatorRotationError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidSlot, InvalidState, NonCanonical, LimitExceeded, LengthOverflow
  ## Only success contains a complete plan; discriminator and payload remain private.
  ValidatorRotationResult* = object
    case status: ValidatorRotationError
    of None:
      completed: ValidatorRotation # Callers select success before accessing any handles.
    else:
      discard                      # Failed alternatives carry only their reason.

## Inspect a reason without publishing roster handles or allowing result mutation.
func error*(outcome: ValidatorRotationResult): ValidatorRotationError = outcome.status
## Require successful selection before returning the complete immutable roster-handle group.
func value*(outcome: ValidatorRotationResult): ValidatorRotation {.inline,
    requires: outcome.status == ValidatorRotationError.None.} = outcome.completed

## Convert existing codec failures without treating bad owners or policy refusals as empty validator sets.
func codecError(reason: StateComponentError): ValidatorRotationError =
  case reason
  of StateComponentError.None: ValidatorRotationError.None # Complete existing codec success.
  of StateComponentError.InvalidConfig: ValidatorRotationError.InvalidConfig # Caller chooses a valid profile.
  of StateComponentError.LimitExceeded: ValidatorRotationError.LimitExceeded # Preserve explicit resource policy.
  of StateComponentError.LengthOverflow: ValidatorRotationError.LengthOverflow # No unsafe native extent conversion.
  else: ValidatorRotationError.InvalidState # Bad populations, handles or framing cannot be state.

## Compare fixed identity octets lexicographically; no curve validation or account semantics are implied.
func compare(a, b: array[32, byte]): int =
  for i in 0..<32:
    if a[i] < b[i]: return -1 # First smaller octet sorts before the other identity.
    if a[i] > b[i]: return 1 # First larger octet sorts after the other identity.
  0 # Full equality denotes exactly one offender identity.

## Binary-search the caller's already canonical posterior offender set, without retaining borrowed bytes.
proc excluded(key: StateEdKey, offenders: openArray[OffenderKey]): bool =
  var first = 0
  var last = offenders.len
  while first < last:
    let middle = first+(last-first) div 2 # Bound arithmetic without adding two arbitrary indices.
    let order = compare(array[32, byte](key), array[32, byte](offenders[middle]))
    if order == 0:
      return true # Membership depends only on the Ed25519 field, never another key or metadata.
    if order < 0:
      last = middle # Search the strictly smaller half of the canonical set.
    else:
      first = middle+1 # Search the strictly larger half; middle is still below last.
  false

## Rotate once on epoch crossing; replace every offending staging record with all-zero fields in place.
## No crossing retains the prior pending/active/previous unchanged, even when staging/offenders differ.
## The result is a plan only: the epoch ring root and C(4)/C(8)/C(9) must be coordinated before publication.
proc planValidatorRotation*(staging, pending, active, previous: ValidatorStateSnapshot,
    priorSlot, targetSlot: StateTime, epochSlots: EpochSlots,
    offenders: openArray[OffenderKey], config: ValidatorRotationConfig): ValidatorRotationResult =
  if uint64(epochSlots) == 0 or uint64(config.roster.cores) < 2:
    return ValidatorRotationResult(status: ValidatorRotationError.InvalidConfig) # No zero division or guessed profile.
  if uint32(targetSlot) <= uint32(priorSlot):
    return ValidatorRotationResult(status: ValidatorRotationError.InvalidSlot) # No repeats, regressions or wraparound.
  if uint64(offenders.len) > uint64(config.offenders):
    return ValidatorRotationResult(status: ValidatorRotationError.LimitExceeded) # Bound traversal before examining keys.
  for i in 1..<offenders.len:
    if compare(array[32, byte](offenders[i-1]), array[32, byte](offenders[i])) >= 0:
      return ValidatorRotationResult(status: ValidatorRotationError.NonCanonical) # No sorting/deduplication fallback.
  # All four immutable input rosters must satisfy the explicit current policy before allocating output.
  for owner in [staging, pending, active, previous]:
    let count = validatorCount(owner)
    if count.error != StateComponentError.None:
      return ValidatorRotationResult(status: ValidatorRotationError.InvalidState) # Defaults are not zero validators.
    let checked = stateValidatorSize(ValidatorCount(uint64(count.value)), config.roster)
    if checked.error != StateComponentError.None:
      return ValidatorRotationResult(status: codecError(
          checked.error)) # Population, bytes and native extent are bounded.
  let changed = uint64(uint32(targetSlot)) div uint64(epochSlots) >
      uint64(uint32(priorSlot)) div uint64(epochSlots)
  if not changed:
    return ValidatorRotationResult(status: ValidatorRotationError.None,
        completed: ValidatorRotation(pending: pending, active: active, previous: previous,
            epochChanged: false)) # No re-filtering or roster movement inside an epoch.
  let count = validatorCount(staging).value
  var records = newSeq[StateValidator](count)
  for i in 0..<count:
    let record = validatorAt(staging, StateValidatorIndex(uint64(i))).value
    if excluded(record.ed25519, offenders):
      records[i] = default(StateValidator) # All 336 bytes become zero; cardinality and ordinal remain intact.
    else:
      records[i] = record # Copy Bandersnatch, Ed25519, BLS and metadata fields exactly.
  # Reuse the roster codec to capture a new immutable pending owner; C(7) here is temporary framing only.
  let encoded = validatorEntry(ValidatorChapter.Staging, records, config.roster)
  if encoded.error != StateComponentError.None:
    return ValidatorRotationResult(status: codecError(encoded.error)) # No partial posterior handles.
  let captured = decodeStateValidators(encoded.value.value, config.roster)
  if captured.error != StateComponentError.None:
    return ValidatorRotationResult(status: codecError(captured.error)) # A failed capture cannot become a plan.
  ValidatorRotationResult(status: ValidatorRotationError.None,
      completed: ValidatorRotation(pending: captured.value.value, active: pending,
          previous: active, epochChanged: true)) # A multi-epoch skip rotates once from the original inputs.
