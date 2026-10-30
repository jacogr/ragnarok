# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 Safrole ticket admission: publish only C(4) in a private full-state working store.
## Rotation and entropy/time run first; caller retains the parent slot for epoch-reset
## decisions.
##
## Exposes admitSafroleTicketsState and checked full-state publication results.

import ../../codec/state/[safrole as state_safrole, consensus as state_consensus,
    layout as state_layout, trie as state_trie]
import ../../codec/tickets
import ./admission as ticket_admission
import ../store

type
  TicketStateResult* = object ## Only successful publication contains a complete immutable working-store snapshot.
    case status: TicketAdmissionError
    of None:
      completed: StateStoreSnapshot # Retained history cannot be mutated through this result.
    else:
      discard                       # Failed/default publications contain their reason alone.

func error*(outcome: TicketStateResult): TicketAdmissionError =
  ## Inspect a reason without allowing payload access or result retagging.
  outcome.status

func value*(outcome: TicketStateResult): StateStoreSnapshot {.inline,
    requires: outcome.status == TicketAdmissionError.None.} =
  ## Extract only a fully published immutable snapshot after selecting successful admission.
  outcome.completed

func storeError(reason: StateStoreError): TicketAdmissionError =
  ## Preserve store resource/backend failures and distinguish absent required chapters from default stores.
  case reason
  of StateStoreError.Uninitialized: TicketAdmissionError.Uninitialized # No default store can provide stage state.
  of StateStoreError.MissingKey: TicketAdmissionError.MissingState # Missing state is never fabricated genesis data.
  of StateStoreError.LimitExceeded: TicketAdmissionError.LimitExceeded # Caller batch/map limits remain explicit.
  of StateStoreError.LengthOverflow: TicketAdmissionError.LengthOverflow # Preserve checked native extent refusal.
  of StateStoreError.BackendFailure: TicketAdmissionError.BackendFailure # Hash refusal publishes nothing.
  else: TicketAdmissionError.InvalidState # Other store errors cannot describe this fixed one-entry batch.

proc candidateEntry(owner: SafroleStateSnapshot, policy: SafroleStateConfig): SafroleStateResult[StateEntry] =
  ## Re-encode a candidate already validated under this exact policy, copying only bounded owned fields.
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

proc admitSafroleTicketsState*(state: var StateStore, previous, target: StateTime,
    submitted: openArray[Ticket], config: TicketAdmissionConfig): TicketStateResult =
  ## Admit against staged C(4)/C(6)/C(11), then atomically replace only C(4), or retain an unchanged snapshot.
  ## previous is the retained parent slot; C(11) must already equal target after entropy/time advancement.
  ## This substep neither authenticates prior stages nor publishes a canonical complete block transition.
  if uint32(target) <= uint32(previous):
    return TicketStateResult(status: TicketAdmissionError.InvalidSlot) # No repeated/backward/wrapped slots.
  let before = state.snapshot
  if before.error != StateStoreError.None:
    return TicketStateResult(status: storeError(before.error)) # No default working map.
  let time = before.value.lookup(chapterKey(StateChapter(11)))
  if time.error != StateStoreError.None:
    return TicketStateResult(status: storeError(time.error)) # A missing time is not slot zero.
  let entropy = before.value.lookup(chapterKey(StateChapter(6)))
  if entropy.error != StateStoreError.None:
    return TicketStateResult(status: storeError(entropy.error)) # A missing entropy is not an all-zero word.
  if time.value.byteLength != 4 or entropy.value.byteLength != 128:
    return TicketStateResult(status: TicketAdmissionError.InvalidState) # Bound fixed copies and reject suffixes/truncation.
  let decodedTime = decodeStateTime(time.value.bytes)
  let decodedEntropy = decodeStateEntropy(entropy.value.bytes)
  if decodedTime.error != StateComponentError.None or decodedEntropy.error !=
      StateComponentError.None:
    return TicketStateResult(status: TicketAdmissionError.InvalidState) # No default/partial fixed state.
  if uint32(decodedTime.value.value) != uint32(target):
    return TicketStateResult(status: TicketAdmissionError.InvalidState) # Refuse missing/out-of-order entropy-time staging.
  let found = before.value.lookup(chapterKey(StateChapter(4)))
  if found.error != StateStoreError.None:
    return TicketStateResult(status: storeError(found.error)) # No missing C(4) fallback.
  if uint64(found.value.byteLength) > uint64(config.state.maxBytes):
    return TicketStateResult(status: TicketAdmissionError.LimitExceeded) # Check the caller's ceiling before copying C(4).
  let original = found.value.bytes
  let admitted = admitSafroleTickets(original, previous, target, decodedEntropy.value.value[2],
    submitted, config)
  if admitted.error != TicketAdmissionError.None:
    return TicketStateResult(status: admitted.error) # Invalid proofs/eligibility/selection publish no accepted prefix.
  let next = candidateEntry(admitted.value, config.state)
  if next.error != StateComponentError.None:
    if next.error == StateComponentError.LimitExceeded:
      return TicketStateResult(status: TicketAdmissionError.LimitExceeded) # Preserve posterior byte/count policy.
    elif next.error == StateComponentError.LengthOverflow:
      return TicketStateResult(status: TicketAdmissionError.LengthOverflow) # Preserve native extent refusal.
    else:
      return TicketStateResult(status: TicketAdmissionError.InvalidState) # Never publish a failed re-encoding.
  if next.value.value == original:
    return TicketStateResult(status: TicketAdmissionError.None,
        completed: before.value) # Valid no-op requires no write budget or root hash.
  let published = state.apply(@[StateWrite(key: next.value.key, kind: StateWriteKind.Put,
    value: next.value.value)])
  if published.error != StateStoreError.None:
    return TicketStateResult(status: storeError(published.error)) # Private candidate hashing precedes the store's sole publication.
  TicketStateResult(status: TicketAdmissionError.None, completed: published.value)
