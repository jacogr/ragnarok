# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Consecutive current commands persist every exact history map, with atomic retained-prefix refusal across both layouts and RPC modes.
import std/assertions
import std/syncio
import std/envvars
import std/posix/posix
import ../../../src/app/current_download_command as app_current_download_command
import ../../../src/app/services as app_services
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/bounded as codec_bounded
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../support/state_current_consecutive_context
import ../../support/state_current_rotated_sequence_context
import ../../support/state_current_consecutive_download_context
import ../../support/state_current_download_command_context
import ../../support/state_current_services_disk_samples
import ../../support/app_managed_storage_samples
import ../../support/app_block_download_transport
import ../../support/rpc_socket
const
  ChainPath = "pvm-current-consecutive-disk-chain"
  PolicyPath = "pvm-current-consecutive-disk-policy"

proc check(fixture: CurrentConsecutiveFixture, managed, rpc, short: bool) {.raises.} =
  ## Exact IO-owner confirmation precedes scalar adoption; strict startup restores each original complete history map.
  var database = "pvm-current-consecutive-disk-state"
  defer:
    if managed: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString()) # No native borrower or responder survives command return.
  var extra = @["--state-storage", "disk", "--state-db", database]
  if managed:
    extra.add("--state-layout")
    extra.add("managed")
    extra.add("--state-compact-bytes")
    extra.add("0") # These witnesses isolate publication from physical maintenance scheduling.
  if rpc:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    extra.add("--with-rpc")
    extra.add("--rpc-port")
    extra.add($reserved.port)
  var policy = currentConsecutivePolicy()
  if short: policy.candidate.completion.composition.recent.history.blocks = ElementLimit(2)
  let responses = @[currentConsecutiveResponse(fixture.children[0]), currentConsecutiveResponse(
      fixture.children[1])]
  let observed = exchangeCurrentDownloads(fixture.seed, responses, @[Healthy, Healthy], 2,
    policy, ChainPath, PolicyPath, "pvm-current-consecutive-disk", extra)
  let adopted = if short: 1 else: 2
  let expected = if short: CurrentDownloadCommandResult.Exhausted else: CurrentDownloadCommandResult.Adopted
  assert observed.outcome.error == expected and observed.outcome.adoptedBlocks == adopted
  assert observed.outcome.requestedBlocks == 2
  assert observed.firstRequests == 0 and observed.secondRequests == 2
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
  ## The same two genuinely signed children qualify both full progress and an explicit later local-resource refusal.
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  # Exercise the same real transport/lifecycle assertions before and after the signed slot12 rotation.
  for fixture in [currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value, 2),
      currentRotatedSequenceFixture(decodeOwnedReport(bytes, 2).value, 2)]:
    for managed in [false, true]:
      for rpc in [false, true]:
        check(fixture, managed, rpc, false)
        check(fixture, managed, rpc, true)
try:
  main()
except:
  quit(2) # Disk, proof, native request or any retained-map mismatch remains a strict failure.
echo "PVM current consecutive disk passed"
