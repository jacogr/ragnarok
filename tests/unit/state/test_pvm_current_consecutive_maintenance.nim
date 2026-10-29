# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Three genuine adoptions traverse automatic managed maintenance while preserving exact history and a later refusal prefix.
import std/[assertions, syncio, envvars, monotimes]
import std/posix/posix
import ../../../src/app/current/download/command as current_download_command
import ../../../src/app/services
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[report_owned, bounded]
import ../../../src/crypto/primitives
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/database_identity
import ../../support/[current_consecutive_context, current_rotated_sequence_context,
  current_consecutive_download_context,
  current_sequence_command_context, current_services_disk_samples, managed_storage_samples,
  block_download_transport, rpc_socket]
const
  ChainPath = "pvm-current-consecutive-maintenance-chain"
  PolicyPath = "pvm-current-consecutive-maintenance-policy"

proc check(fixture: CurrentConsecutiveFixture, rpc, short: bool) {.raises.} =
  ## Exact IO-owner confirmation precedes scalar adoption; strict startup restores each original complete history map.
  let managed = true
  var database = "pvm-current-consecutive-maintenance-state-" & $getMonoTime().ticks
  defer:
    if managed: removeManagedSample(database, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3),
        ManagedEpoch(4), ManagedEpoch(5), ManagedEpoch(6), ManagedEpoch(7), ManagedEpoch(8)])
    else: discard posix.unlink(database.toCString()) # No native borrower or responder survives command return.
  var extra = @["--state-storage", "disk", "--state-db", database]
  if managed:
    extra.add("--state-layout")
    extra.add("managed")
    extra.add("--state-compact-bytes")
    extra.add("1") # Each nonempty journal triggers actual automatic physical maintenance between adoptions.
  if rpc:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    extra.add("--with-rpc")
    extra.add("--rpc-port")
    extra.add($reserved.port)
  var policy = currentConsecutivePolicy()
  if short: policy.candidate.completion.composition.recent.history.blocks = ElementLimit(3)
  let responses = @[currentConsecutiveResponse(fixture.children[0]), currentConsecutiveResponse(
      fixture.children[1]), currentConsecutiveResponse(fixture.children[2])]
  writeFile("pvm-current-consecutive-maintenance-stop", "stale")
  writeFile("pvm-current-consecutive-maintenance-count",
      "999:999") # Old control/evidence must never govern this independent invocation.
  let observed = exchangeCurrentSequence(fixture, 0, 3, responses, @[Healthy, Healthy, Healthy],
    policy, ChainPath, PolicyPath, "pvm-current-consecutive-maintenance", extra)
  let adopted = if short: 2 else: 3
  let expected = if short: CurrentDownloadCommandResult.Exhausted else: CurrentDownloadCommandResult.Adopted
  if observed.outcome.error != expected or observed.outcome.adoptedBlocks != adopted:
    echo "maintenance rpc=" & $rpc & " short=" & $short & " outcome=" & $observed.outcome.error &
        " adopted=" & $observed.outcome.adoptedBlocks & " requests=" & $observed.secondRequests
  assert observed.outcome.error == expected and observed.outcome.adoptedBlocks == adopted, "automatic maintenance current progress"
  assert observed.outcome.requestedBlocks == 3
  assert observed.firstRequests == 0 and observed.secondRequests == 3
  var identity: seq[byte] = @[]
  for octet in "RAGNAROK-CHAIN-V1\n": identity.add(byte(octet))
  let parent = fixture.heads[0]
  for octet in array[32, byte](parent.blockHash): identity.add(octet)
  for octet in array[32, byte](parent.stateSnapshot.commitment.root): identity.add(octet)
  for octet in parent.chainParameters.encodeParameters: identity.add(octet)
  let digest = blake2b256(identity)
  assert digest.error == CryptoError.None
  let rawManifest = readFile(database & "/CURRENT")
  assert rawManifest.len == ManagedManifestBytes
  var manifestBytes = newSeq[byte](rawManifest.len)
  for index, octet in rawManifest: manifestBytes[index] = byte(octet)
  let manifest = decodeManagedManifest(manifestBytes, StorageChainId(array[32, byte](digest.value)),
      StorageSchema.FullStateV1, ByteLimit(ManagedManifestBytes))
  assert manifest.error == ManifestError.None
  assert uint64(manifest.value.epoch) > uint64(adopted), "maintenance must replace epochs across the adopted prefix"
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
  ## Three signed children qualify complete progress and a later explicit C3 refusal with both listener policies.
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  # Exercise the same real transport/lifecycle assertions before and after the signed slot12 rotation.
  for fixture in [currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value),
      currentRotatedSequenceFixture(decodeOwnedReport(bytes, 2).value)]:
    for rpc in [false, true]:
      check(fixture, rpc, false)
      check(fixture, rpc, true)
try:
  main()
except:
  quit(2) # Disk, proof, native request or any retained-map mismatch remains a strict failure.
echo "PVM current consecutive maintenance passed"
