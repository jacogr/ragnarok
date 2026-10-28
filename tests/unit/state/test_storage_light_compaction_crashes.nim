# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Grouped replacement/cleanup qualification kills every actual observed IO boundary and checks explicit retry.
import std/assertions
import std/envvars
import std/syncio
import ../../support/storage_io
import ../../support/storage_light_journal
import ../../support/storage_light_compaction_crash
proc main() {.raises.} =
  ## Completed controls discover bounded operation counts; each real successful boundary has its own exact-child kill.
  let fixture = lightFixture()
  var controls = 0
  var killed = 0
  var counts = ""
  for action in [ReplaceCheckpoint, RetirePrevious, DiscardCandidate]:
    for operation in [writeIo, syncIo, renameIo, unlinkIo, closeIo]:
      # Observe only operation families used by this transition; unchanged families receive no artificial quota cases.
      if action == ReplaceCheckpoint and operation == unlinkIo: continue
      if action != ReplaceCheckpoint and (operation == writeIo or operation == renameIo): continue
      let count = lightReplacementCrash(fixture, action, operation, 4096)
      inc controls
      killed += int(count)
      assert count > 0 and count < 128, "bounded actual operation count"
      counts &= $action & ":" & $operation & "=" & $count & "\n"
      for skip in 0..<int(count):
        discard lightReplacementCrash(fixture, action, operation, cint(skip))
  let chunks = lightReplacementCrash(fixture, ReplaceCheckpoint, writeIo, 4096, true)
  inc controls
  killed += int(chunks)
  assert chunks > 3 and chunks < 128, "genuine short compaction writes"
  for skip in 0..<int(chunks):
    discard lightReplacementCrash(fixture, ReplaceCheckpoint, writeIo, cint(skip), true)
  let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
  if evidence.len > 0:
    # Preserve actual controls and exact killed boundary counts without changing stable suite output.
    writeFile(evidence & "/storage_light_compaction_crashes.txt", counts & "short_chunks=" &
      $chunks & "\ncontrols=" & $controls & "\nkilled=" & $killed & "\n")
try:
  main()
except:
  quit(2)
echo "PASS light replacement process crashes: compaction and cleanup boundaries, exact selection and explicit retry"
