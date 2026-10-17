## Publish a selected Safrole schedule atomically in the full-state working map.
## Retain the parent snapshot before rotation/admission; staged chapters supply posterior inputs.
import ../codec/[state_safrole, state_consensus, state_layout, state_trie, tickets]
import ./[sealer_schedule, store]

type
  ## Success alone owns a complete immutable published map; defaults/refusals expose no payload.
  SealerStateResult* = object
    case status: SealerScheduleError
    of None:
      completed: StateStoreSnapshot # Acyclic shared history remains immutable after later writes.
    else:
      discard                       # No partial schedule or root escapes a failed publication.

## Read the publication reason without permitting result retagging.
func error*(outcome: SealerStateResult): SealerScheduleError = outcome.status
## Extract the immutable map only after selecting successful publication.
func value*(outcome: SealerStateResult): StateStoreSnapshot {.inline,
    requires: outcome.status == SealerScheduleError.None.} = outcome.completed

## Preserve store resource/backend reasons and distinguish absent chapters from default handles.
func storeError(reason: StateStoreError): SealerScheduleError =
  case reason
  of StateStoreError.Uninitialized: SealerScheduleError.Uninitialized # Default snapshots cannot supply a parent.
  of StateStoreError.MissingKey: SealerScheduleError.MissingState # Missing chapters are never synthesized.
  of StateStoreError.LimitExceeded: SealerScheduleError.LimitExceeded # Caller map/batch ceilings remain explicit.
  of StateStoreError.LengthOverflow: SealerScheduleError.LengthOverflow # Preserve checked native extent refusal.
  of StateStoreError.BackendFailure: SealerScheduleError.BackendFailure # Refused commitment hashes publish nothing.
  else: SealerScheduleError.InvalidState # Other failures cannot describe the fixed one-entry batch.

## Re-encode a candidate already validated under this exact policy, copying only bounded owned fields.
proc candidateEntry(owner: SafroleStateSnapshot, policy: SafroleStateConfig): SafroleStateResult[StateEntry] =
  let info = safroleInfo(owner).value
  var source = SafroleState(pending: newSeq[StateValidator](info.validators), root: info.root,
    schedule: ticketSchedule(@[]), accumulator: newSeq[WinningTicket](info.accumulated))
  for i in 0..<source.pending.len:
    source.pending[i] = pendingValidatorAt(owner, StateValidatorIndex(uint64(
        i))).value # Fixed owner-bound copies.
  for i in 0..<source.accumulator.len:
    source.accumulator[i] = accumulatedTicketAt(owner, SafroleStateIndex(uint64(
        i))).value # Preserve the admitted order/attempts.
  case info.kind
  of SealerKind.Tickets:
    var values = newSeq[WinningTicket](info.slots) # Preserve existing ticket schedule independently of new accumulator.
    for i in 0..<values.len:
      values[i] = sealerTicketAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = ticketSchedule(values)
  of SealerKind.Keys:
    var values = newSeq[StateBsKey](info.slots) # Preserve fallback slot order and duplicates.
    for i in 0..<values.len:
      values[i] = sealerKeyAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = keySchedule(values)
  safroleStateEntry(source, policy)

## Read parent C(4)/C(11) and staged C(4)/C(6)/C(8)/C(11) from immutable snapshots.
## Caller stages rotation, entropy/time and admission first; this does not authenticate their lineage.
## Refusal preserves the working map at entry, not the entire earlier multi-stage transition.
proc selectSafroleScheduleState*(state: var StateStore, parent: StateStoreSnapshot,
    target: StateTime, config: SealerScheduleConfig): SealerStateResult =
  let oldTime = parent.lookup(chapterKey(StateChapter(11)))
  if oldTime.error != StateStoreError.None:
    return SealerStateResult(status: storeError(oldTime.error)) # No default/missing parent slot.
  let oldChapter = parent.lookup(chapterKey(StateChapter(4)))
  if oldChapter.error != StateStoreError.None:
    return SealerStateResult(status: storeError(oldChapter.error)) # Retain the actual parent contest before admission reset.
  let before = state.snapshot
  if before.error != StateStoreError.None:
    return SealerStateResult(status: storeError(before.error)) # Default working maps cannot publish.
  let time = before.value.lookup(chapterKey(StateChapter(11)))
  if time.error != StateStoreError.None:
    return SealerStateResult(status: storeError(time.error)) # Time advancement must already have completed.
  let entropy = before.value.lookup(chapterKey(StateChapter(6)))
  if entropy.error != StateStoreError.None:
    return SealerStateResult(status: storeError(entropy.error)) # Fallback uses the supplied posterior entropy history.
  let active = before.value.lookup(chapterKey(StateChapter(8)))
  if active.error != StateStoreError.None:
    return SealerStateResult(status: storeError(active.error)) # Never substitute pending or parent keys.
  let chapter = before.value.lookup(chapterKey(StateChapter(4)))
  if chapter.error != StateStoreError.None:
    return SealerStateResult(status: storeError(chapter.error)) # Admission must leave a complete serialized C(4).
  if oldTime.value.byteLength != 4 or time.value.byteLength != 4 or entropy.value.byteLength != 128:
    return SealerStateResult(status: SealerScheduleError.InvalidState) # Bound fixed copies and reject truncation/suffixes.
  let oversizedParent = uint64(oldChapter.value.byteLength) > uint64(config.state.maxBytes)
  let oversizedStaged = uint64(chapter.value.byteLength) > uint64(config.state.maxBytes)
  let oversizedActive = uint64(active.value.byteLength) > uint64(config.state.validators.maxBytes)
  if oversizedParent or oversizedStaged or oversizedActive:
    return SealerStateResult(status: SealerScheduleError.LimitExceeded) # Check every dynamic ceiling before copying any dynamic input.
  let decodedPrevious = decodeStateTime(oldTime.value.bytes)
  let decodedTime = decodeStateTime(time.value.bytes)
  let decodedEntropy = decodeStateEntropy(entropy.value.bytes)
  let invalidTime = decodedPrevious.error != StateComponentError.None or decodedTime.error !=
      StateComponentError.None
  if invalidTime or decodedEntropy.error != StateComponentError.None:
    return SealerStateResult(status: SealerScheduleError.InvalidState) # Select codec success before extracting any fixed payload.
  let previous = decodedPrevious.value.value
  let stagedTime = decodedTime.value.value
  let stagedEntropy = decodedEntropy.value.value
  if uint32(stagedTime) != uint32(target):
    return SealerStateResult(status: SealerScheduleError.InvalidState) # Refuse absent/out-of-order entropy-time staging.
  let original = chapter.value.bytes
  let selected = selectSafroleSchedule(oldChapter.value.bytes, original, active.value.bytes,
    previous, target, stagedEntropy[2], config)
  if selected.error != SealerScheduleError.None:
    return SealerStateResult(status: selected.error) # No invalid/partial schedule reaches the store.
  let next = candidateEntry(selected.value, config.state)
  if next.error != StateComponentError.None:
    if next.error == StateComponentError.LimitExceeded:
      return SealerStateResult(status: SealerScheduleError.LimitExceeded) # Preserve posterior chapter policy.
    elif next.error == StateComponentError.LengthOverflow:
      return SealerStateResult(status: SealerScheduleError.LengthOverflow) # Preserve native extent refusal.
    else:
      return SealerStateResult(status: SealerScheduleError.InvalidState) # Failed encodings have no payload.
  if next.value.value == original:
    return SealerStateResult(status: SealerScheduleError.None,
      completed: before.value) # Validated no-op consumes no write budget or commitment hashes.
  let published = state.apply(@[StateWrite(key: next.value.key, kind: StateWriteKind.Put,
    value: next.value.value)])
  if published.error != StateStoreError.None:
    return SealerStateResult(status: storeError(published.error)) # Store hashes privately before its sole publication point.
  SealerStateResult(status: SealerScheduleError.None, completed: published.value)
