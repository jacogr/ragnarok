# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated failed/default result and selected source/metadata/decoded-union accesses require
## their exact contracts.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[cmdline, syncio]
import ../../src/codec/[c2_records, bounded, composite, work_digest, work_report, assurances]
let useDefault = paramStr(2) == "default"
let policy = OperandLimits(outputBytes: ByteLimit(1024), authBytes: ByteLimit(1024),
    totalBlobBytes: ByteLimit(1024), maxBytes: ByteLimit(4096))
let config = AvailabilityConfig(cores: CoreCount(2), maxBytes: ByteLimit(104))
var output: seq[byte] = @[]
# Hand-authored empty tagged operands select each existing work-error alternative without source-encoder round trips.
proc errorInfo(kind: WorkKind): OperandInfo =
  var wire = newSeq[byte](132)
  wire[130] = byte(ord(kind))
  operandInfo(decodeOperand(wire, policy).value.owner).value
# A valid fixed transfer selects the opposite decoded branch without exposing a private discriminator.
proc decodedTransfer(): AccumulationValue =
  var wire = newSeq[byte](154)
  wire[0] = 1
  decodeAccumulationInput(wire, policy).value.value
case paramStr(1)
of "av-value":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[AvailabilityRead]) else: decodeAvailability([], config)
  echo uint16(parsed.value.value.erasureShards)
of "av-consumed":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[AvailabilityRead]) else: decodeAvailability([], config)
  echo parsed.value.consumed
of "transfer-value":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[TransferRead]) else: decodeTransfer([],
      ByteLimit(154))
  echo uint64(parsed.value.value.amount)
of "transfer-consumed":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[TransferRead]) else: decodeTransfer([],
      ByteLimit(154))
  echo parsed.value.consumed
of "operand-owner":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[OperandRead]) else: decodeOperand([], policy)
  echo ord(operandInfo(parsed.value.owner).error)
of "operand-consumed":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[OperandRead]) else: decodeOperand([], policy)
  echo parsed.value.consumed
of "info":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[OperandInfo]) else: operandInfo(default(OwnedOperand))
  echo parsed.value.consumed
of "union-value":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[AccumulationRead]) else: decodeAccumulationInput([], policy)
  echo ord(parsed.value.value.kind)
of "union-consumed":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[AccumulationRead]) else: decodeAccumulationInput([], policy)
  echo parsed.value.consumed
of "av-write":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[int]) else: encodeAvailability(default(
      AvailabilitySpec), config, output)
  echo parsed.value
of "transfer-write":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[int]) else: encodeTransfer(default(
      DeferredTransfer), ByteLimit(154), output)
  echo parsed.value
of "operand-write":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[int]) else: encodeOperand(default(
      AccumulationOperand), policy, output)
  echo parsed.value
of "union-write":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[int]) else: encodeAccumulationInput(default(
      AccumulationSource), policy, output)
  echo parsed.value
of "owned-write":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[int]) else: encodeOwnedOperand(default(
      OwnedOperand), policy, output)
  echo parsed.value
of "output-copy":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[int]) else: copyOperandOutput(default(
      OwnedOperand), output)
  echo parsed.value
of "trace-copy":
  # Failed/default operations cannot authorize a value, retained owner or progress.
  let parsed = if useDefault: default(RecordResult[int]) else: copyOperandTrace(default(
      OwnedOperand), output)
  echo parsed.value
of "outofgas-copy":
  # OutOfGas carries no success payload or metadata length.
  echo operandPayloadCopies(failedOperandOutput(WorkKind.OutOfGas)).len
of "outofgas-edit":
  # OutOfGas carries no success payload or metadata length.
  var value = failedOperandOutput(WorkKind.OutOfGas)
  echo editOperandPayload(value).len
of "outofgas-metadata":
  # OutOfGas carries no success payload or metadata length.
  echo errorInfo(WorkKind.OutOfGas).output.length
of "panic-copy":
  # Panic carries no success payload or metadata length.
  echo operandPayloadCopies(failedOperandOutput(WorkKind.Panic)).len
of "panic-edit":
  # Panic carries no success payload or metadata length.
  var value = failedOperandOutput(WorkKind.Panic)
  echo editOperandPayload(value).len
of "panic-metadata":
  # Panic carries no success payload or metadata length.
  echo errorInfo(WorkKind.Panic).output.length
of "badexports-copy":
  # BadExports carries no success payload or metadata length.
  echo operandPayloadCopies(failedOperandOutput(WorkKind.BadExports)).len
of "badexports-edit":
  # BadExports carries no success payload or metadata length.
  var value = failedOperandOutput(WorkKind.BadExports)
  echo editOperandPayload(value).len
of "badexports-metadata":
  # BadExports carries no success payload or metadata length.
  echo errorInfo(WorkKind.BadExports).output.length
of "oversize-copy":
  # Oversize carries no success payload or metadata length.
  echo operandPayloadCopies(failedOperandOutput(WorkKind.Oversize)).len
of "oversize-edit":
  # Oversize carries no success payload or metadata length.
  var value = failedOperandOutput(WorkKind.Oversize)
  echo editOperandPayload(value).len
of "oversize-metadata":
  # Oversize carries no success payload or metadata length.
  echo errorInfo(WorkKind.Oversize).output.length
of "bad-copy":
  # Bad carries no success payload or metadata length.
  echo operandPayloadCopies(failedOperandOutput(WorkKind.Bad)).len
of "bad-edit":
  # Bad carries no success payload or metadata length.
  var value = failedOperandOutput(WorkKind.Bad)
  echo editOperandPayload(value).len
of "bad-metadata":
  # Bad carries no success payload or metadata length.
  echo errorInfo(WorkKind.Bad).output.length
of "big-copy":
  # Big carries no success payload or metadata length.
  echo operandPayloadCopies(failedOperandOutput(WorkKind.Big)).len
of "big-edit":
  # Big carries no success payload or metadata length.
  var value = failedOperandOutput(WorkKind.Big)
  echo editOperandPayload(value).len
of "big-metadata":
  # Big carries no success payload or metadata length.
  echo errorInfo(WorkKind.Big).output.length
of "source-operand":
  # A selected alternative cannot authorize an inactive source or decoded branch.
  let source = default(DeferredTransfer)
  let value = transferSource(source)
  echo uint64(value.operand.gas)
of "source-transfer":
  # A selected alternative cannot authorize an inactive source or decoded branch.
  let source = default(AccumulationOperand)
  let value = operandSource(source)
  echo uint64(value.transfer.amount)
of "source-default-transfer":
  # A selected alternative cannot authorize an inactive source or decoded branch.
  let value = default(AccumulationSource)
  echo uint64(value.transfer.amount)
of "decoded-operand":
  # A selected alternative cannot authorize an inactive source or decoded branch.
  echo ord(operandInfo(decodedTransfer().operand).error)
of "decoded-transfer":
  # A selected alternative cannot authorize an inactive source or decoded branch.
  let value = default(AccumulationValue)
  echo uint64(value.transfer.amount)
of "factory":
  # A runtime-selected success tag is forbidden in the failure-only constructor.
  let kind = if paramStr(2) == "none": WorkKind.Success else: WorkKind.Panic
  echo ord(failedOperandOutput(kind).kind)
else:
  # Unknown trusted selectors are fixture errors.
  quit(2)
