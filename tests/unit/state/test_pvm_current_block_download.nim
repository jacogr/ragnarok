# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_block_download_arc_release"}

## Current-only CE128 framing, exact worker handoff, ancestry suspension and stable receiver retirement use genuine signed children.
import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../../src/app/services
import "../../../src/app/current/block/download" as current_block_download
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/app/[preparation_worker, candidate, chain, options]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, report_owned]
import ../../../src/state/store
import ../../../src/state/accumulation/current/[update as accumulation_current_update,
    consensus as accumulation_current_consensus]
import ../../../src/state/report/anchors as report_anchors
import ../../support/[current_services_disk_samples, current_application_context,
  accumulation_current_chain_context, accumulation_current_candidate_context, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Native reception and resumption must do no hashing or execution.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count primitive work independently of receiver status.
proc frame(context: CurrentChainFixture): seq[byte] =
  ## Independent E4 framing retains exactly one signed current block without an element-count prefix.
  let wire = context.currentDiskChildBytes
  assert uint64(wire.len) <= 0xffffffff'u64 and wire.len <= high(int)-4
  result = newSeq[byte](wire.len+4)
  for index in 0..<4: result[index] = byte((uint64(wire.len) shr (8*index)) and 255)
  for index, octet in wire: result[index+4] = octet
proc resources(size: int, discover = false): CurrentBlockInputLimits =
  ## All retained payload and ancestor ceilings are explicit local choices.
  CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(size)), ancestorBytes: ByteLimit(10000),
    ancestors: ElementLimit(4), discoverAncestors: discover)
proc begin(download: var CurrentBlockDownload, owner: Services, wire: seq[byte],
    discover = false): CurrentBlockDownloadId =
  ## Admit the current policy against the exact captured complete canonical parent.
  let admitted = download.begin(owner, [], resources(wire.len, discover), currentCandidateLimits())
  assert admitted.error == CurrentBlockDownloadError.None
  admitted.value
proc ready(download: var CurrentBlockDownload, owner: Services, wire: seq[byte],
    discover = false): CurrentBlockDownloadId =
  ## Both actual FIN observations are required before lending stable raw storage to a worker.
  result = download.begin(owner, wire, discover)
  assert download.append(result, wire, true) == CurrentBlockDownloadError.None
  assert download.stage == CurrentBlockDownloadStage.Receiving
  assert download.requestFinished(result) == CurrentBlockDownloadError.None
  assert download.stage == CurrentBlockDownloadStage.Ready
proc waitDone(owner: var Services) =
  ## Only scalar/dispatcher operations run while the current worker owns its exact RPC/graph lease.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    yieldCurrentDiskThread() # The shared wait helper retains no canonical/raw aliases.
proc framing(owner: Services, wire: seq[byte]) =
  ## Every split, defensive request copy, both FIN orders and malformed E4 outcomes are checked without guest work.
  var download = default(CurrentBlockDownload)
  let parent = array[32, byte](owner.chainView.bestBlock.value.blockHash)
  failHash(1)
  for split in 0..wire.len:
    let id = download.begin(owner, wire)
    let request = download.request(id).value
    assert request[0] == 128 and request[1] == 37 and request[37] == 0 and request[38] == 1
    for index in 0..<32: assert request[index+5] == parent[index]
    var scratch = request
    scratch[0] = 0
    assert download.request(id).value[0] == 128
    assert download.requestFinished(id) == CurrentBlockDownloadError.None
    assert download.append(id, wire.toOpenArray(0, split-1), false) ==
        CurrentBlockDownloadError.None
    assert download.append(id, wire.toOpenArray(split, wire.high), true) ==
        CurrentBlockDownloadError.None
    assert download.stage == CurrentBlockDownloadStage.Ready
    assert download.append(id, [], true) == CurrentBlockDownloadError.Busy
    assert download.cancel(id)
    assert download.append(id, [], true) == CurrentBlockDownloadError.StaleDownload
  let empty = download.begin(owner, wire)
  assert download.append(empty, [0'u8, 0, 0, 0], true) == CurrentBlockDownloadError.None
  assert download.requestFinished(empty) == CurrentBlockDownloadError.None
  assert download.stage == CurrentBlockDownloadStage.Empty and download.cancel(empty)
  for cut in [0, 1, 2, 3, 4, wire.len-1]:
    let id = download.begin(owner, wire)
    assert download.append(id, wire.toOpenArray(0, cut-1), true) ==
        CurrentBlockDownloadError.Truncated
    assert download.failure.error == CurrentBlockDownloadError.Truncated
    assert download.cancel(id)
  let huge = download.begin(owner, wire)
  assert download.append(huge, [255'u8, 255, 255, 255], false) ==
      CurrentBlockDownloadError.LimitExceeded
  assert download.cancel(huge)
  let extra = download.begin(owner, wire)
  var trailing = wire
  trailing.add(0)
  assert download.append(extra, trailing, true) == CurrentBlockDownloadError.Trailing
  assert download.cancel(extra)
  assert hashCalls() == 0
  failHash(0)
proc jobs(owner: var Services, wire: seq[byte]) =
  ## Completed cancellation and joined retirement retain stable input/parent ownership and never enqueue unwanted work.
  var download = default(CurrentBlockDownload)
  let parent = owner.stateSnapshot.value
  for cancelled in [false, true]:
    let id = download.ready(owner, wire)
    assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
    assert not download.cancel(id) and owner.rpc.chainPaused
    owner.waitDone()
    assert owner.preparationActive and owner.rpc.chainPaused
    if cancelled: assert download.cancelPreparation(id, owner)
    let completed = download.collectPreparation(id, owner)
    if cancelled:
      assert completed.error == CurrentBlockDownloadError.Cancelled
      assert download.cancel(id)
    else:
      assert completed.error == CurrentBlockDownloadError.None
      assert sameStateSnapshot(owner.stateSnapshot.value, parent)
      assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
      assert owner.cancelCurrentAccumulation()
      assert download.stage == CurrentBlockDownloadStage.Idle
    assert not owner.preparationActive and not owner.rpc.chainPaused
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  let joined = download.ready(owner, wire)
  assert download.beginPreparation(joined, owner).error == CurrentBlockDownloadError.None
  owner.waitDone()
  assert download.retirePreparation(joined, owner)
  assert not owner.preparationActive and download.stage == CurrentBlockDownloadStage.Idle
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
proc scenario(context: CurrentChainFixture, ancestry = false) {.raises.} =
  ## Complete independent parent startup supplies real current execution and original-history ancestry resumption.
  var path = "pvm-current-block-download-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var download = default(CurrentBlockDownload)
  var owner = default(Services)
  defer:
    discard download.retirePreparation(CurrentBlockDownloadId(1), owner)
    owner.close() # No outstanding worker may outlive its receiver even on exceptional test exit.
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current receiver")
  let wire = context.frame
  if not ancestry:
    framing(owner, wire)
    jobs(owner, wire)
  let id = download.ready(owner, wire, ancestry)
  assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
  owner.waitDone()
  var completed = download.collectPreparation(id, owner)
  if ancestry:
    assert completed.error == CurrentBlockDownloadError.NeedsAncestors
    assert download.stage == CurrentBlockDownloadStage.AwaitingAncestors
    assert download.ancestorDemand(id).value.missingLookups.value > 0
    failHash(1)
    assert download.resumeAncestors(id, owner, [default(OwnedHeader)]).error ==
        CurrentBlockDownloadError.InputFailure
    assert download.resumeAncestors(id, owner, context.older).error ==
        CurrentBlockDownloadError.None
    assert hashCalls() == 0
    failHash(0)
    assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
    owner.waitDone()
    completed = download.collectPreparation(id, owner)
  assert completed.error == CurrentBlockDownloadError.None
  equalCurrentDiskMap(completed.value.currentUpdateState,
      context.source.currentConsensusState.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
  owner.tick(0)
  let installed = owner.takeCurrentAccumulation()
  assert installed.error == CurrentHandoffError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, completed.value.currentUpdateState)
  assert download.stage == CurrentBlockDownloadStage.Idle
proc cycle(context: CurrentChainFixture, wire: seq[byte]) =
  ## Isolated reception-only cycles release their bounded raw bytes and captured immutable owners without worker allocator claims.
  var download = default(CurrentBlockDownload)
  let owner = initApplicationChain(context.currentChainSeeded).value
  let admitted = download.begin(owner, [], resources(wire.len), currentCandidateLimits())
  assert admitted.error == CurrentBlockDownloadError.None
  assert download.requestFinished(admitted.value) == CurrentBlockDownloadError.None
  assert download.append(admitted.value, wire, true) == CurrentBlockDownloadError.None
  assert download.cancel(admitted.value)
proc main() {.raises.} =
  ## Independent current state and signed report inputs qualify actual execution separately from callback/ARC work.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let base = decodeOwnedReport(bytes, 2).value
  let context = currentChainFixture(base, available = true)
  let wire = context.frame
  cycle(context, wire)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context, wire)
  let after = getOccupiedMem()
  assert before == after, "current download reception releases"
  recordArcRelease("pvm_current_block_download", 1000, before, after)
  scenario(context)
  scenario(currentChainFixture(base, uses = 2, available = true), true)
  echo "PVM current block download passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit(2) # Current execution, signed fixture or worker failure cannot satisfy successful reception evidence.
