# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Grouped real-process journal qualification covers bootstrap, first/following append and every actual short-write/durability boundary.
import std/[assertions, envvars, syncio]
import ../../support/[storage_io, storage_light_journal, storage_light_journal_crash]
proc main() {.raises.} =
  ## Completed controls first establish actual operation counts, then each witnessed successful boundary is killed independently.
  let fixture = lightFixture()
  var controls = 0
  var killed = 0
  var appendChunks = default(array[2, int])
  var bootstrapCounts = default(array[4, int])
  var appendIndex = 0
  var bootstrapIndex = 0
  for following in [false, true]:
    # First-frame and nonempty-prefix workloads exercise distinct replay/repair sequence authority.
    assert lightAppendCrash(fixture, following, writeIo, 4096) == 1, "one ordinary sparse write"
    assert lightAppendCrash(fixture, following, syncIo, 4096) == 1, "one ordinary sparse append barrier"
    discard lightAppendCrash(fixture, following, writeIo, 0)
    discard lightAppendCrash(fixture, following, syncIo, 0)
    let chunks = lightAppendCrash(fixture, following, writeIo, 4096, true)
    controls += 3
    killed += 2+int(chunks)
    appendChunks[appendIndex] = int(chunks)
    inc appendIndex
    assert chunks > 1 and chunks < 64, "bounded genuine append short-write control"
    for skip in 0..<int(chunks):
      # Each partial and final completed short chunk has its own exact stop/kill/reap and strict recovery witness.
      discard lightAppendCrash(fixture, following, writeIo, cint(skip), true)
  for operation in [writeIo, syncIo, renameIo, closeIo]:
    # Bootstrap includes namespace/LOCK/parent barriers and every snapshot/anchor/staging publication boundary.
    let count = lightBootstrapCrash(fixture, operation, 4096)
    inc controls
    killed += int(count)
    bootstrapCounts[bootstrapIndex] = int(count)
    inc bootstrapIndex
    assert count > 0 and count < 64, "bounded actual bootstrap operation family"
    for skip in 0..<int(count):
      discard lightBootstrapCrash(fixture, operation, cint(skip))
  let chunks = lightBootstrapCrash(fixture, writeIo, 4096, true)
  inc controls
  killed += int(chunks)
  assert chunks > 3 and chunks < 64, "bounded genuine bootstrap short-write control"
  for skip in 0..<int(chunks):
    # Global short-write positions are checked against exact independent extents of each bootstrap file.
    discard lightBootstrapCrash(fixture, writeIo, cint(skip), true)
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if directory.len > 0:
    # Retain actual completed control counts alongside strict exact-child verdicts without altering suite output.
    let data = "{\"controls\":" & $controls & ",\"killed_boundaries\":" & $killed &
      ",\"first_append_chunks\":" & $appendChunks[0] & ",\"following_append_chunks\":" &
          $appendChunks[1] &
      ",\"bootstrap_write\":" & $bootstrapCounts[0] & ",\"bootstrap_sync\":" & $bootstrapCounts[1] &
      ",\"bootstrap_rename\":" & $bootstrapCounts[2] & ",\"bootstrap_close\":" & $bootstrapCounts[3] &
      ",\"bootstrap_short_chunks\":" & $chunks & "}\n"
    writeFile(directory & "/storage_light_journal_crashes.json", data)

try:
  main()
except:
  quit(2)
echo "PASS light journal process crashes: every bootstrap and first/following append boundary, exact forensic bytes and explicit recovery"
