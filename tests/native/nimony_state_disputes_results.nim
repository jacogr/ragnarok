# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and genuinely failed chapter-5 payload reads require the exact supported success
## contract.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
include ../../src/codec/state/disputes
let useDefault = paramStr(2) == "default"
let policy = DisputeStateConfig(perSet: ElementLimit(3), totalItems: ElementLimit(8),
    maxBytes: ByteLimit(300))
let tiny = DisputeStateConfig(perSet: ElementLimit(3), totalItems: ElementLimit(8),
    maxBytes: ByteLimit(1))
let huge = DisputeStateConfig(perSet: ElementLimit(high(uint64)), totalItems: ElementLimit(high(
    uint64)), maxBytes: ByteLimit(high(uint64)))
var word = default(array[32, byte])
word[0] = 17
var original = default(DisputeState)
original.reports[JudgmentSet.Good] = @[DisputeHash(word)]
original.offenders = @[OffenderKey(word)]
let encoded = disputeStateEntry(original, policy)
assert encoded.error == DisputeStateError.None
let owner = decodeDisputeState(encoded.value.value, policy).value.snapshot
var duplicate = original
duplicate.offenders = @[OffenderKey(word), OffenderKey(word)]
# Literal valid empty report sets followed by a duplicate offender pair fail in the final section.
var badOrder = @[0'u8, 0, 0, 2]
# Fixed zero identities are duplicate opaque values regardless of their cryptographic validity.
for i in 0..<64: badOrder.add(0'u8)
case paramStr(1)
of "entry-order":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[StateEntry]) else: disputeStateEntry(
      duplicate, policy)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.NonCanonical)
  discard parsed.value.value.len
of "entry-limit":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[StateEntry]) else: disputeStateEntry(
      original, tiny)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.LimitExceeded)
  discard parsed.value.value.len
of "owner":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[
      DisputeStateRead]) else: decodeDisputeState([], policy)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.Truncated)
  discard parsed.value.snapshot
of "consumed":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[
      DisputeStateRead]) else: decodeDisputeState([], policy)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.Truncated)
  discard parsed.value.consumed
of "decode-order":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[
      DisputeStateRead]) else: decodeDisputeState(badOrder, policy)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.NonCanonical)
  discard parsed.value.consumed
of "decode-framing":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[
      DisputeStateRead]) else: decodeDisputeState([0'u8, 0, 0, 128, 0], policy)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.NonCanonical)
  discard parsed.value.consumed
of "decode-limit":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[
      DisputeStateRead]) else: decodeDisputeState([0'u8, 0, 0, 4], policy)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.LimitExceeded)
  discard parsed.value.consumed
of "decode-overflow":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[
      DisputeStateRead]) else: decodeDisputeState([255'u8, 255, 255, 255, 255, 255, 255, 255, 255], huge)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.LengthOverflow)
  discard parsed.value.consumed
of "decode-bytes":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[
      DisputeStateRead]) else: decodeDisputeState(encoded.value.value, tiny)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.LimitExceeded)
  discard parsed.value.consumed
of "info":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[DisputeStateInfo]) else: disputeStateInfo(
      default(DisputeStateSnapshot))
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.InvalidOwner)
  discard parsed.value.offenders
of "report-owner":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[DisputeHash]) else: judgedReportAt(default(
      DisputeStateSnapshot), JudgmentSet.Good, DisputeStateIndex(0))
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.InvalidOwner)
  discard parsed.value
of "report-index":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[DisputeHash]) else: judgedReportAt(owner,
      JudgmentSet.Good, DisputeStateIndex(high(uint64)))
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.InvalidIndex)
  discard parsed.value
of "report-tag":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[DisputeHash]) else: judgedReportAt(owner,
      JudgmentSet(255), DisputeStateIndex(0))
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.InvalidTag)
  discard parsed.value
of "offender-owner":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[OffenderKey]) else: stateOffenderAt(
      default(DisputeStateSnapshot), DisputeStateIndex(0))
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.InvalidOwner)
  discard parsed.value
of "offender-index":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[OffenderKey]) else: stateOffenderAt(owner,
      DisputeStateIndex(high(uint64)))
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.InvalidIndex)
  discard parsed.value
of "layout":
  # Neither an uninitialized nor this actual failed operation may expose selected data or progress.
  let parsed = if useDefault: default(DisputeStateResult[Layout]) else: scan([0'u8, 0, 0], policy)
  assert parsed.error == (if useDefault: DisputeStateError.Uninitialized else: DisputeStateError.Truncated)
  discard parsed.value.consumed
else:
  # Unknown trusted modes must never masquerade as a successful guard rejection.
  assert false
