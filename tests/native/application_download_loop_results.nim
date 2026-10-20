# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default adoption extraction and forgotten explicit Services-borrow retirement remain strict runtime contracts.

import std/[cmdline, syncio, assertions]
import ../../src/quic/[block_download_loop, block_download_stream]
import ../../src/app/[services, options, download_schedule, block_input]
import ../../src/codec/[bounded, report_owned]
import ../support/application_candidate_context

proc lifecycle(mode: string) {.raises.} =
  ## Use real initialized canonical Services; explicit dispatcher close must precede its owner retirement.
  let raw = readFile("tests/fixtures/state-report.bin")
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet) # Preserve the independent frozen signed seed input.
  let context = fixture(decodeOwnedReport(wire, 2).value)
  writeFile("build/download-loop-guard-chain.json", context.text)
  var owner = default(Services)
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", "build/download-loop-guard-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  assert owner.start(options, "test")
  defer: owner.close()
  var dispatcher = default(BlockDownloadLoop)
  let policy = DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(1)),
    stream: DownloadStreamLimits(readBytes: ByteLimit(1), writeBytes: ByteLimit(1),
      timeout: DownloadTimeout(1)), attemptTimeout: DownloadAttemptTimeout(1))
  assert dispatcher.configure(owner, [DownloadPeerId(1)], [], policy, DownloadLoopTick(0)) ==
      DownloadLoopError.None
  if mode == "positive": dispatcher.close() # No caller may silently abandon even a configured endpoint-free borrow.

let mode = paramStr(1)
if mode in ["unclosed", "positive"]:
  try:
    lifecycle(mode) # File/seed failures cannot satisfy a contract rejection.
  except:
    quit(2)
else:
  var dispatcher = default(BlockDownloadLoop)
  discard dispatcher.adoption # Default owners have no actual consumed adoption result.
