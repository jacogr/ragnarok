# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T chapter 10: fixed core sequence of optional (full guarantee, E4 registration
## slot). Structural serialization does not establish availability, credential validity or
## transition eligibility.
##
## Exposes explicit absent/present assignments, chapter-10 encoding/decoding and retained
## guarantee/registration access.

import std/assertions
import ./bounded as codec_bounded
import ./assurances as codec_assurances
import ./guarantees as codec_guarantees
import ./state_layout as codec_state_layout
import ./state_trie as codec_state_trie
export Guarantee

type
  AssignmentSlot* = distinct uint32 ## Registration time differs from the guarantee's evaluation slot and other report timeslots.
  AssignmentCoreIndex* = distinct uint64 ## Position in the configured core sequence, not an encoded validator or report offset.
  AvailabilityAssignment* = object ## A complete source/extracted value retains its immutable report and copies all fixed credential bytes.
    case isPresent: bool
    of true:
      child: Guarantee             # Full guarantee, including its own E4 slot and credentials.
      registration: AssignmentSlot # Additional registration time belongs to the assignment.
    of false:
      discard                      # Absence has neither a default guarantee nor a fabricated timestamp.
  AvailabilityConfig* = object ## Chain/report/credential policy plus independent present-item and whole-parent byte ceilings.
    guarantee*: GuaranteeConfig
    maxPresent*: ElementLimit
    maxBytes*: ByteLimit
  AvailabilityError* {.pure.} = enum ## Failed/default alternatives contain no values, child owners or parser progress.
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical,
    LimitExceeded, LengthOverflow, InvalidTag, InvalidReport, InvalidCredential,
    InvalidValidator, InvalidOwner, InvalidIndex
  AvailabilityResult*[T] = object ## Only complete success exposes its application payload.
    case status: AvailabilityError
    of None:
      completed: T                # Failure cannot masquerade as a valid empty assignment.
    else:
      discard                     # Default and failures contain only their reason.
  ## Private acyclic ARC storage retains child reports through immutable guarantee handles.
  AvailabilityData = ref object
    values: seq[AvailabilityAssignment]
    present: int
  AvailabilitySnapshot* = object ## Value handles share private immutable storage; replacing a handle cannot mutate retained siblings.
    data: nil AvailabilityData
  AvailabilityRead* = object ## Complete prefix decoding returns its owner and exact consumed extent together.
    snapshot*: AvailabilitySnapshot
    consumed*: int
  AvailabilityInfo* = object ## Fixed copied metadata describes slot and present counts, without exporting mutable arrays.
    cores*, present*: int
  ## Private synchronous descriptor never escapes as a detached span into caller memory.
  SlotLayout = object
    present: bool
    start, length: int
    registered: AssignmentSlot
  ## Protocol-bounded local scan validates all slots before any parent or child allocation.
  Layout = object
    slots: array[341, SlotLayout]
    present, consumed: int

func error*[T](value: AvailabilityResult[T]): AvailabilityError =
  ## Read-only failure reasons cannot authorize parent values, child handles or parser progress.
  value.status
func value*[T](value: AvailabilityResult[T]): T {.inline, requires: value.status ==
    AvailabilityError.None.} =
  ## Every complete payload needs success selection in checked optimized builds too.
  value.completed
func absentAssignment*(): AvailabilityAssignment =
  ## Absence contains neither a child report handle nor a registration timestamp; defaults are absent too.
  AvailabilityAssignment(isPresent: false)
func presentAssignment*(guarantee: Guarantee, registered: AssignmentSlot): AvailabilityAssignment =
  ## Capture a copied full guarantee whose immutable report handle is retained independently of its source.
  AvailabilityAssignment(isPresent: true, child: guarantee, registration: registered)
func present*(assignment: AvailabilityAssignment): bool =
  ## Inspect the optional alternative without allowing callers to retag its storage.
  assignment.isPresent
func guarantee*(assignment: AvailabilityAssignment): Guarantee {.inline,
    requires: assignment.isPresent.} =
  ## A present assignment alone authorizes a copied guarantee and retained immutable report child.
  assignment.child
func registered*(assignment: AvailabilityAssignment): AssignmentSlot {.inline,
    requires: assignment.isPresent.} =
  ## Registration zero remains distinct from an absent assignment with no readable timestamp.
  assignment.registration

## Reuse the existing guarantee profile domain before indexing the fixed local scan array.
proc validate(config: AvailabilityConfig): AvailabilityError =
  if not codec_assurances.validConfig(AssuranceConfig(cores: config.guarantee.cores,
      validators: config.guarantee.validators)):
    return AvailabilityError.InvalidConfig # Only the existing 2..341 core and multiple-of-three validator profiles are supported.
  if uint64(config.guarantee.cores) > uint64(config.maxBytes):
    return AvailabilityError.LimitExceeded # Every configured slot needs at least its discriminator byte.
  AvailabilityError.None

## Preserve child report/credential reasons while keeping unrelated output-buffer statuses private.
proc childError(error: GuaranteeError): AvailabilityError =
  case error
  of GuaranteeError.Uninitialized: AvailabilityError.Uninitialized # No complete child was selected.
  of GuaranteeError.None: AvailabilityError.None # Child validated completely.
  of GuaranteeError.InvalidConfig: AvailabilityError.InvalidConfig # Invalid chain/credential policy.
  of GuaranteeError.Truncated: AvailabilityError.Truncated # A nested required field is missing.
  of GuaranteeError.NonCanonical: AvailabilityError.NonCanonical # Child count/order is not canonical.
  of GuaranteeError.LimitExceeded: AvailabilityError.LimitExceeded # A child resource or profile ceiling failed.
  of GuaranteeError.LengthOverflow: AvailabilityError.LengthOverflow # Native extent cannot be represented.
  of GuaranteeError.InvalidTag: AvailabilityError.InvalidTag # Unknown nested work-result discriminator.
  of GuaranteeError.InvalidCredential: AvailabilityError.InvalidCredential # Guarantee needs two or three credentials.
  of GuaranteeError.InvalidValidator: AvailabilityError.InvalidValidator # E2 credential index is outside its profile.
  of GuaranteeError.InvalidOwner: AvailabilityError.InvalidOwner # No retained child owner exists.
  of GuaranteeError.InvalidIndex: AvailabilityError.InvalidIndex # Invalid child access cannot produce a value.
  else: AvailabilityError.InvalidReport # No unrelated child status can be interpreted as a valid report.

## Bound parent arithmetic and complete payload policy before committing output or captured progress.
proc grow(cursor: var int, bytes: int, limit: ByteLimit): AvailabilityError =
  if bytes > high(int)-cursor: return AvailabilityError.LengthOverflow # Check before addition.
  cursor += bytes
  if uint64(cursor) > uint64(limit): return AvailabilityError.LimitExceeded # Tags, guarantees and registration times all count.
  AvailabilityError.None

## Scan every configured optional slot and full child guarantee before allocating any owner.
proc scan(input: openArray[byte], config: AvailabilityConfig): AvailabilityResult[Layout] =
  let valid = validate(config)
  if valid != AvailabilityError.None: return AvailabilityResult[Layout](
      status: valid) # Configuration precedes input access.
  var layout = default(Layout)
  var cursor = 0
  # The sequence is fixed by core count, without an outer count prefix or omitted absent slots.
  for i in 0..<int(uint64(config.guarantee.cores)):
    var error = grow(cursor, 1, config.maxBytes)
    if error != AvailabilityError.None: return AvailabilityResult[Layout](
        status: error) # Discriminator consumes parent budget.
    if input.len < cursor: return AvailabilityResult[Layout](
        status: AvailabilityError.Truncated) # Require tag before access.
    let tag = input[cursor-1]
    if tag > 1: return AvailabilityResult[Layout](
        status: AvailabilityError.InvalidTag) # Only absent/present alternatives exist.
    if tag == 1:
      # Present-item policy bounds expensive nested parsing and later owner capture.
      if uint64(layout.present) >= uint64(config.maxPresent):
        return AvailabilityResult[Layout](status: AvailabilityError.LimitExceeded) # Check before increment/child work.
      let parsed = inspectGuarantee(input.toOpenArray(cursor, input.len-1), config.guarantee)
      if parsed.error != GuaranteeError.None:
        return AvailabilityResult[Layout](status: childError(parsed.error)) # No partial earlier child owner.
      layout.slots[i].start = cursor
      layout.slots[i].length = parsed.value.consumed
      error = grow(cursor, parsed.value.consumed, config.maxBytes)
      if error != AvailabilityError.None: return AvailabilityResult[Layout](
          status: error) # Full standalone guarantee contributes its exact length.
      let timestamp = cursor
      error = grow(cursor, 4, config.maxBytes)
      if error != AvailabilityError.None: return AvailabilityResult[Layout](
          status: error) # Registration time is an extra E4 field.
      if input.len < cursor: return AvailabilityResult[Layout](
          status: AvailabilityError.Truncated) # No partial timestamp.
      var slot = 0'u32
      for j in 0..<4: slot = slot or (uint32(input[timestamp+j]) shl (j*8)) # Explicit little-endian E4 decoding.
      layout.slots[i].registered = AssignmentSlot(slot)
      layout.slots[i].present = true
      inc layout.present
  layout.consumed = cursor
  AvailabilityResult[Layout](status: AvailabilityError.None, completed: layout)

proc decodeAvailabilityState*(input: openArray[byte],
    config: AvailabilityConfig): AvailabilityResult[AvailabilityRead] =
  ## Decode complete fixed-core state into private immutable parent/child storage only after full preflight.
  let checked = scan(input, config)
  if checked.error != AvailabilityError.None: return AvailabilityResult[AvailabilityRead](
      status: checked.error) # No captured owners after failure.
  let layout = checked.value
  let data = AvailabilityData(values: newSeq[AvailabilityAssignment](int(uint64(
      config.guarantee.cores))), present: layout.present)
  # Only complete selected children are captured; absence retains no report handle or timestamps.
  for i in 0..<data.values.len:
    if layout.slots[i].present:
      let record = layout.slots[i]
      let child = decodeGuarantee(input.toOpenArray(record.start, record.start+record.length-1),
          config.guarantee)
      if child.error != GuaranteeError.None:
        return AvailabilityResult[AvailabilityRead](status: childError(
            child.error)) # Preserve future child capture rejections.
      data.values[i] = presentAssignment(child.value.value, record.registered)
    else:
      data.values[i] = absentAssignment() # Distinct from present with a zero timestamp.
  AvailabilityResult[AvailabilityRead](status: AvailabilityError.None,
    completed: AvailabilityRead(snapshot: AvailabilitySnapshot(data: data),
        consumed: layout.consumed))

proc availabilityStateEntry*(values: openArray[AvailabilityAssignment],
    config: AvailabilityConfig): AvailabilityResult[StateEntry] =
  ## Encode exact fixed-core source shape into an independent C(10) entry after every child validates.
  let valid = validate(config)
  if valid != AvailabilityError.None: return AvailabilityResult[StateEntry](
      status: valid) # Invalid configuration cannot authorize source traversal.
  if uint64(values.len) != uint64(config.guarantee.cores):
    return AvailabilityResult[StateEntry](status: AvailabilityError.InvalidCount) # No outer count is emitted or inferred.
  var size = 0
  var present = 0'u64
  # Whole-source preflight precedes all child scratch/output allocation.
  for value in values:
    var error = grow(size, 1, config.maxBytes)
    if error != AvailabilityError.None: return AvailabilityResult[StateEntry](
        status: error) # Every absent slot still needs a tag.
    if value.present:
      if present >= uint64(config.maxPresent): return AvailabilityResult[StateEntry](
          status: AvailabilityError.LimitExceeded) # Bound child work first.
      let child = measureGuarantee(value.guarantee, config.guarantee)
      if child.error != GuaranteeError.None: return AvailabilityResult[StateEntry](
          status: childError(child.error)) # Retain existing source policy.
      error = grow(size, child.value, config.maxBytes)
      if error != AvailabilityError.None: return AvailabilityResult[StateEntry](
          status: error) # Check complete standalone child extent.
      error = grow(size, 4, config.maxBytes)
      if error != AvailabilityError.None: return AvailabilityResult[StateEntry](
          status: error) # Additional registration timestamp is mandatory.
      inc present
  var entry = StateEntry(key: chapterKey(StateChapter(10)), value: newSeq[byte](size))
  var cursor = 0
  # Stable sources and proved extents make all final copies independent of caller and report backing storage.
  for value in values:
    entry.value[cursor] = byte(ord(value.present))
    inc cursor
    if value.present:
      let child = encodeGuaranteeValue(value.guarantee, config.guarantee)
      if child.error != GuaranteeError.None: return AvailabilityResult[StateEntry](
          status: childError(child.error)) # No partially encoded entry escapes.
      for b in child.value:
        entry.value[cursor] = b # One temporary child buffer is released per iteration by ARC.
        inc cursor
      for j in 0..<4:
        entry.value[cursor] = byte((uint32(value.registered) shr (j*8)) and
            255) # E4 registered time, separate from child slot.
        inc cursor
  AvailabilityResult[StateEntry](status: AvailabilityError.None, completed: entry)

proc availabilityInfo*(owner: AvailabilitySnapshot): AvailabilityResult[AvailabilityInfo] =
  ## Inspect copied parent counts without exposing mutable slot storage.
  let data = owner.data
  if data == nil: return AvailabilityResult[AvailabilityInfo](
      status: AvailabilityError.InvalidOwner) # Defaults cannot masquerade as all-absent state.
  AvailabilityResult[AvailabilityInfo](status: AvailabilityError.None,
    completed: AvailabilityInfo(cores: data.values.len, present: data.present))

proc availabilityAt*(owner: AvailabilitySnapshot, core: AssignmentCoreIndex): AvailabilityResult[
    AvailabilityAssignment] =
  ## Extract a copied tagged assignment; its copied guarantee retains the report after parent release.
  let data = owner.data
  if data == nil: return AvailabilityResult[AvailabilityAssignment](
      status: AvailabilityError.InvalidOwner) # No default slot from missing storage.
  if uint64(core) >= uint64(data.values.len): return AvailabilityResult[
      AvailabilityAssignment](status: AvailabilityError.InvalidIndex) # Check before narrowing.
  AvailabilityResult[AvailabilityAssignment](status: AvailabilityError.None,
      completed: data.values[int(uint64(core))])
