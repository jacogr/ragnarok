# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent authenticated fallback is rearmed for every actual successor; insufficient attempts retain the exact original head.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[current_download_command, services]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, bounded]
import ../../../src/storage/managed_manifest
import ../../support/[current_consecutive_context, current_consecutive_download_context,
  current_sequence_command_context, current_services_disk_samples, managed_storage_samples,
  block_download_transport]
const
  ChainPath = "pvm-current-consecutive-fallback-chain"
  PolicyPath = "pvm-current-consecutive-fallback-policy"

proc check(fixture: CurrentConsecutiveFixture, layout: int, retry: bool) {.raises.} =
  ## Exact IO-owner confirmation precedes scalar adoption; strict startup restores each original complete history map.
  let managed = layout == 2
  var database = "pvm-current-consecutive-fallback-state"
  defer:
    if managed: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString()) # No native borrower or responder survives command return.
  var extra: seq[string] = @[]
  if layout != 0:
    extra = @["--state-storage", "disk", "--state-db", database]
    if managed:
      for argument in ["--state-layout", "managed", "--state-compact-bytes", "0"]:
        extra.add(argument) # Each explicit managed option preserves ordinary no-maintenance policy.
  var policy = currentConsecutivePolicy()
  policy.schedule.peers = ElementLimit(2)
  policy.schedule.attempts = if retry: 2 else: 1
  let observed = exchangeCurrentSequence(fixture, 0, 3,
    @[currentConsecutiveResponse(fixture.children[0]), currentConsecutiveResponse(fixture.children[1]),
      currentConsecutiveResponse(fixture.children[2])], @[Healthy, Healthy, Healthy],
    policy, ChainPath, PolicyPath, "pvm-current-consecutive-fallback", extra, fallback = true)
  let adopted = if retry: 3 else: 0
  assert observed.outcome.error == (if retry: CurrentDownloadCommandResult.Adopted else: CurrentDownloadCommandResult.Exhausted)
  assert observed.outcome.adoptedBlocks == adopted and observed.outcome.requestedBlocks == 3
  assert observed.firstRequests == (if retry: 3 else: 1)
  assert observed.secondRequests == adopted
  if layout == 0: return # Memory outcomes own no disk history projection; durable layouts qualify every retained map.
  var reopened = default(Services)
  defer: reopened.close()
  assert reopened.start(currentDiskOptions(ChainPath, database, managed, 0), "strict consecutive current restart")
  let view = reopened.chainView
  assert view.retainedCount == adopted+1
  assert view.finalizedBlock.error == GenesisError.Unavailable
  for index in 0..adopted:
    let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
    let wanted = fixture.heads[index]
    assert array[32, byte](actual.blockHash) == array[32, byte](wanted.blockHash)
    assert array[32, byte](actual.parentHash) == array[32, byte](wanted.parentHash)
    assert uint32(actual.slot) == uint32(wanted.slot)
    equalCurrentDiskMap(actual.stateSnapshot, wanted.stateSnapshot) # Every retained map is checked, not just the best-head root.
  equalCurrentDiskMap(reopened.stateSnapshot.value, fixture.heads[adopted].stateSnapshot)
  reopened.close()

proc main() {.raises.} =
  ## Three signed children exercise per-child authenticated retries and an explicit insufficient-attempt refusal.
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value)
  for layout in 0..2:
    check(fixture, layout, true)
    check(fixture, layout, false)

try:
  main()
except:
  quit(2) # Disk, proof, native request or any retained-map mismatch remains a strict failure.
echo "PVM current consecutive fallback passed"
