# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime-selected misuse probes cover primitive success payloads and failure-only reasons.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import ../../src/codec/natural as codec_natural
import ../../src/codec/fixed_unsigned as codec_fixed_unsigned
import std/cmdline
import std/syncio
# Both default construction and actual failures must reject every success-only accessor.
let useDefault = paramStr(2) == "default"
let empty = newSeq[byte](0)
let naturalFailure = if useDefault: default(DecodeResult) else: decode(empty)
let fixedFailure = if useDefault: default(FixedDecodeResult) else: decodeFixed(empty, ByteWidth(1))
let encodeFailure = if useDefault: default(FixedEncodeResult) else: encodeFixed(
    FixedUnsigned(256), ByteWidth(1))
# Valid successes have no failure payload, including a valid zero-width fixed field.
let naturalSuccess = decode([byte(0)])
let fixedSuccess = decodeFixed(empty, ByteWidth(0))
let encodeSuccess = encodeFixed(FixedUnsigned(0), ByteWidth(0))
case paramStr(1)
of "natural-value":
  # Failure cannot masquerade as decoded zero.
  echo uint64(naturalFailure.value)
of "natural-consumed":
  # Failure cannot advance the natural prefix cursor.
  echo naturalFailure.consumed
of "fixed-value":
  # Failure is distinct from a valid zero-width value.
  echo uint64(fixedFailure.value)
of "fixed-consumed":
  # Failure cannot publish a fixed-field extent.
  echo fixedFailure.consumed
of "fixed-encoded":
  # A failed encode cannot expose default storage as a valid empty encoding.
  echo encodeFailure.encoded.len
of "natural-error":
  # Successful naturals cannot report a default truncated reason.
  echo ord(naturalSuccess.error)
of "fixed-decode-error":
  # Zero-width success cannot report a default InvalidWidth reason.
  echo ord(fixedSuccess.error)
of "fixed-encode-error":
  # Successful empty encoding has no failure reason to read.
  echo ord(encodeSuccess.error)
else:
  # Misspelled probe modes must not count as contract rejections.
  quit 2
