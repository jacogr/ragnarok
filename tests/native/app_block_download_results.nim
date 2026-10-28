# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict default/refused result, selected failure and receiver-phase contracts preserve success-only extraction.

import std/cmdline
import std/syncio
import ../../src/app/block_download as app_block_download
import ../../src/app/block_input as app_block_input
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../support/app_candidate_context

let argument = paramStr(1)
var download = default(BlockDownload)
var missing = default(ApplicationChain)
let outcome = if argument == "default": default(BlockDownloadResult[BlockDownloadId])
  else: download.begin(missing, [], default(BlockInputLimits), default(ApplicationCandidateLimits))
case argument
of "owner": discard download.failure # Idle/default reception contains no retained selected failure.
of "input": discard outcome.failure.inputError # Missing head is not a raw-input admission failure.
of "preparation": discard outcome.failure.preparationFailure # Missing head contains no failed execution prefix.
of "success-reason":
  try:
    let raw = readFile("tests/fixtures/state-report.bin")
    var wire = newSeq[byte](raw.len)
    for index, octet in raw: wire[index] = byte(octet) # Positive construction uses the frozen signed-block source.
    let context = fixture(decodeOwnedReport(wire, 2).value)
    let admitted = download.begin(initialized(context), [],
      BlockInputLimits(blockBytes: ByteLimit(100000)), preparationLimits())
    discard admitted.failure # Genuine success has no failure alternative to inspect.
  except:
    quit(2) # Filesystem refusal cannot satisfy the selected contract diagnostic.
else:
  discard outcome.value # Neither default nor missing-head admission authorizes a generation.
