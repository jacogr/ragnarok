# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated actual/default result reads must reject through the exact chapter-16 success
## contract.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
include ../../src/codec/state/outputs
let useDefault = paramStr(2) == "default"
let policy = OutputLogConfig(items: ElementLimit(1), maxBytes: ByteLimit(37))
let noItems = OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(37))
let noBytes = OutputLogConfig(items: ElementLimit(1), maxBytes: ByteLimit(0))
let huge = OutputLogConfig(items: ElementLimit(high(uint64)), maxBytes: ByteLimit(high(uint64)))
let values = [AccumulationOutput(service: ServiceIndex(1), commitment: default(OutputCommitment))]
let entry = outputLogEntry(values, policy)
assert entry.error == OutputLogError.None
let owner = decodeOutputLog(entry.value.value, policy).value.snapshot
let empty = decodeOutputLog([0'u8], policy).value.snapshot
var hugeCount = @[255'u8]
# A canonical uint64 maximum cannot authorize native fixed-record storage.
for i in 0..<8: hugeCount.add(255'u8)
case paramStr(1)
of "entry-items":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[StateEntry]) else: outputLogEntry(values, noItems)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LimitExceeded)
  discard parsed.value.value.len
of "entry-bytes":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[StateEntry]) else: outputLogEntry(values, noBytes)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LimitExceeded)
  discard parsed.value.value.len
of "owner":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[OutputLogRead]) else: decodeOutputLog([], policy)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.Truncated)
  discard parsed.value.snapshot
of "consumed":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[OutputLogRead]) else: decodeOutputLog([], policy)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.Truncated)
  discard parsed.value.consumed
of "decode-framing":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[OutputLogRead]) else: decodeOutputLog([128'u8,
      0], policy)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.NonCanonical)
  discard parsed.value.snapshot
of "decode-items":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[OutputLogRead]) else: decodeOutputLog([1'u8], noItems)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LimitExceeded)
  discard parsed.value.snapshot
of "decode-bytes":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[OutputLogRead]) else: decodeOutputLog([0'u8], noBytes)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LimitExceeded)
  discard parsed.value.snapshot
of "decode-overflow":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[OutputLogRead]) else: decodeOutputLog(
      hugeCount, huge)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LengthOverflow)
  discard parsed.value.snapshot
of "decode-tail":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[OutputLogRead]) else: decodeOutputLog([1'u8], policy)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.Truncated)
  discard parsed.value.snapshot
of "count-owner":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[int]) else: outputLogCount(default(OutputLogSnapshot))
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.InvalidOwner)
  discard parsed.value
of "at-owner":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[AccumulationOutput]) else: outputLogAt(
      default(OutputLogSnapshot), OutputLogIndex(0))
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.InvalidOwner)
  discard parsed.value.service
of "at-index":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[AccumulationOutput]) else: outputLogAt(owner,
      OutputLogIndex(high(uint64)))
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.InvalidIndex)
  discard parsed.value.service
of "at-empty":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[AccumulationOutput]) else: outputLogAt(empty,
      OutputLogIndex(0))
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.InvalidIndex)
  discard parsed.value.service
of "extent-items":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[int]) else: extent(1, 1, noItems)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LimitExceeded)
  discard parsed.value
of "extent-overflow":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[int]) else: extent(high(uint64), 9, huge)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LengthOverflow)
  discard parsed.value
of "extent-bytes":
  # Default and operation failures cannot authorize application payloads or extent proofs.
  let parsed = if useDefault: default(OutputLogResult[int]) else: extent(0, 1, noBytes)
  assert parsed.error == (if useDefault: OutputLogError.Uninitialized else: OutputLogError.LimitExceeded)
  discard parsed.value
else:
  # Unknown fixture cases are setup errors, never successful contract rejections.
  quit 2
