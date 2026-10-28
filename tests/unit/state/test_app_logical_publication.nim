# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical refresh composes with actual durable publication in both journal and managed layouts under the existing native lease.
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../support/state_current_repeated_logical_context
import ../../support/app_collected_logical_context
import ../../support/app_collected_logical_services_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/app_download_chain
import ../../support/state_current_logical_proof_context
import ../../support/app_managed_storage_samples
import ../../../src/app/services as app_services
import ../../../src/app/current_logical as app_current_logical
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/candidate as app_candidate
import ../../../src/state/parent_logical as state_parent_logical
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield scalar phase polling without touching any leased graph owner.
proc waitDisk(owner: var Services) =
  ## Done retains publication exclusion until the following explicit host tick actually collects.
  let start = getMonoTime()
  while owner.diskPublicationPhase != DiskWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000)
proc run(fixture: CurrentRepeatedLogicalFixture, managed: bool) {.raises.} =
  ## Reparse a complete selected parent and continue two actual native current children across confirmed durable publication.
  var path = "application-logical-publication-chain.json"
  var database = "application-logical-publication-" & $getMonoTime().ticks
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  let source = startLogicalServices(owner, fixture, path, database, managed)
  defer:
    owner.close() # Every worker joins before exact test-owned disk namespaces are removed.
    discard posix.unlink(path.toCString())
    if managed: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString())
  var prior = default(CurrentLogicalState)
  let bound = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted
  var wire = currentWire(bound.admittedBlock)
  for slot in 2..3:
    let original = owner.stateSnapshot.value
    var policies = currentCandidateLimits()
    if slot == 3: policies.completion.composition.validators.services = ElementLimit(2)
    let ancestors = if slot == 2: fixture.first.source.older else: @[]
    let ticket = beginManagedCurrent(owner, input, wire, ancestors, policies)
    owner.waitManagedPreparation()
    let receipt = owner.collectPreparation(ticket)
    let refreshed = if slot == 2:
      owner.refreshCollectedLogical(receipt, source, collectedLogicalTestLimits())
    else:
      owner.refreshCollectedLogical(receipt, prior, collectedLogicalTestLimits())
    assert refreshed.error == CollectedLogicalError.None
    let update = receipt.currentValue.value
    assert sameStateSnapshot(refreshed.value.logicalProducer.currentUpdateState,
        update.currentUpdateState)
    assert sameStateSnapshot(owner.stateSnapshot.value, original), "refresh cannot publish"
    if slot == 2:
      let crossed = owner.refreshCollectedLogical(receipt, fixture.first.parent,
          collectedLogicalTestLimits())
      assert crossed.error == CollectedLogicalError.IdentityFailure
      assert crossed.identityFailure.error == CurrentIdentityError.ParentMismatch, "equal root cannot replace a physical seed"
    prior = refreshed.value # Host alias replacement precedes disk submission; all retained aliases stay untouched until collection.
    assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
    owner.tick(0)
    assert owner.diskPublicationActive
    owner.waitDisk()
    assert owner.diskPublicationActive and owner.currentAccumulationPhase ==
        CurrentHandoffPhase.Publishing
    assert owner.collectPreparation(default(PreparationTicket)).kind ==
        PreparationCompletionKind.Uninitialized
    assert owner.diskPublicationActive # A different worker's stale receipt cannot reopen publication exclusion.
    owner.tick(0) # This actual Done collection installs the confirmed durable child before reopening host access.
    assert not owner.diskPublicationActive
    assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
    assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
    assert owner.refreshCollectedLogical(receipt, source, collectedLogicalTestLimits()).error ==
        CollectedLogicalError.StaleUpdate
    if slot == 2: wire = currentWire(signedChild(update.currentUpdateChild))
  assert prior.logicalProducer.currentUpdateChildContext.slot == 3
proc main() {.raises.} =
  ## The maintained complete signed fixture supplies all authenticated namespace and execution authority.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  run(fixture, false)
  run(fixture, true)
  echo "application-logical-publication: ok"
try:
  main()
except:
  quit(2) # Native startup, durable publication or cleanup exceptions cannot satisfy qualification.
