# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native GP assurance transition tests: unchanged tiny/full STF inputs plus threshold, timeout
## and ownership boundaries.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "availability_transition_arc_release"}

import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[availability, store]
import ../../../src/codec/[assurances, bounded]
import ../../../src/codec/state/[availability as state_availability, safrole as state_safrole,
    layout as state_layout, trie as state_trie]
import ../../../src/codec/[report_owned, owned, guarantees]
import ../../../src/crypto/assurance_context
import ../../support/arc_evidence

## Refuse transcript/publication hashing without replacing successful backend behavior.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Parse exact trusted hexadecimal fixtures; empty report collections use their own explicit token.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[i*2..i*2+1], result[i]) == 2 # Complete known octets only.

## The configured ceiling permits actual parent/posterior populations to differ within one chain profile.
proc policy(cores: uint64): AvailabilityTransitionConfig =
  AvailabilityTransitionConfig(rosters: ValidatorStateConfig(cores: CoreCount(cores),
      validators: ElementLimit(cores*3), maxBytes: ByteLimit(1000000)),
    assignments: AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(cores),
        validators: ValidatorCount(cores*3), maxBytes: ByteLimit(2000000)),
      maxPresent: ElementLimit(cores), maxBytes: ByteLimit(8000000)),
          availableReports: ElementLimit(cores))

## Encode one retained complete assignment snapshot for independent exact expected-byte comparisons.
proc assignmentBytes(owner: AvailabilitySnapshot, config: AvailabilityConfig): seq[byte] =
  var slots = newSeq[AvailabilityAssignment](availabilityInfo(owner).value.cores)
  for i in 0..<slots.len:
    slots[i] = availabilityAt(owner, AssignmentCoreIndex(uint64(
        i))).value # Preserve complete guarantee and registration.
  availabilityStateEntry(slots, config).value.value

## Copy exact canonical report bytes without exporting a mutable reference into retained plan storage.
proc reportBytes(owner: OwnedReport): seq[byte] =
  result = newSeq[byte](ownedReportInfo(owner).value.consumed)
  assert encodeOwnedReport(owner, result).error == OwnershipError.None

## Finite full-state limits cover every fixture roster and preserve unrelated values in adapter tests.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(20), perValue: ByteLimit(10000000),
    totalValueBytes: ByteLimit(30000000), nodes: TrieNodeLimit(10000)), writes: ElementLimit(5),
        writeValueBytes: ByteLimit(20000000))

## Compare all original entries/root after a failed staged transition or publication, not just the changed chapter.
proc unchanged(state: StateStore, entries: seq[StateEntry], root: StateRoot) =
  let snapshot = state.snapshot.value
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](root)
  for entry in entries:
    assert snapshot.lookup(entry.key).value.bytes ==
        entry.value # Includes both roster context and unrelated data.

## Return only the plan after all original decoded input owners leave their local scope.
proc escapedPlan(wire, roster: seq[byte], population: ValidatorCount, values: seq[Assurance],
    parent: AssuranceParent, slot: StateTime, config: AvailabilityTransitionConfig): AvailabilityPlan =
  let assignments = decodeAvailabilityState(wire, config.assignments).value.snapshot
  let active = decodeStateValidators(roster, config.rosters).value.value
  planAvailability(assignments, active, population, values, parent, slot, config).value

## A scoped call releases every temporary key table, transcript, assignment and report handle.
proc releaseCycle(owner: AvailabilitySnapshot, active: ValidatorStateSnapshot, values: seq[
    Assurance], parent: AssuranceParent, config: AvailabilityTransitionConfig, refused: bool) =
  failHash(cint(if refused: 1 else: 0))
  let result = planAvailability(owner, active, ValidatorCount(6), values, parent, StateTime(12), config)
  if refused:
    assert result.error == AvailabilityTransitionError.ContextFailure
    assert result.contextError == AssuranceContextError.BackendFailure
  else:
    assert result.error == AvailabilityTransitionError.None

## Signed tiny records prove exact two-thirds refusal, strict quorum success and widened deadline arithmetic.
proc boundaries(owner: AvailabilitySnapshot, active: ValidatorStateSnapshot, values: seq[Assurance],
    parent: AssuranceParent, original: seq[byte], config: AvailabilityTransitionConfig) =
  assert values.len == 6
  let exact = planAvailability(owner, active, ValidatorCount(6), values.toOpenArray(0, 4), parent,
      StateTime(12), config)
  assert exact.error == AvailabilityTransitionError.None and exact.value.availableReportCount == 0
  assert assignmentBytes(exact.value.assuredAssignments, config.assignments) ==
      original # Four votes out of six are insufficient.
  let strict = planAvailability(owner, active, ValidatorCount(6), values.toOpenArray(1, 5), parent,
      StateTime(12), config)
  assert strict.error == AvailabilityTransitionError.None and strict.value.availableReportCount == 1
  let before = planAvailability(owner, active, ValidatorCount(6), [], parent, StateTime(15), config)
  let deadline = planAvailability(owner, active, ValidatorCount(6), [], parent, StateTime(16), config)
  assert assignmentBytes(before.value.assuredAssignments, config.assignments) == original
  assert availabilityInfo(deadline.value.assuredAssignments).value.present ==
      0 # Five slots is inclusive, not six.
  var nearEnd = newSeq[AvailabilityAssignment](2)
  for i in 0..<2:
    nearEnd[i] = presentAssignment(availabilityAt(owner, AssignmentCoreIndex(uint64(
        i))).value.guarantee, AssignmentSlot(high(uint32)-2)) # Deadline exceeds E4.
  let entry = availabilityStateEntry(nearEnd, config.assignments).value
  let captured = decodeAvailabilityState(entry.value, config.assignments).value.snapshot
  let late = planAvailability(captured, active, ValidatorCount(6), [], parent, StateTime(high(
      uint32)), config)
  assert late.error == AvailabilityTransitionError.None
  assert availabilityInfo(late.value.assuredAssignments).value.present == 2 # No wrapped registration+5 timeout.
  var tight = config
  tight.availableReports = ElementLimit(0)
  assert planAvailability(owner, active, ValidatorCount(6), values, parent, StateTime(12),
      tight).error == AvailabilityTransitionError.LimitExceeded
  var records = newSeq[StateValidator](6)
  for i in 0..<6: records[i] = validatorAt(active, StateValidatorIndex(uint64(
      i))).value # Preserve every parent field.
  let first = records[0].ed25519
  let second = records[1].ed25519
  records[0].ed25519 = second
  records[1].ed25519 = first # A same-sized posterior set has different signing keys.
  let posterior = validatorEntry(ValidatorChapter.Active, records, config.rosters).value
  let entries = @[StateEntry(key: chapterKey(StateChapter(10)), value: original), posterior,
      timeEntry(StateTime(12))]
  var staged = newStateStore(entries, limits()).value
  let updated = advanceAvailabilityState(staged, active, values, parent, StateTime(12), config)
  assert updated.error == AvailabilityTransitionError.None # Signatures must use original parent keys, not posterior keys.
  assert updated.value.plan.availableReportCount == 1
  assert updated.value.snapshot.lookup(posterior.key).value.bytes ==
      posterior.value # No roster rewrite in the availability adapter.
  for warm in 0..<10: releaseCycle(owner, active, values, parent, config,
      false) # Exclude one-time caches from ARC evidence.
  let occupied = getOccupiedMem()
  for cycle in 0..<1000: releaseCycle(owner, active, values, parent, config, cycle mod 2 ==
      1) # Complete success and transcript refusal must both retire.
  let retired = getOccupiedMem()
  assert occupied == retired
  recordArcRelease("availability_transition", 1000, occupied, retired)
  failHash(0)

## Published expected bytes/reports and exact failure reasons are checked in Nim, independently of transport helpers.
proc main() {.raises.} =
  var cases, accepted = 0
  for line in readFile(getEnv("RAGNAROK_AVAILABILITY_TRANSITION")).splitLines:
    if line.len == 0: continue # Terminal newline is not another case.
    let parts = line.splitWhitespace
    assert parts.len == 12
    let config = policy(uint64(parseInt(parts[1])))
    let assignmentWire = unhex(parts[4])
    let owner = decodeAvailabilityState(assignmentWire, config.assignments)
    assert owner.error == AvailabilityError.None and owner.value.consumed == assignmentWire.len
    let active = decodeStateValidators(unhex(parts[5]), config.rosters)
    assert active.error == StateComponentError.None
    let population = validatorCount(active.value.value).value
    let assuranceConfig = AssuranceConfig(cores: config.rosters.cores, validators: ValidatorCount(
        uint64(population)))
    var values = newSeq[Assurance](population)
    let read = decodeAssurances(unhex(parts[3]), assuranceConfig, values)
    if read.error != AssuranceError.None:
      assert parts[2] in ["bad_validator_index", "not_sorted_or_unique_assurers"] # Canonical codec owns these exact structural rejections.
    else:
      values.setLen(read.count)
      var anchor = default(array[32, byte])
      let parentBytes = unhex(parts[8])
      for i in 0..<32: anchor[i] = parentBytes[i] # Fixed expected parent is supplied independently of every record.
      let parent = AssuranceParent(anchor)
      let slot = StateTime(uint32(parseInt(parts[7])))
      let posterior = ValidatorCount(uint64(parseInt(parts[11])))
      let planned = planAvailability(owner.value.snapshot, active.value.value, posterior, values,
          parent, slot, config)
      if parts[2] != "ok":
        if parts[2] == "core_not_engaged":
          assert planned.error == AvailabilityTransitionError.UnassignedCore # A valid signature cannot assure post-disputes absence.
        else:
          assert planned.error == AvailabilityTransitionError.ContextFailure
          assert planned.contextError == (if parts[2] ==
              "bad_signature": AssuranceContextError.InvalidSignature else: AssuranceContextError.WrongParent)
      else:
        if planned.error != AvailabilityTransitionError.None: echo parts[0], " got ",
            planned.error # Identify a changed upstream case without hiding failures.
        assert planned.error == AvailabilityTransitionError.None
        let plan = escapedPlan(assignmentWire, unhex(parts[5]), posterior, values, parent, slot, config)
        assert plan.availableReportCount == planned.value.availableReportCount # Independent escaped captures survive local input retirement.
        assert assignmentBytes(plan.assuredAssignments, config.assignments) == unhex(parts[9])
        let reports = if parts[10] == "-": newSeq[string](0) else: parts[10].split(
            ',') # Exact published available-report sequence.
        assert plan.availableReportCount == reports.len
        for i in 0..<reports.len: assert reportBytes(plan.availableReportAt(i).value) == unhex(
            reports[i]) # Core order and complete reports.
        assert plan.availableReportAt(-1).error == AvailabilityTransitionError.InvalidIndex
        assert plan.availableReportAt(reports.len).error == AvailabilityTransitionError.InvalidIndex
        assert assignmentBytes(owner.value.snapshot, config.assignments) ==
            assignmentWire # Input owner stays immutable.
        if parts[0].endsWith("tiny/some_assurances-1.json"):
          boundaries(owner.value.snapshot, active.value.value, values, parent, assignmentWire, config)
        if uint64(posterior) >= 6:
          let entries = @[StateEntry(key: chapterKey(StateChapter(10)), value: assignmentWire),
            StateEntry(key: chapterKey(StateChapter(8)), value: unhex(parts[6])), timeEntry(slot),
            StateEntry(key: chapterKey(StateChapter(250)), value: @[4'u8, 9, 2])]
          var state = newStateStore(entries, limits()).value
          let root = state.snapshot.value.commitment.root
          let published = advanceAvailabilityState(state, active.value.value, values, parent, slot, config)
          assert published.error == AvailabilityTransitionError.None
          assert published.value.snapshot.lookup(chapterKey(StateChapter(10))).value.bytes == unhex(
              parts[9])
          for entry in entries:
            if array[31, byte](entry.key) != array[31, byte](chapterKey(StateChapter(10))):
              assert published.value.snapshot.lookup(entry.key).value.bytes ==
                  entry.value # Only C(10) may change.
          var refused = newStateStore(entries, limits()).value
          failHash(1)
          let failed = advanceAvailabilityState(refused, active.value.value, values, parent, slot, config)
          if values.len > 0:
            assert failed.error == AvailabilityTransitionError.ContextFailure and
                failed.contextError == AssuranceContextError.BackendFailure
          elif assignmentWire != unhex(parts[9]):
            assert failed.error == AvailabilityTransitionError.BackendFailure # Empty-assurance timeout publication still needs a genuine root.
          unchanged(refused, entries, root)
          failHash(0)
          assert advanceAvailabilityState(refused, active.value.value, values, parent, StateTime(
              uint32(slot)+1), config).error == AvailabilityTransitionError.InvalidSlot
          unchanged(refused, entries, root)
        else:
          assert parts[0].endsWith("tiny/val_set_size_change_clears_pending_reports-1.json") # Size-only STF projection, not a valid full-state roster.
        inc accepted
    inc cases
  assert cases == 22 and accepted == 10
  assert planAvailability(default(AvailabilitySnapshot), default(ValidatorStateSnapshot),
      ValidatorCount(6), [], default(AssuranceParent), StateTime(0), policy(2)).error ==
      AvailabilityTransitionError.InvalidState
  assert availableReportAt(default(AvailabilityPlan), 0).error ==
      AvailabilityTransitionError.Uninitialized
  echo "Availability transition: 22 pinned tiny/full assurance cases and authored boundaries passed"

try:
  main() # Missing or malformed trusted fixture transport fails the suite.
except:
  quit(2) # No partial corpus can masquerade as success.
