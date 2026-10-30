# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 safrole.tex: coordinate authenticated Safrole changes before one canonical
## publication. Full-state maps only; posterior disputes offenders are supplied, not executed by
## this stage.
##
## Exposes advanceSafroleState with typed rotation, ticket, schedule, marker, authentication,
## entropy and publication failures.

import ../../codec/state/[safrole as state_safrole, consensus as state_consensus,
    layout as state_layout, trie as state_trie]
import ../../codec/[header, tickets, bounded]
from ../../codec/disputes import OffenderKey
import ../store
import ../validator/state as validator_state
import ../ticket/admission as ticket_admission
import ../sealer/schedule as sealer_schedule
import ./[markers as safrole_markers, authentication as safrole_authentication]
import ../entropy

type
  SafroleTransitionConfig* = object ## One shared chain profile prevents incompatible epoch/roster parameters between substeps.
    state*: SafroleStateConfig
    tailStart*: EpochSlots
    blockTickets*: TicketLimit
    offenders*: ElementLimit
    maxHeaderBytes*: ByteLimit
    maxMarkerBytes*: ByteLimit
  SafroleTransitionError* {.pure.} = enum ## Preflight errors and typed substep refusals; failures contain reasons, never intermediate state.
    Uninitialized, None, InvalidConfig, InvalidHeader, InvalidState, MissingState,
    InvalidSlot, LimitExceeded, RotationFailure, AdmissionFailure, ScheduleFailure,
    MarkerFailure, AuthenticationFailure, EntropyFailure, PublicationFailure
  SafroleTransition* = object ## Success retains the canonical immutable map and the exact authenticated signed header.
    snapshot*: StateStoreSnapshot
    authentication*: SafroleAuthentication
  SafroleTransitionResult* = object ## Private tagged payloads protect both successful extraction and stage-specific failure reasons.
    case status: SafroleTransitionError
    of None:
      completed: SafroleTransition           # No mutable working handle or transient snapshot escapes.
    of RotationFailure:
      rotationReason: ValidatorStateError    # Only this rejected substep's cause is retained.
    of AdmissionFailure:
      admissionReason: TicketAdmissionError  # Only this rejected substep's cause is retained.
    of ScheduleFailure:
      scheduleReason: SealerScheduleError    # Only this rejected substep's cause is retained.
    of MarkerFailure:
      markerReason: SafroleMarkerError       # Only this rejected substep's cause is retained.
    of AuthenticationFailure:
      authenticationReason: SafroleAuthError # Only this rejected substep's cause is retained.
    of EntropyFailure:
      entropyReason: EntropyTransitionError  # Only this rejected substep's cause is retained.
    of PublicationFailure:
      publicationReason: StateStoreError     # Only this rejected substep's cause is retained.
    else:
      discard                                # Default/preflight failures have no payload.

func error*(outcome: SafroleTransitionResult): SafroleTransitionError =
  ## Read the status without permitting retagging or access to unsuccessful payloads.
  outcome.status

func value*(outcome: SafroleTransitionResult): SafroleTransition {.inline,
    requires: outcome.status == SafroleTransitionError.None.} =
  ## Extract complete success only; defaults/refusals cannot expose a working map or header.
  outcome.completed

func rotationError*(outcome: SafroleTransitionResult): ValidatorStateError {.inline,
    requires: outcome.status == SafroleTransitionError.RotationFailure.} =
  ## Inspect the precise rotation refusal only after selecting that failed substep.
  outcome.rotationReason

func admissionError*(outcome: SafroleTransitionResult): TicketAdmissionError {.inline,
    requires: outcome.status == SafroleTransitionError.AdmissionFailure.} =
  ## Inspect the precise admission refusal only after selecting that failed substep.
  outcome.admissionReason

func scheduleError*(outcome: SafroleTransitionResult): SealerScheduleError {.inline,
    requires: outcome.status == SafroleTransitionError.ScheduleFailure.} =
  ## Inspect the precise schedule refusal only after selecting that failed substep.
  outcome.scheduleReason

func markerError*(outcome: SafroleTransitionResult): SafroleMarkerError {.inline,
    requires: outcome.status == SafroleTransitionError.MarkerFailure.} =
  ## Inspect the precise marker refusal only after selecting that failed substep.
  outcome.markerReason

func authenticationError*(outcome: SafroleTransitionResult): SafroleAuthError {.inline,
    requires: outcome.status == SafroleTransitionError.AuthenticationFailure.} =
  ## Inspect the precise authentication refusal only after selecting that failed substep.
  outcome.authenticationReason

func entropyError*(outcome: SafroleTransitionResult): EntropyTransitionError {.inline,
    requires: outcome.status == SafroleTransitionError.EntropyFailure.} =
  ## Inspect the precise entropy refusal only after selecting that failed substep.
  outcome.entropyReason

func publicationError*(outcome: SafroleTransitionResult): StateStoreError {.inline,
    requires: outcome.status == SafroleTransitionError.PublicationFailure.} =
  ## Inspect the precise publication refusal only after selecting that failed substep.
  outcome.publicationReason

proc chapterEntry(owner: SafroleStateSnapshot, policy: SafroleStateConfig): SafroleStateResult[StateEntry] =
  ## Re-encode an already bounded immutable C(4), retaining its complete pending/root/schedule/contest.
  let info = safroleInfo(owner).value
  var source = SafroleState(pending: newSeq[StateValidator](info.validators), root: info.root,
    schedule: ticketSchedule(@[]), accumulator: newSeq[WinningTicket](info.accumulated))
  # Fixed owner-bound copies cannot detach a span from its original chapter.
  for i in 0..<source.pending.len:
    source.pending[i] = pendingValidatorAt(owner, StateValidatorIndex(uint64(i))).value
  # Admission already proved canonical identifiers and bounded the retained contest.
  for i in 0..<source.accumulator.len:
    source.accumulator[i] = accumulatedTicketAt(owner, SafroleStateIndex(uint64(i))).value
  case info.kind
  of SealerKind.Tickets:
    # Preserve whole records and their literal E1 attempts.
    var values = newSeq[WinningTicket](info.slots)
    for i in 0..<values.len:
      values[i] = sealerTicketAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = ticketSchedule(values)
  of SealerKind.Keys:
    # Fallback slot order, nulls and repeated keys remain protocol data.
    var values = newSeq[StateBsKey](info.slots)
    for i in 0..<values.len:
      values[i] = sealerKeyAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = keySchedule(values)
  safroleStateEntry(source, policy)

proc advanceSafroleState*(state: var StateStore, candidate: OwnedHeader,
    submitted: openArray[Ticket], offenders: openArray[OffenderKey],
    config: SafroleTransitionConfig): SafroleTransitionResult =
  ## Execute rotation, ticket admission, schedule/markers, seal/entropy and one final atomic write batch.
  ## candidate/submitted are structurally decoded header/tickets; their block commitment is checked elsewhere.
  ## Borrow offenders synchronously from validated posterior disputes; C(5)/C(7) and unrelated entries are preserved.
  ## Private rotation may hash its candidate; no intermediate state is assigned to the canonical store.
  let epoch = uint64(config.state.epochSlots)
  if epoch == 0 or uint64(config.tailStart) == 0 or uint64(config.tailStart) >= epoch:
    return SafroleTransitionResult(status: SafroleTransitionError.InvalidConfig) # No division or work under an invalid chain profile.
  let header = headerInfo(candidate)
  if header.error != HeaderError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.InvalidHeader) # A default owner is not a complete signed header.
  if uint64(header.value.consumed) > uint64(config.maxHeaderBytes) or
      uint64(submitted.len) > uint64(config.blockTickets) or uint64(offenders.len) > uint64(
          config.offenders):
    return SafroleTransitionResult(status: SafroleTransitionError.LimitExceeded) # Bound untrusted work before rotation/native setup.
  let retained = state.snapshot
  if retained.error != StateStoreError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.Uninitialized) # Never fabricate a genesis map.
  let parent = retained.value
  let oldTime = parent.lookup(chapterKey(StateChapter(11)))
  let oldEntropy = parent.lookup(chapterKey(StateChapter(6)))
  let oldChapter = parent.lookup(chapterKey(StateChapter(4)))
  if oldTime.error != StateStoreError.None or oldEntropy.error != StateStoreError.None or
      oldChapter.error != StateStoreError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.MissingState) # Every retained parent input is required.
  if oldTime.value.byteLength != 4 or oldEntropy.value.byteLength != 128:
    return SafroleTransitionResult(status: SafroleTransitionError.InvalidState) # Reject fixed chapter suffixes/truncations before copies.
  if uint64(oldChapter.value.byteLength) > uint64(config.state.maxBytes):
    return SafroleTransitionResult(status: SafroleTransitionError.LimitExceeded) # Bound the parent contest copy.
  let previous = decodeStateTime(oldTime.value.bytes)
  let entropy = decodeStateEntropy(oldEntropy.value.bytes)
  if previous.error != StateComponentError.None or entropy.error != StateComponentError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.InvalidState) # Extract only both complete fixed codec values.
  let target = StateTime(uint32(header.value.unsigned.slot))
  if uint32(target) <= uint32(previous.value.value):
    return SafroleTransitionResult(status: SafroleTransitionError.InvalidSlot) # Repeated/backward/wrapped candidates never rotate.
  # A copied handle shares immutable parent bytes; all intermediate writes remain local until final apply.
  var working = state
  let rotated = rotateValidatorState(working, target, offenders,
    ValidatorTransitionConfig(safrole: config.state, offenders: config.offenders))
  if rotated.error != ValidatorStateError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.RotationFailure,
      rotationReason: rotated.error) # A private failed ring/root plan never modifies the original handle.
  let staged = rotated.value
  let chapter = staged.lookup(chapterKey(StateChapter(4))).value
  let active = staged.lookup(chapterKey(StateChapter(8))).value
  # Only historical eta[2] is needed before authentication; no placeholder eta[0] or fake VRF is hashed.
  let crossed = uint64(uint32(target)) div epoch > uint64(uint32(previous.value.value)) div epoch
  let history2 = if crossed: entropy.value.value[1] else: entropy.value.value[2]
  let admitted = admitSafroleTickets(chapter.bytes, previous.value.value, target, history2,
    submitted, TicketAdmissionConfig(state: config.state, tailStart: config.tailStart,
      blockTickets: config.blockTickets))
  if admitted.error != TicketAdmissionError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.AdmissionFailure,
      admissionReason: admitted.error) # No accepted prefix or rotation can escape rejected tickets.
  let admittedEntry = chapterEntry(admitted.value, config.state)
  if admittedEntry.error != StateComponentError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.InvalidState) # Core capture was already bounded under this exact policy.
  let selected = selectSafroleSchedule(oldChapter.value.bytes, admittedEntry.value.value,
    active.bytes, previous.value.value, target, history2,
    SealerScheduleConfig(state: config.state, tailStart: config.tailStart))
  if selected.error != SealerScheduleError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.ScheduleFailure,
      scheduleReason: selected.error) # Fallback refusal exposes no generated prefix.
  let selectedEntry = chapterEntry(selected.value, config.state)
  if selectedEntry.error != StateComponentError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.InvalidState) # No invalid C(4) can reach authentication or publication.
  let unsigned = unsignedPart(candidate)
  let expected = deriveSafroleMarkers(oldChapter.value.bytes, selectedEntry.value.value,
    previous.value.value, target, entropy.value.value,
    SafroleMarkerConfig(state: config.state, tailStart: config.tailStart,
      maxMarkerBytes: config.maxMarkerBytes))
  if expected.error != SafroleMarkerError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.MarkerFailure,
      markerReason: expected.error) # The original contest and original entropy define both marker predicates.
  let markers = validateSafroleMarkers(expected.value, headerEpoch(unsigned.value).value,
    headerWinners(unsigned.value).value)
  if markers != SafroleMarkerError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.MarkerFailure,
      markerReason: markers) # A correctly signed but wrong marker is still a rejected candidate.
  let authenticated = authenticateSafroleSeal(candidate, selectedEntry.value.value, active.bytes,
    previous.value.value, entropy.value.value,
    SafroleAuthConfig(state: config.state, maxHeaderBytes: config.maxHeaderBytes))
  if authenticated.error != SafroleAuthError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.AuthenticationFailure,
      authenticationReason: authenticated.error) # Verify both ordinary credentials before using entropy output.
  let advanced = advanceEntropyTime(entropy.value.value, previous.value.value, target,
    authenticated.value.entropy, config.state.epochSlots)
  if advanced.error != EntropyTransitionError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.EntropyFailure,
      entropyReason: advanced.error) # Even a post-authentication primitive refusal preserves the entire parent.
  let nextEntropy = entropyEntry(advanced.value.entropy)
  let nextTime = timeEntry(target)
  var entries = @[selectedEntry.value, nextEntropy,
    StateEntry(key: chapterKey(StateChapter(8)), value: active.bytes),
    StateEntry(key: chapterKey(StateChapter(9)), value: staged.lookup(chapterKey(StateChapter(
        9))).value.bytes),
    nextTime]
  var writes: seq[StateWrite] = @[]
  # Write only changed chapters, preserving no-op budgets while treating the complete stage as one batch.
  for entry in entries:
    let original = parent.lookup(entry.key)
    if original.value.bytes != entry.value:
      writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put,
          value: entry.value)) # No deletes or unrelated mutations.
  let published = state.apply(writes)
  if published.error != StateStoreError.None:
    return SafroleTransitionResult(status: SafroleTransitionError.PublicationFailure,
      publicationReason: published.error) # Final map/batch/hash refusal discards every successful private substep.
  SafroleTransitionResult(status: SafroleTransitionError.None,
    completed: SafroleTransition(snapshot: published.value, authentication: authenticated.value))
