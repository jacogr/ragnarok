# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent local management HTTP stays responsive while actual current native leases remain uncollected.
import std/assertions
import std/envvars
import std/syncio
import std/strutils
import std/monotimes
import std/times
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/app/proof_query as app_proof_query
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/rpc/server as rpc_server
import ../../support/management_socket
import ../../support/app_proof_query_context
import ../../support/state_current_application_context
import ../../support/state_current_consecutive_context
import ../../support/state_current_services_disk_samples
import ../../support/app_managed_storage_samples

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Short private local socket names remain within the native Unix address bound.
proc inspect(owner: var Services, path: string) =
  ## Poll only the management member: no canonical aliases, worker collection or graph retirement is allowed here.
  assert owner.rpc.chainPaused
  let reply = managementInfo(owner.management, path)
  assert "\"stateEnabled\":true" in reply and "\"pid\":" & $processId() in reply
  assert "\"residentBytes\":null" notin reply and "\"availableBytes\":null" notin reply
  assert owner.rpc.chainPaused

proc scenario(fixture: CurrentConsecutiveFixture, disk, managed: bool) {.raises.} =
  ## Actual preparation, durable publication/replacement and selected proof workers retain their exclusive leases across HTTP replies.
  var directory = "/tmp/pvm-management-" & $processId()
  var socket = directory & "/admin.sock"
  assert mkdir(directory.toCString(), Mode(0o700)) == 0
  defer: assert rmdir(directory.toCString()) == 0
  var path = "pvm-current-management-chain"
  var database = "pvm-current-management-state-" & $getMonoTime().ticks
  writeFile(path, fixture.seed.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if disk:
      if managed: removeManagedSample(database, [ManagedEpoch(1), ManagedEpoch(2)])
      else: discard posix.unlink(database.toCString()) # Storage retires only after all native workers and canonical aliases are joined.
  var args = @["server", "--with-state", "--chain", path, "--with-management",
      "--management-socket", socket]
  if disk:
    args.add("--state-storage")
    args.add("disk")
    args.add("--state-db")
    args.add(database)
  if managed:
    args.add("--state-layout")
    args.add("managed")
    args.add("--state-compact-bytes")
    args.add("0") # One explicit replacement gives a deterministic lease boundary independent of scheduling speed.
  var configuration = default(Options)
  assert parseCanonicalOptions(args, configuration)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(configuration, "current management lease witness")
  var input = default(CurrentBlockInput)
  let extent = fixture.children[0].blockInfo.value.consumed
  var wire = newSeq[byte](extent)
  assert fixture.children[0].encodeOwnedBlock(wire).error == FrameError.None
  let admitted = owner.beginBlockInput(input, ByteLimit(uint64(extent)), [],
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(extent)), ancestorBytes: ByteLimit(10000),
        ancestors: ElementLimit(4), discoverAncestors: false), currentConsecutiveLimits())
  assert admitted.error == CurrentBlockInputError.None
  assert input.append(admitted.value, wire, true) == CurrentBlockInputError.None
  let ticket = owner.beginPreparation(input, admitted.value)
  assert ticket.error == PreparationError.None
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    yieldCurrentDiskThread() # The source and canonical graph stay untouched until the actual ticket is collected.
  assert owner.preparationActive
  inspect(owner, socket)
  assert owner.preparationActive and owner.preparationPhase == PreparationPhase.Done
  let completion = owner.collectPreparation(ticket.value)
  assert completion.kind == PreparationCompletionKind.CurrentCompleted and
      completion.currentValue.error == CurrentBlockInputError.None
  let update = completion.currentValue.value
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  owner.tick(0)
  if disk:
    owner.waitCurrentDiskDone()
    assert owner.diskPublicationActive
    inspect(owner, socket)
    assert owner.diskPublicationActive and owner.diskPublicationPhase == DiskWorkerPhase.Done
    owner.tick(0) # Exact publication collection may now install the prepared successor.
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  if managed:
    assert owner.beginDiskMaintenance()
    owner.waitCurrentDiskDone()
    inspect(owner, socket)
    assert owner.diskPublicationActive and owner.diskPublicationPhase == DiskWorkerPhase.Done
    owner.tick(0) # Only explicit collection permits physical replacement aliases to retire.
    assert owner.diskMaintenanceCompletion.kind == DiskCompletionKind.Maintained
    assert owner.diskMaintenanceCompletion.maintenanceValue.error == DiskChainError.None
  assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[1].stateSnapshot)
  let selected = owner.chainView.bestBlock.value.blockHash
  let key = owner.stateSnapshot.value.keyAt(StateEntryIndex(0)).value
  let plan = captureStateProofPlan([key], ElementLimit(1)).value
  var policy = queryLimits()
  policy.map.items = ElementLimit(65536)
  policy.map.nodes = TrieNodeLimit(131071)
  policy.map.perValue = ByteLimit(1048576)
  policy.map.totalValueBytes = ByteLimit(8388608)
  let proof = owner.beginStateProof(selected, plan, policy)
  assert proof.error == StateProofAdmissionError.None
  let proofStarted = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-proofStarted).inSeconds < 20
    yieldCurrentDiskThread() # Scalar Done does not release the selected state or RPC exclusion.
  inspect(owner, socket)
  assert owner.stateProofActive and owner.stateProofPhase == ProofWorkerPhase.Done
  let proved = owner.collectStateProof(proof.value)
  assert proved.kind == ProofWorkerCompletionKind.Completed and proved.value.error ==
      ProofQueryError.None
  assert array[32, byte](proved.value.value.blockHash) == array[32, byte](selected)
  assert array[32, byte](proved.value.value.stateRoot) == array[32, byte](fixture.heads[1].stateRoot)
  assert not owner.rpc.chainPaused and not owner.stateProofActive
  owner.close()
  var status = default(Stat)
  assert lstat(socket.toCString(), status) != 0
  if disk:
    assert owner.start(configuration, "strict current management restart")
    assert owner.chainView.retainedCount == 2
    for index in 0..1:
      let actual = owner.chainView.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
      assert array[32, byte](actual.blockHash) == array[32, byte](fixture.heads[index].blockHash)
      equalCurrentDiskMap(actual.stateSnapshot, fixture.heads[index].stateSnapshot)
    owner.close()

proc main() {.raises.} =
  ## Each layout receives a fresh signed parent and test-owned endpoint with no process-global option state.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let fixture = currentConsecutiveFixture(decodeOwnedReport(wire, 2).value, 1)
  scenario(fixture, false, false)
  scenario(fixture, true, false)
  scenario(fixture, true, true)
try:
  main()
except:
  quit(2) # HTTP responsiveness alone cannot hide a changed worker lease or failed strict reopen.
echo "PVM current management leases passed"
