# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent failed/default result reads must hit their exact success precondition.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[cmdline, syncio]
import ../../src/codec/assurances

let useDefault = paramStr(2) == "default"
let config = AssuranceConfig(cores: CoreCount(2), validators: ValidatorCount(6))
let noRecords: seq[Assurance] = @[]
let noBytes: seq[byte] = @[]
var bytes = newSeq[byte](0)
var records = newSeq[Assurance](0)
let written = if useDefault: default(AssuranceWriteResult) else: encodeAssurances(noRecords, config, bytes)
let decoded = if useDefault: default(AssuranceDecodeResult) else: decodeAssurances(noBytes, config, records)
let scanned = if useDefault: default(AssuranceDecodeResult) else: inspectAssurances(noBytes, config)
case paramStr(1)
of "written":
  # An incomplete encode has no committed byte prefix.
  echo written.written
of "count":
  # Failed decode must not describe initialized output records.
  echo decoded.count
of "consumed":
  # Failed decode must not advance the caller's input cursor.
  echo decoded.consumed
of "inspect-count":
  # Inspection cannot manufacture a successful count from missing input.
  echo scanned.count
of "inspect-consumed":
  # Inspection has no consumed extent until its complete prefix validates.
  echo scanned.consumed
else:
  # Misspelled probe modes must not count as contract rejections.
  quit 2
