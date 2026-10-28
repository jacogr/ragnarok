# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Load the existing independently encoded report fixture for authenticated global chapter tests.
import std/assertions
import std/envvars
import std/syncio
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/owned as codec_owned
proc globalReport*(): OwnedReport {.raises.} =
  ## Fail setup explicitly if fixture transport/decoding is unavailable; no generated fallback is permitted.
  let path = getEnv("RAGNAROK_STATE_REPORT")
  assert path.len > 0
  let text = readFile(path)
  var bytes = newSeq[byte](text.len)
  for i in 0..<text.len:
    bytes[i] = byte(text[i]) # Preserve the independent reference's exact bytes.
  let decoded = decodeOwnedReport(bytes, 2)
  assert decoded.error == OwnershipError.None
  decoded.value
