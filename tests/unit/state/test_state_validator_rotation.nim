# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pinned roster projections plus authored nulling, epoch, budget and immutable lifetime
## contracts.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "validator_rotation_arc_release"}

import std/assertions
import std/envvars
import std/parseutils
import std/strutils
import std/syncio
import ../../support/codec_validator_rotation_fixture
import ../../support/testing_arc_evidence
import ../../../src/state/validators as state_validators

## Decode trusted exact hexadecimal fixture bytes without using a production protocol parser.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet = 0'u8
    assert parseHex(text[2*i..2*i+1], octet) == 2 # Complete octets only.
    result[i] = octet

## Parse complete unsigned fixture values before any checked native/slot narrowing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Share a finite offender policy with an explicit per-chain roster configuration.
proc config(cores = 341): ValidatorRotationConfig =
  ValidatorRotationConfig(roster: rotationRosterConfig(cores), offenders: ElementLimit(1023))

## Exact upstream posterior rosters are the oracle; fixture pooling never deduplicates protocol records.
proc published(text: string) =
  let lines = text.splitLines()
  let count = int(number(lines[0]))
  assert count > 0 and count < 100 and lines.len == count+18
  var owners = newSeq[ValidatorStateSnapshot](count)
  var wire = newSeq[seq[byte]](count)
  for i in 0..<count:
    wire[i] = unhex(lines[i+1]) # Copy complete pooled byte strings unchanged.
    let decoded = decodeStateValidators(wire[i], rotationRosterConfig())
    assert decoded.error == StateComponentError.None and decoded.value.consumed == wire[i].len
    owners[i] = decoded.value.value
  for i in 0..<16:
    let fields = lines[count+1+i].splitWhitespace()
    assert fields.len == 15
    let epoch = EpochSlots(number(fields[1]))
    assert number(fields[2]) <= uint64(high(uint32)) and number(fields[3]) <= uint64(high(uint32))
    let prior = StateTime(uint32(number(fields[2])))
    let target = StateTime(uint32(number(fields[3])))
    let raw = if fields[5] == "-": newSeq[byte](0) else: unhex(fields[5])
    assert raw.len mod 32 == 0
    var offenders = newSeq[OffenderKey](raw.len div 32)
    for j in 0..<offenders.len:
      var identity = default(array[32, byte])
      for k in 0..<32: identity[k] = raw[j*32+k] # Bind the whole original Ed25519 identity.
      offenders[j] = OffenderKey(identity)
    var ids = default(array[7, int])
    for j in 0..<7:
      let id = number(fields[6+j])
      assert id < uint64(count)
      ids[j] = int(id)
    let planned = planValidatorRotation(owners[ids[0]], owners[ids[1]], owners[ids[2]], owners[ids[
        3]], prior, target, epoch, offenders, config(int(number(fields[0]))))
    if fields[4] == "0":
      assert planned.error == ValidatorRotationError.InvalidSlot # Equal-slot rejection returns no plan.
    else:
      assert fields[4] == "1" and planned.error == ValidatorRotationError.None
      let expectedChange = uint64(uint32(target)) div uint64(epoch) > uint64(uint32(
          prior)) div uint64(epoch)
      assert planned.value.epochChanged == expectedChange
      assert rotationBytes(planned.value.pending) == wire[ids[4]]
      assert rotationBytes(planned.value.active) == wire[ids[5]]
      assert rotationBytes(planned.value.previous) == wire[ids[6]]
    for j in 0..<4:
      assert rotationBytes(owners[ids[j]]) == wire[ids[
          j]] # Neither filtering nor rotation mutates any retained input.

## Plans returned from callee-local owners stay alive, with full-record nulling and immutable extraction.
proc scoped(): ValidatorRotation =
  var staging = rotationRecords(6, 9)
  let pending = rotationOwner(rotationRecords(9, 10))
  let active = rotationOwner(rotationRecords(6, 11))
  let previous = rotationOwner(rotationRecords(6, 12))
  let first = OffenderKey(array[32, byte](staging[0].ed25519))
  let last = OffenderKey(array[32, byte](staging[5].ed25519))
  let owner = rotationOwner(staging)
  let before = rotationBytes(owner)
  let planned = planValidatorRotation(owner, pending, active, previous, StateTime(11), StateTime(
      12), EpochSlots(12), @[first, last], config())
  assert planned.error == ValidatorRotationError.None and planned.value.epochChanged
  let actual = planned.value
  assert validatorCount(actual.pending).value == 6 and validatorCount(actual.active).value == 9
  assert rotationBytes(actual.active) == rotationBytes(pending)
  assert rotationBytes(actual.previous) == rotationBytes(active)
  let bytes = rotationBytes(actual.pending)
  for index in [0, 5]:
    for j in 0..<336:
      assert bytes[1+index*336+j] == (if j == 32: 2'u8 else: 0'u8) # Current nullvalkey has exactly one nonzero byte in its Ed25519 field.
  for index in 1..<5:
    for j in 0..<336:
      assert bytes[1+index*336+j] == before[1+index*336+j] # Non-offenders keep their exact full record.
  staging[0] = default(StateValidator)
  var copied = validatorAt(actual.pending, StateValidatorIndex(1)).value
  copied.metadata = StateValidatorMetadata(default(array[128, byte]))
  assert rotationBytes(actual.pending) == bytes # Source/extracted-copy mutation cannot change a completed owner.
  assert rotationBytes(owner) == before
  actual

## Explicit canonical offender, source population, profile and slot limits apply before output construction.
proc boundaries() =
  let rows = rotationRecords(6, 7)
  let owner = rotationOwner(rows)
  let key = OffenderKey(array[32, byte](rows[0].ed25519))
  let later = OffenderKey(array[32, byte](rows[5].ed25519))
  let before = rotationBytes(owner)
  let same = planValidatorRotation(owner, owner, owner, owner, StateTime(1), StateTime(11),
      EpochSlots(12), @[key], config())
  assert same.error == ValidatorRotationError.None and not same.value.epochChanged
  assert rotationBytes(same.value.pending) == before # Offenders only null incoming staging on an epoch crossing.
  for epoch in [1'u64, 12, 600, high(uint64)]:
    let planned = planValidatorRotation(owner, owner, owner, owner, StateTime(0), StateTime(high(
        uint32)), EpochSlots(epoch), [], config())
    assert planned.error == ValidatorRotationError.None
    assert planned.value.epochChanged == (uint64(high(uint32)) div epoch >
        0) # No slot arithmetic overflow or repeated skips.
  for offenders in [@[key, key], @[later, key]]:
    assert planValidatorRotation(owner, owner, owner, owner, StateTime(0), StateTime(1), EpochSlots(
        12),

offenders, config()).error == ValidatorRotationError.NonCanonical # Duplicate or descending identities reject.
  var limited = config()
  limited.offenders = ElementLimit(0)
  assert planValidatorRotation(owner, owner, owner, owner, StateTime(0), StateTime(1), EpochSlots(
      12), @[key], limited).error == ValidatorRotationError.LimitExceeded
  limited = config()
  limited.roster.maxBytes = ByteLimit(2016)
  assert planValidatorRotation(owner, owner, owner, owner, StateTime(0), StateTime(1), EpochSlots(
      12),

[], limited).error == ValidatorRotationError.LimitExceeded # Count framing makes six records 2017 bytes.
  limited.roster.maxBytes = ByteLimit(2017)
  assert planValidatorRotation(owner, owner, owner, owner, StateTime(0), StateTime(12), EpochSlots(
      12), [], limited).error == ValidatorRotationError.None
  let larger = rotationOwner(rotationRecords(9, 8))
  assert planValidatorRotation(owner, owner, larger, owner, StateTime(0), StateTime(1), EpochSlots(
      12),

[], config(2)).error == ValidatorRotationError.InvalidState # Every input population must fit the selected profile.
  assert planValidatorRotation(default(ValidatorStateSnapshot), owner, owner, owner, StateTime(0),
      StateTime(1), EpochSlots(12), [], config()).error == ValidatorRotationError.InvalidState
  assert planValidatorRotation(owner, owner, owner, owner, StateTime(1), StateTime(1), EpochSlots(
      12), [], config()).error == ValidatorRotationError.InvalidSlot
  assert planValidatorRotation(owner, owner, owner, owner, StateTime(high(uint32)), StateTime(0),
      EpochSlots(12), [], config()).error == ValidatorRotationError.InvalidSlot
  assert planValidatorRotation(owner, owner, owner, owner, StateTime(0), StateTime(1), EpochSlots(
      0), [], config()).error == ValidatorRotationError.InvalidConfig
  let retained = scoped()
  assert validatorCount(retained.pending).value == 6 and validatorCount(retained.active).value == 9

try:
  published(readFile(getEnv("RAGNAROK_VALIDATOR_STF"))) # Missing fixture transport is an explicit harness failure.
except:
  quit(2) # No omitted published cases may silently pass.
boundaries()
for i in 0..<25: discard scoped() # Warm allocator paths before measuring retained ownership.
let before = getOccupiedMem()
for i in 0..<1000: discard scoped() # Retire all callee-local input/output/failed-source owners each cycle.
let after = getOccupiedMem()
assert before == after
recordArcRelease("state_validator_rotation", 1000, before, after)
echo "PASS validator rotation planning: sixteen published projections, offender nulling, bounds and ARC ownership"
