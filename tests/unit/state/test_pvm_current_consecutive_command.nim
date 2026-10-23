# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real authenticated current command downloads adopt two genuine successors and preserve one confirmed prefix on later resource refusal.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/current_download_command
import ../../../src/codec/[report_owned, bounded]
import ../../support/[current_consecutive_context, current_rotated_sequence_context,
  current_consecutive_download_context,
  current_download_command_context, block_download_transport]
const
  ChainPath = "pvm-current-consecutive-command-chain"
  PolicyPath = "pvm-current-consecutive-command-policy"

proc main() {.raises.} =
  ## An independent forked TLS responder verifies the exact original parent and actual adopted-child requests.
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Cleanup follows joined command workers and responder processes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  # Exercise the same real transport/lifecycle assertions before and after the signed slot12 rotation.
  for fixture in [currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value, 2),
      currentRotatedSequenceFixture(decodeOwnedReport(bytes, 2).value, 2)]:
    let responses = @[currentConsecutiveResponse(fixture.children[0]), currentConsecutiveResponse(
        fixture.children[1])]
    let completed = exchangeCurrentDownloads(fixture.seed, responses, @[Healthy, Healthy], 2,
      currentConsecutivePolicy(), ChainPath, PolicyPath, "pvm-current-consecutive-command")
    if completed.outcome.error != CurrentDownloadCommandResult.Adopted or
        completed.outcome.adoptedBlocks != 2:
      echo "two-child completion: " & $completed.outcome.error & " adopted=" &
          $completed.outcome.adoptedBlocks & " requests=" & $completed.secondRequests
    assert completed.outcome.error == CurrentDownloadCommandResult.Adopted
    assert completed.outcome.requestedBlocks == 2 and completed.outcome.adoptedBlocks == 2
    assert completed.firstRequests == 0 and completed.secondRequests == 2
    var short = currentConsecutivePolicy()
    short.candidate.completion.composition.recent.history.blocks = ElementLimit(
        2) # One original row plus child one fits; child two requires a third row.
    let refused = exchangeCurrentDownloads(fixture.seed, responses, @[Healthy, Healthy], 2,
      short, ChainPath, PolicyPath, "pvm-current-consecutive-command")
    if refused.outcome.error != CurrentDownloadCommandResult.Exhausted or
        refused.outcome.adoptedBlocks != 1:
      echo "two-child resource refusal: " & $refused.outcome.error & " adopted=" &
          $refused.outcome.adoptedBlocks & " requests=" & $refused.secondRequests
    assert refused.outcome.error == CurrentDownloadCommandResult.Exhausted
    assert refused.outcome.requestedBlocks == 2 and refused.outcome.adoptedBlocks == 1
    assert refused.firstRequests == 0 and refused.secondRequests ==
        2 # The explicit two-row history ceiling never silently widens for continuation.
try:
  main()
except:
  quit(2) # Native proof, actual execution, exact request or confirmed-progress errors defeat success.
echo "PVM current consecutive command passed"
