# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded validator/builder/other admission and canonical epoch gating. TLS callbacks supply
## authenticated identities; this module grants capacity only, never stream-specific privileges.
import std/assertions
import ./topology
import ../chain/[genesis, provider]
import ../codec/state/[safrole, consensus]

type
  PeerSlot* = distinct uint64 ## Native slot identity is checked before indexing owned policy storage.
  ValidatorConnectionBudget* = range[1..3069] ## At most three independent 1023-member rosters.
  GuestConnectionBudget* = range[0..256] ## Explicit bounded reservations for each non-validator class.
  PeerClass* {.pure.} = enum ## Capacity classification never authorizes application protocols.
    Validator, Builder, Other
  AdmissionError* {.pure.} = enum ## Failed/default outcomes carry no accepted class or applied topology.
    Uninitialized, None, InvalidConfig, InvalidSlot, InvalidIdentity, Duplicate, Full, MissingState,
      InvalidState, Stale
  EpochUpdate* {.pure.} = enum ## A held update preserves both accepted topology and admission records.
    Held, Applied
  AdmissionResult*[T] = object ## Read-only success selection precedes fixed fact extraction.
    case status: AdmissionError
    of None: completed: T
    else: discard              # No failed operation publishes a partial policy change.
  AdmittedPeer = object ## Private mutable slot; closure authority remains with the owning native transport.
    occupied, closing, builder: bool
    identity: StateEdKey
    category: PeerClass
  ValidatorAdmission* = object ## Plain owned state is mutated through var parameters; no mutable slot array escapes.
    initialized: bool
    local: StateEdKey
    accepted: ValidatorTopology
    slots: seq[AdmittedPeer]
    ceilings, counts: array[PeerClass, int]

func error*[T](outcome: AdmissionResult[T]): AdmissionError =
  ## Inspect failure without acquiring a payload.
  outcome.status
func value*[T](outcome: AdmissionResult[T]): T {.requires: outcome.status == AdmissionError.None.} =
  ## Extract a selected success only.
  outcome.completed
func ready*(policy: ValidatorAdmission): bool =
  ## Default policy is unavailable, never a zero-capacity live listener.
  policy.initialized
func capacity*(policy: ValidatorAdmission): int =
  ## Return the exact native slot budget; default policy has no slots.
  policy.slots.len
func count*(policy: ValidatorAdmission, category: PeerClass): int =
  ## Closing slots remain physically owned but no longer consume a desired class reservation.
  policy.counts[category]
func topology*(policy: ValidatorAdmission): ValidatorTopology {.requires: policy.ready.} =
  ## Return an immutable accepted projection, with no pending topology authority.
  policy.accepted
func same(left, right: StateEdKey): bool =
  ## Compare Ed25519 identities only.
  array[32, byte](left) == array[32, byte](right)
func validIdentity(identity: StateEdKey): bool =
  ## Null validator identity cannot request an ordinary or builder reservation either.
  not same(identity, nullValidator().ed25519)
func initValidatorAdmission*(topology: ValidatorTopology, local: StateEdKey,
    validators: ValidatorConnectionBudget, builders: GuestConnectionBudget = 20,
    others: GuestConnectionBudget = 20): AdmissionResult[ValidatorAdmission] =
  ## Seed an already selected connectivity view. Startup canonical selection remains the caller's job.
  if not topology.ready: return AdmissionResult[ValidatorAdmission](
      status: AdmissionError.Uninitialized)
  if not validIdentity(local): return AdmissionResult[ValidatorAdmission](
      status: AdmissionError.InvalidIdentity)
  # Typed ceilings prove total <=3581, below the generic4096-peer transport ceiling.
  let total = int(validators)+int(builders)+int(others)
  AdmissionResult[ValidatorAdmission](status: AdmissionError.None,
    completed: ValidatorAdmission(initialized: true, local: local, accepted: topology,
      slots: newSeq[AdmittedPeer](total), ceilings: [int(validators), int(builders), int(others)]))
proc classify(topology: ValidatorTopology, identity: StateEdKey, builder: bool): PeerClass =
  ## Validator membership takes priority over a reservation request.
  if topology.contains(identity): PeerClass.Validator
  elif builder: PeerClass.Builder
  else: PeerClass.Other # Unauthenticated caller claims never reach this internal decision.
proc admitAuthenticated*(policy: var ValidatorAdmission, slot: PeerSlot,
    identity: StateEdKey, builder: bool): AdmissionResult[PeerClass] =
  ## Commit a synchronous authenticated callback decision; native retention follows success atomically.
  if not policy.ready: return AdmissionResult[PeerClass](status: AdmissionError.Uninitialized)
  if uint64(slot) >= uint64(policy.slots.len): return AdmissionResult[PeerClass](
      status: AdmissionError.InvalidSlot)
  let index = int(uint64(slot))
  if policy.slots[index].occupied: return AdmissionResult[PeerClass](
      status: AdmissionError.InvalidSlot)
  if not validIdentity(identity) or same(policy.local, identity):
    return AdmissionResult[PeerClass](status: AdmissionError.InvalidIdentity) # No self-loop or null guest fallback.
  for position in 0..<policy.slots.len:
    if policy.slots[position].occupied and same(policy.slots[position].identity, identity):
      return AdmissionResult[PeerClass](status: AdmissionError.Duplicate) # Closing peers retain their identity until actual retirement.
  let category = classify(policy.accepted, identity, builder)
  if policy.counts[category] >= policy.ceilings[category]:
    return AdmissionResult[PeerClass](status: AdmissionError.Full) # Other classes cannot borrow a reserved slot.
  policy.slots[index] = AdmittedPeer(occupied: true, identity: identity, builder: builder,
      category: category)
  inc policy.counts[category] # Preceding comparison proves this increment remains within the typed ceiling.
  AdmissionResult[PeerClass](status: AdmissionError.None, completed: category)
proc release*(policy: var ValidatorAdmission, slot: PeerSlot): bool =
  ## Observe a genuine native close once; premature/fabricated/duplicate closure is rejected.
  if not policy.ready or uint64(slot) >= uint64(policy.slots.len): return false
  let index = int(uint64(slot))
  if not policy.slots[index].occupied: return false
  if not policy.slots[index].closing:
    let category = policy.slots[index].category
    assert policy.counts[category] > 0
    dec policy.counts[category] # Closing entries were already removed from desired-role counts.
  policy.slots[index] = default(AdmittedPeer)
  true
func retiring*(policy: ValidatorAdmission, slot: PeerSlot): bool =
  ## The runtime must close marked peers, then release only after their actual close callback.
  uint64(slot) < uint64(policy.slots.len) and policy.slots[int(uint64(slot))].occupied and
      policy.slots[int(uint64(slot))].closing
proc announcements*(policy: ValidatorAdmission, slot: PeerSlot): bool =
  ## Accepted grid membership determines UP0; builder reservation does not change protocol eligibility.
  if not policy.ready or uint64(slot) >= uint64(policy.slots.len): return false
  let index = int(uint64(slot))
  if not policy.slots[index].occupied or policy.slots[index].closing: return false
  let identity = policy.slots[index].identity
  if not policy.accepted.contains(policy.local) or not policy.accepted.contains(
      identity): return true
  policy.accepted.neighbours(policy.local, identity)
proc replace(policy: var ValidatorAdmission, topology: ValidatorTopology) =
  ## Reclassify deterministically in native-slot order; no unchecked state remains after validation.
  policy.counts = default(array[PeerClass, int])
  for index in 0..<policy.slots.len:
    if policy.slots[index].occupied and not policy.slots[index].closing:
      let category = classify(topology, policy.slots[index].identity, policy.slots[index].builder)
      if policy.counts[category] >= policy.ceilings[category]:
        policy.slots[index].closing = true # Preserve physical ownership until the runtime observes close.
      else:
        policy.slots[index].category = category
        inc policy.counts[category] # Ceiling comparison bounds each desired count.
  policy.accepted = topology
proc advance*(policy: var ValidatorAdmission, view: ChainView, now: StateTime,
    limits: SafroleStateConfig): AdmissionResult[EpochUpdate] =
  ## Capture the caller's canonical best atomically; a new epoch requires both finality and delay.
  if not policy.ready: return AdmissionResult[EpochUpdate](status: AdmissionError.Uninitialized)
  let best = view.bestBlock
  if best.error != GenesisError.None: return AdmissionResult[EpochUpdate](
      status: AdmissionError.MissingState)
  let projected = captureValidatorTopology(best, limits)
  if projected.error != TopologyError.None:
    return AdmissionResult[EpochUpdate](status: AdmissionError.InvalidState) # Failed chapters preserve all accepted records/counts.
  let incoming = projected.value
  let duration = policy.accepted.epochSlots
  if incoming.epochSlots != duration: return AdmissionResult[EpochUpdate](
      status: AdmissionError.InvalidConfig)
  let previous = policy.accepted.slot div duration
  let epoch = incoming.slot div duration
  if epoch < previous: return AdmissionResult[EpochUpdate](status: AdmissionError.Stale)
  if incoming.slot > uint32(now): return AdmissionResult[EpochUpdate](status: AdmissionError.None,
      completed: EpochUpdate.Held)
  if epoch > previous:
    let finalized = view.finalizedBlock
    if finalized.error != GenesisError.None:
      return AdmissionResult[EpochUpdate](status: AdmissionError.None,
          completed: EpochUpdate.Held) # Best-head progress is not finality.
    if finalized.value.slot div duration < epoch:
      return AdmissionResult[EpochUpdate](status: AdmissionError.None,
          completed: EpochUpdate.Held) # Earlier epochs still need their connectivity.
    if finalized.value.slot div duration > epoch:
      return AdmissionResult[EpochUpdate](status: AdmissionError.InvalidState) # Inconsistent selected canonical/finalized clocks.
    let start = incoming.slot - incoming.slot mod duration
    let delay = max(duration div 30, 1'u32)
    if uint32(now)-start < delay:
      return AdmissionResult[EpochUpdate](status: AdmissionError.None,
          completed: EpochUpdate.Held) # No multiplication or wrapped epoch-start subtraction.
  replace(policy, incoming)
  AdmissionResult[EpochUpdate](status: AdmissionError.None, completed: EpochUpdate.Applied)
