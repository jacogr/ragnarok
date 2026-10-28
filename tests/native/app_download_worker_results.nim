# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Worker-specific failure extraction and input-owner destruction remain checked runtime contracts.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/app/block_download as app_block_download
import ../../src/app/block_input as app_block_input
import ../../src/app/services as app_services
import ../../src/app/options as app_options
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../support/app_candidate_context

proc main() {.raises.} =
  ## The positive case joins explicitly; invalid alternatives must fail before exposing data or retiring leased input.
  let mode = paramStr(1)
  if mode == "worker" or mode == "handoff":
    let reason = default(BlockDownloadFailure)
    if mode == "worker": discard reason.workerError # Defaults contain no actual worker admission refusal.
    else: discard reason.handoffError # Defaults contain no actual host enqueue refusal.
    return
  let raw = readFile("tests/fixtures/state-report.bin")
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet) # The native suite independently verifies these frozen report bytes.
  let context = fixture(decodeOwnedReport(bytes, 2).value)
  const path = "build/download-worker-guard-chain.json"
  writeFile(path, context.text)
  var owner = default(Services)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path, "--state-writes", "1000",
    "--state-write-bytes", "1000000"], options)
  assert owner.start(options, "guard")
  var download = default(BlockDownload) # This owner must guard destruction before its Services owner can retire.
  let admitted = download.begin(owner, [], BlockInputLimits(blockBytes: ByteLimit(1)),
      preparationLimits())
  assert admitted.error == BlockDownloadError.None
  assert download.append(admitted.value, [1'u8, 0, 0, 0, 255], true) == BlockDownloadError.None
  assert download.requestFinished(admitted.value) == BlockDownloadError.None
  assert download.beginPreparation(admitted.value, owner).error == BlockDownloadError.None
  if mode == "destroy": return # The raw owner's guard must fail before any nested input or captured history is destroyed.
  assert download.retirePreparation(admitted.value, owner)
  assert not owner.preparationActive
  owner.close() # Positive join ends worker/RPC ownership before either composite owner is destroyed.

try:
  main() # Raising file/startup errors cannot substitute for the required assertion diagnostic.
except:
  quit(2)
