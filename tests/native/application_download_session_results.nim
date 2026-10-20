# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/selected results and nested alternatives retain strict runtime contracts with genuine success controls.

import std/[cmdline, syncio, assertions]
import ../../src/quic/block_download_session
import ../../src/app/[services, options, download_schedule, block_input, candidate]
import ../../src/codec/[bounded, report_owned]
import ../support/application_candidate_context

proc admitted(): DownloadSessionResult[DownloadSessionAttempt] {.raises.} =
  ## Construct real admission from the frozen signed seed; no native callback or fabricated result is needed.
  let raw = readFile("tests/fixtures/state-report.bin")
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet) # Independent frozen report bytes feed the established fixture.
  let context = fixture(decodeOwnedReport(wire, 2).value)
  writeFile("build/download-session-guard-chain.json", context.text)
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain",
    "build/download-session-guard-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "test")
  defer: owner.close()
  var session = default(BlockDownloadSession)
  assert session.configure([DownloadPeerId(1)], DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(1)), DownloadScheduleTick(0)) ==
        DownloadScheduleError.None
  result = session.begin(owner, [], BlockInputLimits(blockBytes: ByteLimit(100000)),
    preparationLimits(), DownloadScheduleTick(0))
  assert result.error == DownloadSessionError.None

let mode = paramStr(1)
let outcome = default(DownloadSessionResult[bool])
case mode
of "schedule": discard outcome.failure.scheduleError # Default failure is not a selected scheduler refusal.
of "download": discard outcome.failure.downloadFailure # Default failure has no receiver/preparation owner.
of "stream": discard outcome.failure.streamError # Default failure has no native binding refusal.
of "positive", "success-reason":
  try:
    let good = admitted()
    if mode == "positive": discard good.value.peer # A genuine detached successful token remains usable.
    else: discard good.failure # Actual success must reject failure extraction.
  except:
    quit(2) # Fixture/filesystem refusal cannot satisfy an assertion-contract diagnostic.
else: discard outcome.value # Default extraction refuses at runtime, never yields a successful prefix.
