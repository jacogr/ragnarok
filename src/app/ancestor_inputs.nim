# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture bounded complete sealed headers from explicit regular files, preserving caller order.
## Structural decoding grants no ancestry/trust authority; report admission still checks every link.

import std/assertions
import ../codec/[bounded, header]
import ../lib/atomic_file

type
  AncestorInputError* {.pure.} = enum ## Refusal never exposes the successfully decoded prefix.
    Uninitialized, None, LimitExceeded, FileFailure, HeaderFailure, TrailingBytes
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
