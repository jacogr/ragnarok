# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only chapter-16 ownership, preflight and arithmetic checks; no private runtime hooks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import ../../support/arc_evidence
import std/[assertions, syncio]
include ../../../src/codec/state_outputs

## Independent source pairs preserve descending/repeated services and all fixed commitment octets.
proc source(marker: byte): seq[AccumulationOutput] =
  var commitment = default(array[32, byte])
  commitment[0] = marker
  commitment[31] = 255
  @[AccumulationOutput(service: ServiceIndex(high(uint32)), commitment: OutputCommitment(
      commitment)),
    AccumulationOutput(service: ServiceIndex(1), commitment: OutputCommitment(commitment)),
    AccumulationOutput(service: ServiceIndex(1), commitment: OutputCommitment(commitment))]

## Capture an owner after caller source and wire are destroyed and leave their original scope.
proc escaped(marker: byte): OutputLogSnapshot =
  let policy = OutputLogConfig(items: ElementLimit(3), maxBytes: ByteLimit(109))
  var values = source(marker)
  let entry = outputLogEntry(values, policy)
  assert entry.error == OutputLogError.None
  # Encoded bytes must own copies of every original pair.
  for i in 0..<values.len: values[i] = default(AccumulationOutput)
  var wire = entry.value.value
  let parsed = decodeOutputLog(wire, policy)
  assert parsed.error == OutputLogError.None and parsed.value.consumed == 109
  result = parsed.value.snapshot
  # No retained coordinate or mutable caller array can supply later fields.
  for i in 0..<wire.len: wire[i] = 0

## A standalone extracted pair remains a value after its final parent owner retires.
proc escapedPair(): AccumulationOutput =
  let owner = escaped(61)
  outputLogAt(owner, OutputLogIndex(0)).value

## Retain, replace, copy and release all scopes, including late malformed and policy failures.
proc cycle() =
  var owner = escaped(17)
  let alias = owner
  owner = escaped(29)
  assert outputLogCount(alias).value == 3 and outputLogCount(owner).value == 3
  assert array[32, byte](outputLogAt(alias, OutputLogIndex(0)).value.commitment)[0] == 17
  assert array[32, byte](outputLogAt(owner, OutputLogIndex(0)).value.commitment)[0] == 29
  var pair = outputLogAt(alias, OutputLogIndex(0)).value
  pair.service = ServiceIndex(0)
  pair.commitment = default(OutputCommitment)
  assert uint32(outputLogAt(alias, OutputLogIndex(0)).value.service) == high(uint32)
  assert array[32, byte](outputLogAt(alias, OutputLogIndex(0)).value.commitment)[31] == 255
  assert uint32(outputLogAt(alias, OutputLogIndex(1)).value.service) == 1
  assert uint32(outputLogAt(alias, OutputLogIndex(2)).value.service) == 1
  owner = default(OutputLogSnapshot)
  assert outputLogCount(owner).error == OutputLogError.InvalidOwner
  assert outputLogCount(alias).value == 3
  assert outputLogAt(alias, OutputLogIndex(high(uint64))).error == OutputLogError.InvalidIndex
  let detached = escapedPair()
  assert uint32(detached.service) == high(uint32)
  assert array[32, byte](detached.commitment)[0] == 61
  let policy = OutputLogConfig(items: ElementLimit(3), maxBytes: ByteLimit(109))
  var wire = outputLogEntry(source(43), policy).value.value
  wire.setLen(wire.len-1)
  let beforeFailure = getOccupiedMem()
  assert decodeOutputLog(wire, policy).error == OutputLogError.Truncated
  assert beforeFailure == getOccupiedMem()
  let noBytes = OutputLogConfig(items: ElementLimit(3), maxBytes: ByteLimit(108))
  assert outputLogEntry(source(43), noBytes).error == OutputLogError.LimitExceeded
  assert decodeOutputLog([128'u8, 0], policy).error == OutputLogError.NonCanonical
  let empty = decodeOutputLog([0'u8], policy).value.snapshot
  assert outputLogCount(empty).value == 0
  assert outputLogAt(empty, OutputLogIndex(0)).error == OutputLogError.InvalidIndex

# Check representability before multiplication/addition without allocating announced payloads.
let huge = OutputLogConfig(items: ElementLimit(high(uint64)), maxBytes: ByteLimit(high(uint64)))
let maximum = uint64((high(int)-9) div 36)
let fit = extent(maximum, 9, huge)
assert fit.error == OutputLogError.None and fit.value == 9+int(maximum)*36
assert extent(maximum+1, 9, huge).error == OutputLogError.LengthOverflow
assert extent(high(uint64), 9, huge).error == OutputLogError.LengthOverflow
assert extent(0, 1, huge).value == 1
assert extent(1, 1, huge).value == 37
assert extent(0, 1, OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(0))).error ==
    OutputLogError.LimitExceeded
assert extent(1, 1, OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(high(
    uint64)))).error == OutputLogError.LimitExceeded
# Warm allocator bookkeeping and all owner/late-failure paths before the isolated comparison.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Every final reference, source and fixed copy retires when the workload scope returns.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_outputs_private", 1000, beforeRelease, afterRelease)
echo "OUTPUTS_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony chapter 16: retained/replaced owners, escaped fixed pairs and scoped ARC release passed"
