# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated actual/default account result reads require the exact success precondition.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_accounts
let useDefault = paramStr(2) == "default"
let late = newSeq[byte](88)
case paramStr(1)
of "entry-bytes":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[StateEntry]) else: serviceMetadataEntry(
      ServiceIndex(0), default(ServiceMetadata), ByteLimit(88))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.LimitExceeded)
  discard parsed.value.value.len
of "metadata":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[
      ServiceMetadataRead]) else: decodeServiceMetadata([], ByteLimit(89))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.Truncated)
  discard parsed.value.metadata.balance
of "consumed":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[
      ServiceMetadataRead]) else: decodeServiceMetadata([], ByteLimit(89))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.Truncated)
  discard parsed.value.consumed
of "decode-policy":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[
      ServiceMetadataRead]) else: decodeServiceMetadata([], ByteLimit(88))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.LimitExceeded)
  discard parsed.value.metadata
of "decode-framing":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[
      ServiceMetadataRead]) else: decodeServiceMetadata([128'u8, 0], ByteLimit(89))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.NonCanonical)
  discard parsed.value.metadata
of "decode-version":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[
      ServiceMetadataRead]) else: decodeServiceMetadata([1'u8], ByteLimit(89))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.UnsupportedVersion)
  discard parsed.value.metadata
of "decode-version-truncated":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[
      ServiceMetadataRead]) else: decodeServiceMetadata([128'u8], ByteLimit(89))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.Truncated)
  discard parsed.value.metadata
of "decode-tail":
  # Neither a default nor an actual failed operation may fabricate application metadata or progress.
  let parsed = if useDefault: default(ServiceMetadataResult[
      ServiceMetadataRead]) else: decodeServiceMetadata(late, ByteLimit(89))
  assert parsed.error == (if useDefault: ServiceMetadataError.Uninitialized else: ServiceMetadataError.Truncated)
  discard parsed.value.metadata
else:
  # Unknown fixture cases fail setup rather than being counted as contract rejections.
  quit 2
