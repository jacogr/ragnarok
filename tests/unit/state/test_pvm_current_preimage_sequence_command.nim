# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual command/IO owners preserve nonempty preimage availability and the exact adopted prefix on a freshly sealed repeat.
import std/[assertions, syncio, envvars, monotimes]
import std/posix/posix
import ../../../src/app/current/download/command as current_download_command
import ../../../src/app/services
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, bounded]
import ../../../src/storage/managed/manifest as managed_manifest
import ../../support/[current_preimage_sequence_context, current_consecutive_download_context,
  current_sequence_command_context, current_services_disk_samples, managed_storage_samples,
  block_download_transport, rpc_socket]
const
  ChainPath = "pvm-current-preimage-sequence-command-chain"
  PolicyPath = "pvm-current-preimage-sequence-command-policy"

proc check(fixture: CurrentPreimageSequenceFixture, layout: int, rpc, repeated: bool) {.raises.} =
  ## Services consumes genuine nonempty current bodies; durable cases qualify every retained physical map after joined teardown.
  let managed = layout == 2
  var database = "pvm-current-preimage-sequence-command-state-" & $getMonoTime().ticks
  defer:
    if managed: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString()) # Exact test-owned paths retire only after all command workers and callbacks join.
  var extra: seq[string] = @[]
  if layout != 0:
    extra = @["--state-storage", "disk", "--state-db", database]
    if managed:
      for argument in ["--state-layout", "managed", "--state-compact-bytes", "0"]:
        extra.add(argument) # Physical publication remains separate from the earlier automatic-maintenance regression.
  if rpc:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    for argument in ["--with-rpc", "--rpc-port", $reserved.port]:
      extra.add(argument) # Each durable listener policy owns a fresh loopback reservation.
  var responses = @[currentConsecutiveResponse(fixture.sequence.children[0]),
    currentConsecutiveResponse(fixture.sequence.children[1])]
  if repeated: responses.add(currentConsecutiveResponse(fixture.repeated))
  var modes: seq[DownloadTransferMode] = @[]
  for response in responses:
    modes.add(Healthy) # Every rejection receives a complete structurally valid genuine frame and FIN.
  let observed = exchangeCurrentSequence(fixture.sequence, 0, responses.len, responses, modes,
    currentConsecutivePolicy(), ChainPath, PolicyPath, "pvm-current-preimage-sequence-command", extra)
  assert observed.outcome.error == (if repeated: CurrentDownloadCommandResult.Exhausted else: CurrentDownloadCommandResult.Adopted)
  assert observed.outcome.adoptedBlocks == 2 and observed.outcome.requestedBlocks == responses.len
  assert observed.firstRequests == 0 and observed.secondRequests == responses.len
  if layout == 0: return # The command deliberately returns scalar progress; exact map/history observations use durable owners below.
  let adopted = 2
  var reopened = default(Services)
  defer: reopened.close()
  assert reopened.start(currentDiskOptions(ChainPath, database, managed, 0), "strict consecutive current restart")
  let view = reopened.chainView
  assert view.retainedCount == adopted+1
  assert view.finalizedBlock.error == GenesisError.Unavailable
  for index in 0..adopted:
    let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
    let wanted = fixture.sequence.heads[index]
    assert array[32, byte](actual.blockHash) == array[32, byte](wanted.blockHash)
    assert array[32, byte](actual.parentHash) == array[32, byte](wanted.parentHash)
    assert uint32(actual.slot) == uint32(wanted.slot)
    equalCurrentDiskMap(actual.stateSnapshot, wanted.stateSnapshot) # Every retained map is checked, not just the best-head root.
  equalCurrentDiskMap(reopened.stateSnapshot.value, fixture.sequence.heads[adopted].stateSnapshot)
  reopened.close()

proc main() {.raises.} =
  ## Two accepted bodies and a freshly sealed repeated delivery qualify memory progress and durable history under both listener policies.
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentPreimageSequenceFixture(decodeOwnedReport(bytes, 2).value)
  for layout in 0..2:
    check(fixture, layout, false, false)
    check(fixture, layout, false, true)
    if layout != 0:
      check(fixture, layout, true, false)
      check(fixture, layout, true, true) # RPC-enabled durable history must retain the same exact nonempty successor prefix.

try:
  main()
except:
  quit(2) # Disk, proof, native request or any retained-map mismatch remains a strict failure.
echo "PVM current preimage sequence command passed"
