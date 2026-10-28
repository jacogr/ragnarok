# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current adoption/ancestry extraction and explicit Services-borrow retirement remain strict contracts, with an actual positive close control.
import std/cmdline
import std/syncio
import std/assertions
import ../../src/quic/current_block_download_loop as quic_current_block_download_loop
import ../../src/quic/current_block_download_stream as quic_current_block_download_stream
import ../../src/app/services as app_services
import ../../src/app/options as app_options
import ../../src/app/download_schedule as app_download_schedule
import ../../src/app/current_block_input as app_current_block_input
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../support/state_accumulation_current_chain_context
import ../support/state_current_application_context
proc lifecycle(mode: string) {.raises.} =
  ## Real independent current canonical startup distinguishes a forgotten close from default/unavailable configuration.
  let raw = readFile("tests/fixtures/state-report.bin")
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = currentChainFixture(decodeOwnedReport(wire, 2).value, available = true)
  writeFile("build/current-download-loop-guard-chain.json", context.currentApplicationText)
  var owner = default(Services)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "build/current-download-loop-guard-chain.json"], options)
  assert owner.start(options, "current close contract")
  defer: owner.close()
  var dispatcher = default(CurrentDownloadLoop)
  let policy = CurrentDownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(1)), input: CurrentBlockInputLimits(
        blockBytes: ByteLimit(1)),
    stream: CurrentDownloadStreamLimits(readBytes: ByteLimit(1), writeBytes: ByteLimit(1),
      timeout: CurrentDownloadTimeout(1)), attemptTimeout: CurrentDownloadAttemptTimeout(1))
  assert dispatcher.configure(owner, [DownloadPeerId(1)], [], policy, CurrentDownloadLoopTick(0)) ==
      CurrentDownloadLoopError.None
  if mode == "positive": dispatcher.close() # The same configured owner must succeed when its explicit borrow is retired.
let mode = paramStr(1)
if mode in ["unclosed", "positive"]:
  try: lifecycle(mode)
  except: quit(2) # Actual startup/fixture errors cannot satisfy the selected close diagnostic.
else:
  var dispatcher = default(CurrentDownloadLoop)
  case mode
  of "demand": discard dispatcher.ancestorDemand
  of "remaining": discard dispatcher.ancestorRemaining(CurrentDownloadLoopTick(0))
  else: discard dispatcher.adoption # No default dispatcher has a consumed canonical result.
