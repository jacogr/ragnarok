# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture bounded sealed headers from explicit regular files or retained local parents, preserving exact order.
## Structural decoding grants no ancestry/trust authority; report admission still checks every link.

import std/assertions
import ../../codec/[bounded, header]
import ../../lib/atomic/file as atomic_file
import ../../chain/[genesis, provider]

type
  AncestorInputError* {.pure.} = enum ## Refusal never exposes the successfully decoded prefix.
    Uninitialized, None, LimitExceeded, FileFailure, HeaderFailure, TrailingBytes, InvalidHistory
  AncestorInputResult* = object ## Private alternatives separate complete captured inputs from exact child failures.
    case status: AncestorInputError
    of None:
      captured: seq[OwnedHeader]
    of FileFailure:
      fileReason: AtomicFileError
    of HeaderFailure:
      headerReason: HeaderError
    else:
      discard # Default, quota and trailing-byte refusals retain no headers.

func error*(outcome: AncestorInputResult): AncestorInputError =
  ## Inspect structural capture status without extracting headers.
  outcome.status
func fileError*(outcome: AncestorInputResult): AtomicFileError {.inline,
    requires: outcome.status == AncestorInputError.FileFailure.} =
  ## Inspect only a failed regular-file read, including its bounded-growth refusal.
  outcome.fileReason
func headerError*(outcome: AncestorInputResult): HeaderError {.inline,
    requires: outcome.status == AncestorInputError.HeaderFailure.} =
  ## Preserve the actual configured header decoder's failure.
  outcome.headerReason
proc headers*(outcome: AncestorInputResult): seq[OwnedHeader] {.requires:
    outcome.status == AncestorInputError.None.} =
  ## Return independent sequence storage retaining immutable sealed owners in supplied order.
  result = newSeq[OwnedHeader](outcome.captured.len)
  for index, owner in outcome.captured:
    result[index] = owner # Caller replacement cannot change captured inputs or another consumer.

proc loadAncestorInputs*(paths: openArray[string], config: HeaderConfig,
    count: ElementLimit, bytes: ByteLimit): AncestorInputResult =
  ## Bound all descriptors before file access and subtract actual bytes before each subsequent read.
  if uint64(paths.len) > uint64(count) or paths.len > high(int) div sizeof(OwnedHeader):
    return AncestorInputResult(status: AncestorInputError.LimitExceeded)
  var remaining = uint64(bytes)
  var captured: seq[OwnedHeader] = @[]
  for path in paths:
    # The shared reader requires a regular file, reads through EOF and detects one excess byte.
    let input = readBoundedFile(path, ByteLimit(min(remaining, uint64(config.maxBytes))))
    if input.error != AtomicFileError.None:
      return AncestorInputResult(status: AncestorInputError.FileFailure, fileReason: input.error)
    let wire = input.value
    let decoded = decodeHeader(wire, config)
    if decoded.error != HeaderError.None:
      return AncestorInputResult(status: AncestorInputError.HeaderFailure,
          headerReason: decoded.error)
    if decoded.value.consumed != wire.len:
      return AncestorInputResult(status: AncestorInputError.TrailingBytes)
    remaining -= uint64(wire.len) # Reader success proves subtraction and the aggregate capture bound.
    captured.add(decoded.value.owner)
  AncestorInputResult(status: AncestorInputError.None, captured: captured)

proc prependLocalAncestors*(view: ChainView, older: seq[OwnedHeader], config: HeaderConfig,
    count: ElementLimit, bytes: ByteLimit): AncestorInputResult =
  ## Capture the bounded header-only parent suffix before explicit older inputs; never search separated finality or truncate to fit.
  let retained = view.validationHeaderCount
  if retained == 0 or retained > ValidationHeaderCapacity:
    return AncestorInputResult(status: AncestorInputError.InvalidHistory)
  let local = retained - 1 # The selected head is already supplied independently to report admission.
  if uint64(local) > uint64(count) or uint64(older.len) > uint64(count) - uint64(local) or
      older.len > high(int) div sizeof(OwnedHeader) - local:
    return AncestorInputResult(status: AncestorInputError.LimitExceeded)
  var captured = newSeq[OwnedHeader](local + older.len)
  var remaining = uint64(bytes)
  var child = view.validationHeaderAt(ValidationHeaderIndex(retained-1))
  for index in 0..<captured.len:
    # Only validation-header ordinals participate: an evicted finalized owner cannot bridge a missing parent.
    var owner = default(OwnedHeader)
    if index < local:
      let parent = view.validationHeaderAt(ValidationHeaderIndex(retained - 2 - index))
      if array[32, byte](child.parent) != array[32, byte](parent.hash) or parent.slot >= child.slot:
        return AncestorInputResult(status: AncestorInputError.InvalidHistory)
      owner = parent.header
      child = parent
    else:
      owner = older[index - local] # Explicit suffix linkage remains the ordinary report validator's responsibility.
    let info = owner.headerInfo
    if info.error != HeaderError.None:
      return AncestorInputResult(status: AncestorInputError.HeaderFailure, headerReason: info.error)
    let size = uint64(info.value.consumed)
    if size > uint64(config.maxBytes) or size > remaining:
      return AncestorInputResult(status: AncestorInputError.LimitExceeded)
    remaining -= size # Actual sealed bytes consume one shared budget before exposing any prefix.
    captured[index] = owner
  AncestorInputResult(status: AncestorInputError.None, captured: captured)
