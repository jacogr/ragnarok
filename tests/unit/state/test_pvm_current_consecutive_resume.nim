# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual disk restart resumes from the persisted current child, then retains every exact successor without replaying the first.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[current_download_command, services]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/report_owned
import ../../../src/storage/managed_manifest
import ../../support/[current_consecutive_context, current_consecutive_download_context,
  current_sequence_command_context, current_services_disk_samples, managed_storage_samples,
  block_download_transport]
const
  ChainPath = "pvm-current-consecutive-resume-chain"
  PolicyPath = "pvm-current-consecutive-resume-policy"

proc check(fixture: CurrentConsecutiveFixture, managed, local: bool) {.raises.} =
  ## A separate complete command/IO owner persists the prefix before a fresh command selects its actual retained head.
  var database = "pvm-current-consecutive-resume-state"
  defer:
    if managed: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString())
  var extra = @["--state-storage", "disk", "--state-db", database]
  if managed:
    extra.add("--state-layout")
    extra.add("managed")
    extra.add("--state-compact-bytes")
    extra.add("0") # Original history restart stays independent of physical maintenance ordering.
  let initial = exchangeCurrentSequence(fixture, 0, 1,
    @[currentConsecutiveResponse(fixture.children[0])], @[Healthy], currentConsecutivePolicy(),
    ChainPath, PolicyPath, "pvm-current-consecutive-resume", extra)
  assert initial.outcome.error == CurrentDownloadCommandResult.Adopted
  assert initial.outcome.adoptedBlocks == 1 and initial.secondRequests == 1
  if local: extra.add("--download-local-ancestors") # Only actual retained originals may be projected into the next command's lookup context.
  let resumed = exchangeCurrentSequence(fixture, 1, 2,
    @[currentConsecutiveResponse(fixture.children[1]), currentConsecutiveResponse(fixture.children[2])],
    @[Healthy, Healthy], currentConsecutivePolicy(), ChainPath, PolicyPath,
    "pvm-current-consecutive-resume", extra)
  assert resumed.outcome.error == CurrentDownloadCommandResult.Adopted
  assert resumed.outcome.requestedBlocks == 2 and resumed.outcome.adoptedBlocks == 2
  assert resumed.firstRequests == 0 and resumed.secondRequests == 2
  var reopened = default(Services)
  defer: reopened.close()
  assert reopened.start(currentDiskOptions(ChainPath, database, managed, 0), "resumed current strict history")
  let view = reopened.chainView
  assert view.retainedCount == 4 and view.finalizedBlock.error == GenesisError.Unavailable
  for index in 0..3:
    let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
    assert array[32, byte](actual.blockHash) == array[32, byte](fixture.heads[index].blockHash)
    equalCurrentDiskMap(actual.stateSnapshot, fixture.heads[index].stateSnapshot)
  reopened.close()

proc main() {.raises.} =
  ## Journal and managed layouts each qualify implicit selected-head restart and explicit retained-local ancestry.
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value)
  for managed in [false, true]:
    check(fixture, managed, false)
    check(fixture, managed, true)
try:
  main()
except:
  quit(2) # A repeated original request, native refusal or changed historical map cannot count as resumed progress.
echo "PVM current consecutive resume passed"
