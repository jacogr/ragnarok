# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_assurance_duty_arc_release"}

## Actual executed erasure sources and independently trusted complete parent chapters exercise original-index assurance acquisition duties and whole-plan refusal.

import std/[assertions, syncio]
import ../../../src/jamnp-s/[assurance_duty, availability_proof]
import ../../../src/chain/genesis
import ../../../src/codec/[bounded, header, assurances]
import ../../../src/codec/work/report
import ../../../src/codec/state/[layout, safrole, trie]
import ../../../src/state/store
import ../../../src/state/availability/specifier
import ../../support/[pvm_computed_report, jamnp_import_recovery_fixture,
  jamnp_topology_fixture, arc_evidence]

proc limits(): AssuranceDutyLimits =
  ## Explicit aggregate and plan limits cover the tested complete parent rather than inferring network or signing defaults.
  AssuranceDutyLimits(chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(4000000),
    reports: ElementLimit(341), requests: ElementLimit(341*1023))

proc replaceRoster(source: BlockSnapshotResult, roster: seq[StateValidator]): BlockSnapshotResult =
  ## Recommit a complete test-owned parent map while preserving its exact header; equal headers alone cannot authorize stale duties.
  let saved = source.value
  let chapter = validatorEntry(ValidatorChapter.Active, roster,
    ValidatorStateConfig(cores: saved.cores, validators: ElementLimit(1023),
      maxBytes: ByteLimit(1000000))).value
  var entries: seq[StateEntry] = @[]
  for index in 0..<saved.keyCount:
    # The replacement remains an independently trusted structural fixture, not fabricated GP block-admission evidence.
    let key = saved.keyAt(StateKeyIndex(index))
    if array[31, byte](key) != array[31, byte](chapter.key):
      entries.add(StateEntry(key: key, value: saved.lookup(key).value.bytes))
  entries.add(chapter)
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert saved.header.encodeOwnedHeader(wire).error == HeaderError.None, "encode exact fixture header"
  captureBlockSnapshot(wire, entries, saved.chainParameters)

proc changed(source: AvailabilityCommitment, count: int): BlockSnapshotResult =
  ## One real local key owns three original positions; an unrelated position is GP-null and must keep its coordinate.
  let original = registrationSnapshot(source, active = count, previous = count)
  assert original.error == GenesisError.None, "capture registration fixture"
  var roster = topologyRecords(1, count)
  roster[0] = nullValidator()
  roster[2].ed25519 = roster[1].ed25519
  roster[count-1].ed25519 = roster[1].ed25519
  replaceRoster(original, roster)

proc coordinates(source: AvailabilityCommitment, count: int, expected: array[3, uint64]) =
  ## Literal NP coordinates distinguish original roster ordinals and the non-optimal 12-validator recovery threshold (four, not five) from compressed or naive mappings.
  let saved = changed(source, count)
  assert saved.error == GenesisError.None, "capture repeated-key fixture"
  let result = captureAssuranceDuty(saved, topologyKey(61), limits())
  assert result.error == AssuranceDutyError.None, $result.error
  let duty = result.value
  let info = duty.dutyInfo.value
  assert info.assignments == 1 and info.localIndices == 3 and info.requests == 3, "one assignment times all three local indices"
  assert int(uint64(info.validators)) == count, "actual parent population"
  assert duty.matches(saved), "exact original parent matches"
  assert not duty.matches(unavailableGenesis()), "unavailable parent cannot match"
  let ordinary = registrationSnapshot(source, active = count, previous = count)
  assert array[32, byte](ordinary.value.blockHash) == array[32, byte](saved.value.blockHash), "identical header control"
  assert not duty.matches(ordinary), "the same sealed header with a different complete posterior map cannot revive the plan"
  for index in 0..<3:
    # The first two local indices and last roster index remain distinct even though their signing identity is identical.
    let ordinal = if index < 2: index+1 else: count-1
    assert uint16(duty.localIndex(index).value) == uint16(ordinal), "original uncompressed validator index"
    let request = duty.shardRequest(CoreIndex(1), index)
    assert request.error == AssuranceDutyError.None, "complete CE137 request"
    assert request.value.kind == AvailabilityTransferKind.Distribution, "distribution transfer kind"
    assert uint64(request.value.shard) == expected[index],
        "assigned shard coordinate: validators=" & $count & "; local ordinal=" & $ordinal &
        "; actual=" & $uint64(request.value.shard) & "; expected=" & $expected[index]
    assert request.value.root.bytes == source.availabilityInfo.value.specifier.erasureRoot.bytes, "canonical report erasure root"
  assert duty.localIndex(-1).error == AssuranceDutyError.InvalidIndex, "negative local index refused"
  assert duty.localIndex(3).error == AssuranceDutyError.InvalidIndex, "exclusive local index refused"
  assert duty.shardRequest(CoreIndex(0), 0).error == AssuranceDutyError.InvalidIndex, "absent core cannot request shards"
  assert duty.shardRequest(CoreIndex(341), 0).error == AssuranceDutyError.InvalidIndex, "exclusive core bound refused"
  assert duty.shardRequest(CoreIndex(1), -1).error == AssuranceDutyError.InvalidIndex, "negative request ordinal refused"
  assert duty.assignment(CoreIndex(0)).value.present == false, "absent core remains absent"
  var narrow = limits()
  narrow.requests = ElementLimit(3)
  assert captureAssuranceDuty(saved, topologyKey(61), narrow).error == AssuranceDutyError.None, "exact complete request budget accepted"
  narrow.requests = ElementLimit(2)
  assert captureAssuranceDuty(saved, topologyKey(61), narrow).error ==
      AssuranceDutyError.LimitExceeded, "one missing request unit refuses whole plan"

proc refuse(source: AvailabilityCommitment) =
  ## Missing authority, whole-chapter bounds and malformed actual parent chapters never publish a successful prefix.
  let saved = registrationSnapshot(source, active = 6, previous = 6)
  assert not default(AssuranceDuty).valid, "default plan disabled"
  assert default(AssuranceDuty).dutyInfo.error == AssuranceDutyError.Uninitialized, "default plan exposes no metadata"
  assert captureAssuranceDuty(unavailableGenesis(), topologyKey(61), limits()).error ==
      AssuranceDutyError.InvalidSource, "unavailable canonical source refused"
  assert captureAssuranceDuty(saved, default(StateEdKey), limits()).error ==
      AssuranceDutyError.InvalidIdentity, "null local identity refused"
  assert captureAssuranceDuty(saved, nullValidator().ed25519, limits()).error ==
      AssuranceDutyError.InvalidIdentity, "GP null identity refused"
  assert captureAssuranceDuty(saved, topologyKey(300), limits()).error ==
      AssuranceDutyError.NotValidator, "non-validator identity refused"
  assert captureAssuranceDuty(saved, topologyKey(61), default(AssuranceDutyLimits)).error ==
      AssuranceDutyError.InvalidPolicy, "default resource policy refused"
  var total = 0'u64
  var largest = 0'u64
  for chapter in [StateChapter(8), StateChapter(9), StateChapter(10), StateChapter(11)]:
    # Independent stored extents define exact whole-read and per-chapter boundaries.
    let size = uint64(saved.value.lookup(chapterKey(chapter)).value.byteLength)
    total += size
    largest = max(largest, size)
  var narrow = limits()
  narrow.readBytes = ByteLimit(total)
  narrow.chapterBytes = ByteLimit(largest)
  assert captureAssuranceDuty(saved, topologyKey(61), narrow).error == AssuranceDutyError.None, "exact whole-read budget accepted"
  narrow.readBytes = ByteLimit(total-1)
  assert captureAssuranceDuty(saved, topologyKey(61), narrow).error ==
      AssuranceDutyError.LimitExceeded, "one missing read byte refuses whole plan"
  narrow = limits()
  narrow.chapterBytes = ByteLimit(largest-1)
  assert captureAssuranceDuty(saved, topologyKey(61), narrow).error ==
      AssuranceDutyError.LimitExceeded, "one missing chapter byte refuses whole plan"
  let suffix = registrationSnapshot(source, active = 6, previous = 6, badSuffix = true)
  assert captureAssuranceDuty(suffix, topologyKey(61), limits()).error ==
      AssuranceDutyError.InvalidState, "trailing C10 bytes refused"
  let future = registrationSnapshot(source, active = 6, previous = 6, registered = 21)
  assert captureAssuranceDuty(future, topologyKey(61), limits()).error ==
      AssuranceDutyError.InvalidState, "future registration refused"
  let population = registrationSnapshot(source, active = 9, previous = 9)
  assert captureAssuranceDuty(population, topologyKey(61), limits()).error ==
      AssuranceDutyError.InvalidState, "report and active population mismatch refused"

proc cycle(saved: BlockSnapshotResult) =
  ## Every scoped successful/late-refused plan and extracted assignment retires before ARC occupancy is compared.
  let planned = captureAssuranceDuty(saved, topologyKey(61), limits())
  assert planned.error == AssuranceDutyError.None, "ARC cycle source qualification"
  let duty = planned.value
  assert duty.assignment(CoreIndex(1)).value.present, "ARC cycle retained assignment"
  assert duty.shardRequest(CoreIndex(1), 2).error == AssuranceDutyError.None, "ARC cycle retained final request"
  var narrow = limits()
  narrow.requests = ElementLimit(2)
  assert captureAssuranceDuty(saved, topologyKey(61), narrow).error ==
      AssuranceDutyError.LimitExceeded, "ARC cycle late capacity refusal"

proc main() =
  ## Genuine execution and real erasure geometry remain independent of the trusted structural registration fixture's placeholder credentials.
  let tiny = computedAvailabilityAtCore(0, 1, 6)
  coordinates(tiny, 6, [4'u64, 5, 2])
  coordinates(computedAvailabilityAtCore(0, 1, 12), 12, [5'u64, 6, 3])
  coordinates(computedAvailabilityAtCore(0, 1, 1023), 1023, [343'u64, 344, 341])
  refuse(tiny)
  let saved = changed(tiny, 6)
  cycle(saved)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Complete-plan success and late capacity refusal must leave no retained decoded chapter or report owner.
    cycle(saved)
  let after = getOccupiedMem()
  assert before == after, "assurance duty ARC release"
  recordArcRelease("jamnp_assurance_duty", 1000, before, after)
  echo "JAMNP-S assurance duty passed"
main()
