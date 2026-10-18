# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated public/private result failures and runtime-selected absent fields need exact
## contracts.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../../src/codec/[report_owned, owned]
include ../../src/codec/state_availability
var fixture: seq[byte] = @[]
# Independent fixture bytes are trusted setup, not expected answers derived from the parent decoder.
try:
  let text = readFile(paramStr(3))
  fixture = newSeq[byte](text.len)
  # Copy explicit octets to avoid string/sequence representation assumptions.
  for i in 0..<text.len: fixture[i] = byte(text[i])
except:
  # Missing fixture setup must not count as an expected contract rejection.
  quit 2
let useDefault = paramStr(2) == "default"
let policy = AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2),
    validators: ValidatorCount(6), maxBytes: ByteLimit(2000000)), maxPresent: ElementLimit(2),
    maxBytes: ByteLimit(4000000))
var invalid = policy
invalid.guarantee.cores = CoreCount(0)
var tiny = policy
tiny.maxBytes = ByteLimit(2)
var none = policy
none.maxPresent = ElementLimit(0)
let report = decodeOwnedReport(fixture, 2)
assert report.error == OwnershipError.None
var child = Guarantee(report: report.value, slot: GuaranteeSlot(255), credentialCount: 2)
child.credentials[1].validator = GuarantorIndex(1)
let original = @[presentAssignment(child, AssignmentSlot(0x01020304)), absentAssignment()]
let encoded = availabilityStateEntry(original, policy)
assert encoded.error == AvailabilityError.None
let owner = decodeAvailabilityState(encoded.value.value, policy).value.snapshot
var missingChild = child
missingChild.report = default(OwnedReport)
let missing = @[presentAssignment(missingChild, AssignmentSlot(0)), absentAssignment()]
var shortChild = child
shortChild.credentialCount = 1
let shortCredentials = @[presentAssignment(shortChild, AssignmentSlot(0)), absentAssignment()]
var wrongChild = child
wrongChild.credentials[0].validator = GuarantorIndex(6)
let badValidator = @[presentAssignment(wrongChild, AssignmentSlot(0)), absentAssignment()]
# Author hostile children at independent fixture-based byte positions, not production scan offsets.
proc broken(kind: string, reportBytes: int): seq[byte] =
  let wire = encoded.value.value
  result = newSeq[byte](wire.len)
  # Preserve each full field before changing the selected hostile discriminator/index/count.
  for i in 0..<wire.len: result[i] = wire[i]
  if kind == "late":
    # The final absent core becomes a reserved tag after a complete valid first child.
    result[result.len-1] = 2
  elif kind == "credential":
    # The independent report width precedes the child's E4 evaluation slot and canonical credential count.
    result[1+reportBytes+4] = 1
  else:
    # The first E2 index is outside the configured six-validator population.
    result[1+reportBytes+5] = 6
let late = broken("late", fixture.len)
let credential = broken("credential", fixture.len)
let validator = broken("validator", fixture.len)
var framing: seq[byte] = @[]
# Replace the canonical child count with a complete overlong zero, retaining later bytes for precedence checks.
for i in 0..<1+fixture.len+4: framing.add(encoded.value.value[i])
framing.add(128'u8)
framing.add(0'u8)
# This is a framing failure, independently of the trailing old credential bytes.
for i in 1+fixture.len+5..<encoded.value.value.len: framing.add(encoded.value.value[i])
var timestamp = newSeq[byte](encoded.value.value.len-3)
# Drop registration bytes and the second tag, leaving a partial mandatory E4 field.
for i in 0..<timestamp.len: timestamp[i] = encoded.value.value[i]
case paramStr(1)
of "entry-config":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[StateEntry]) else: availabilityStateEntry(
      original, invalid)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidConfig)
  discard parsed.value.value.len
of "entry-count":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[StateEntry]) else: availabilityStateEntry([], policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidCount)
  discard parsed.value.value.len
of "entry-bytes":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[StateEntry]) else: availabilityStateEntry(
      original, tiny)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.LimitExceeded)
  discard parsed.value.value.len
of "entry-present":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[StateEntry]) else: availabilityStateEntry(
      original, none)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.LimitExceeded)
  discard parsed.value.value.len
of "entry-report":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[StateEntry]) else: availabilityStateEntry(
      missing, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidReport)
  discard parsed.value.value.len
of "entry-credential":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[StateEntry]) else: availabilityStateEntry(
      shortCredentials, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidCredential)
  discard parsed.value.value.len
of "entry-validator":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[StateEntry]) else: availabilityStateEntry(
      badValidator, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidValidator)
  discard parsed.value.value.len
of "owner":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState([], policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.Truncated)
  discard parsed.value.snapshot
of "consumed":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState([], policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.Truncated)
  discard parsed.value.consumed
of "decode-config":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState([], invalid)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidConfig)
  discard parsed.value.consumed
of "decode-tag":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState([2'u8], policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidTag)
  discard parsed.value.consumed
of "decode-late":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState(late, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidTag)
  discard parsed.value.consumed
of "decode-credential":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState(credential, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidCredential)
  discard parsed.value.consumed
of "decode-validator":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState(validator, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidValidator)
  discard parsed.value.consumed
of "decode-framing":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState(framing, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.NonCanonical)
  discard parsed.value.consumed
of "decode-present":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState(encoded.value.value, none)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.LimitExceeded)
  discard parsed.value.consumed
of "decode-bytes":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState(encoded.value.value, tiny)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.LimitExceeded)
  discard parsed.value.consumed
of "decode-timestamp":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityRead]) else: decodeAvailabilityState(timestamp, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.Truncated)
  discard parsed.value.consumed
of "info":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[AvailabilityInfo]) else: availabilityInfo(
      default(AvailabilitySnapshot))
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidOwner)
  discard parsed.value.present
of "at-owner":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityAssignment]) else: availabilityAt(default(AvailabilitySnapshot),
      AssignmentCoreIndex(0))
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidOwner)
  discard parsed.value.present
of "at-index":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[
      AvailabilityAssignment]) else: availabilityAt(owner, AssignmentCoreIndex(high(uint64)))
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidIndex)
  discard parsed.value.present
of "layout-consumed":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[Layout]) else: scan([0'u8], policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.Truncated)
  discard parsed.value.consumed
of "layout-present":
  # Neither defaults nor these actual failed operations authorize payloads or progress.
  let parsed = if useDefault: default(AvailabilityResult[Layout]) else: scan(late, policy)
  assert parsed.error == (if useDefault: AvailabilityError.Uninitialized else: AvailabilityError.InvalidTag)
  discard parsed.value.present
of "absent-guarantee":
  # Dynamic default/source/decoded absence must reject this inactive field separately.
  let assignment = if paramStr(2) == "default": default(AvailabilityAssignment)
    elif paramStr(2) == "source": absentAssignment()
    else: availabilityAt(owner, AssignmentCoreIndex(1)).value
  discard assignment.guarantee
of "absent-registered":
  # Dynamic default/source/decoded absence must reject this inactive field separately.
  let assignment = if paramStr(2) == "default": default(AvailabilityAssignment)
    elif paramStr(2) == "source": absentAssignment()
    else: availabilityAt(owner, AssignmentCoreIndex(1)).value
  discard assignment.registered
else:
  # Unknown trusted modes cannot masquerade as successful guard rejections.
  assert false
