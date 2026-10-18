# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated actual/default public and internal payload reads require exact supported success contracts.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_statistics
let useDefault = paramStr(2) == "default"
let policy = ActivityConfig(cores: CoreCount(3), current: ValidatorCount(6),
    previous: ValidatorCount(9), maxServices: ElementLimit(2), maxBytes: ByteLimit(2000))
var invalid = policy
invalid.current = ValidatorCount(0)
var strict = policy
strict.maxServices = ElementLimit(1)
var tiny = policy
tiny.maxBytes = ByteLimit(1)
var huge = policy
huge.maxServices = ElementLimit(high(uint64))
huge.maxBytes = ByteLimit(high(uint64))
var original = default(ActivityState)
original.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
original.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](9)
original.cores = newSeq[CoreActivity](3)
original.services = @[ServiceStatisticsEntry(service: ServiceIndex(255)), ServiceStatisticsEntry(
    service: ServiceIndex(256))]
var wrongCurrent = original
wrongCurrent.validators[StatisticsEpoch.Current] = @[]
var wrongPrevious = original
wrongPrevious.validators[StatisticsEpoch.Previous] = @[]
var wrongCores = original
wrongCores.cores = @[]
var duplicate = original
# Replace the whole dictionary sequence so the original source remains canonical.
duplicate.services = @[ServiceStatisticsEntry(service: ServiceIndex(1)), ServiceStatisticsEntry(
    service: ServiceIndex(1))]
let encoded = activityStateEntry(original, policy)
assert encoded.error == ActivityError.None
let owner = decodeActivityState(encoded.value.value, policy).value.snapshot
# Literal roster counts and E4 zero counters precede three eight-natural all-zero core tuples.
proc prefix(): seq[byte] =
  result = @[6'u8]
  # Six validator records have exactly 24 bytes each.
  for i in 0..<6*24: result.add(0'u8)
  result.add(9'u8)
  # The previous roster population is independent of the current one.
  for i in 0..<9*24: result.add(0'u8)
  # Fixed core tuple arity has no core-array count and uses one-byte zero naturals here.
  for i in 0..<3*8: result.add(0'u8)
var excess = prefix()
excess.add(2'u8)
var overflow = prefix()
overflow.add(255'u8)
# An announced uint64 maximum cannot authorize a typed service-entry array.
for i in 0..<8: overflow.add(255'u8)
var disordered = prefix()
disordered.add(2'u8)
# Complete zero-key/eleven-natural records duplicate their numeric key, independently of truncation.
for i in 0..<2*(4+11): disordered.add(0'u8)
var tail = prefix()
tail.add(1'u8)
# A complete E4 key and ten zero fields precede an overlong final accumulation-gas scalar.
for i in 0..<4+10: tail.add(0'u8)
tail.add(128'u8)
tail.add(0'u8)
var cursor = 0
case paramStr(1)
of "entry-config":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[StateEntry]) else: activityStateEntry(original, invalid)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidConfig)
  discard parsed.value.value.len
of "entry-current":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[StateEntry]) else: activityStateEntry(
      wrongCurrent, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidCount)
  discard parsed.value.value.len
of "entry-previous":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[StateEntry]) else: activityStateEntry(
      wrongPrevious, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidCount)
  discard parsed.value.value.len
of "entry-cores":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[StateEntry]) else: activityStateEntry(
      wrongCores, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidCount)
  discard parsed.value.value.len
of "entry-policy":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[StateEntry]) else: activityStateEntry(original, strict)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.LimitExceeded)
  discard parsed.value.value.len
of "entry-order":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[StateEntry]) else: activityStateEntry(
      duplicate, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.NonCanonical)
  discard parsed.value.value.len
of "entry-bytes":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[StateEntry]) else: activityStateEntry(original, tiny)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.LimitExceeded)
  discard parsed.value.value.len
of "decode-config":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState([], invalid)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidConfig)
  discard parsed.value.consumed
of "decode-count":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState([
      0'u8], policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidCount)
  discard parsed.value.consumed
of "decode-framing":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState([
      128'u8, 0], policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.NonCanonical)
  discard parsed.value.consumed
of "decode-limit":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState(
      excess, strict)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.LimitExceeded)
  discard parsed.value.consumed
of "decode-overflow":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState(
      overflow, huge)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.LengthOverflow)
  discard parsed.value.consumed
of "decode-order":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState(
      disordered, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.NonCanonical)
  discard parsed.value.consumed
of "decode-tail":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState(tail, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.NonCanonical)
  discard parsed.value.consumed
of "decode-bytes":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState(
      encoded.value.value, tiny)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.LimitExceeded)
  discard parsed.value.consumed
of "owner":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState([], policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.Truncated)
  discard parsed.value.snapshot
of "consumed":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityRead]) else: decodeActivityState([], policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.Truncated)
  discard parsed.value.consumed
of "info":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ActivityInfo]) else: activityInfo(default(ActivitySnapshot))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidOwner)
  discard parsed.value.services
of "validator-owner":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ValidatorActivity]) else: validatorActivityAt(
      default(ActivitySnapshot), StatisticsEpoch.Current, StatisticsValidatorIndex(0))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidOwner)
  discard parsed.value
of "validator-index":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ValidatorActivity]) else: validatorActivityAt(
      owner, StatisticsEpoch.Current, StatisticsValidatorIndex(high(uint64)))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidIndex)
  discard parsed.value
of "validator-epoch":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[ValidatorActivity]) else: validatorActivityAt(
      owner, StatisticsEpoch(255), StatisticsValidatorIndex(0))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidTag)
  discard parsed.value
of "core-owner":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[CoreActivity]) else: coreActivityAt(default(
      ActivitySnapshot), StatisticsCoreIndex(0))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidOwner)
  discard parsed.value.gas
of "core-index":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[CoreActivity]) else: coreActivityAt(owner,
      StatisticsCoreIndex(high(uint64)))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidIndex)
  discard parsed.value.gas
of "service-owner":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[
      ServiceStatisticsEntry]) else: serviceActivityAt(default(ActivitySnapshot),
      StatisticsServiceIndex(0))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidOwner)
  discard parsed.value.service
of "service-index":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[
      ServiceStatisticsEntry]) else: serviceActivityAt(owner, StatisticsServiceIndex(high(uint64)))
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.InvalidIndex)
  discard parsed.value.service
of "natural":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[uint64]) else: readNatural([128'u8, 0], cursor, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.NonCanonical)
  discard parsed.value
of "key":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[uint32]) else: readService([0'u8], cursor, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.Truncated)
  discard parsed.value
of "core-fields":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[array[8, uint64]]) else: readFields[8]([0'u8],
      cursor, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.Truncated)
  discard parsed.value
of "service-fields":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[array[11, uint64]]) else: readFields[11]([
      0'u8], cursor, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.Truncated)
  discard parsed.value
of "layout-services":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[Layout]) else: scan(excess, strict)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.LimitExceeded)
  discard parsed.value.services
of "layout-consumed":
  # Neither uninitialized nor actual failed operations authorize this value or partial progress.
  let parsed = if useDefault: default(ActivityResult[Layout]) else: scan(tail, policy)
  assert parsed.error == (if useDefault: ActivityError.Uninitialized else: ActivityError.NonCanonical)
  discard parsed.value.consumed
else:
  # Unknown trusted modes must never count as expected contract failures.
  assert false
