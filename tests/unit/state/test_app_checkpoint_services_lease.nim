# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached export remains available through a real canonical execution lease and joined aggregate shutdown.
import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/block_input as app_block_input
import ../../../src/app/checkpoint_worker as app_checkpoint_worker
import ../../../src/app/checkpoint_transfer as app_checkpoint_transfer
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_file as app_checkpoint_file
import ../../../src/rpc/server as rpc_server
import ../../../src/codec/bounded as codec_bounded
import ../../../src/chain/genesis as chain_genesis
import ../../support/app_checkpoint_services_context
const
  SeedPath = "application-checkpoint-services-lease-chain.json"
  FileName = "application-checkpoint-services-lease"
proc scenario(acknowledge: bool) {.raises.} =
  ## Original canonical context is captured before the lease; no state/header/history alias crosses into I/O.
  var input = default(BlockInput)
  var owner = default(Services) # Input outlives explicit joined service cleanup.
  defer: owner.close()
  owner.startCheckpointServices(SeedPath)
  let expected = owner.checkpointIdentity.value
  var prepared = owner.prepareCheckpoint(ByteLimit(1000000))
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  discard owner.beginCheckpointLease(input)
  assert owner.preparationActive and owner.rpc.chainPaused
  let ticket = owner.stageCheckpointExport(prepared, ByteLimit(1000000)).value
  assert owner.beginCheckpointExport(ticket)
  owner.waitCheckpointServices()
  assert owner.preparationActive and owner.rpc.chainPaused # I/O completion never releases another worker's canonical lease.
  let observed = owner.peekCheckpointExport(ticket)
  assert observed.kind == ApplicationCheckpointCompletionKind.Completed
  assert observed.value.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(observed.value.value, expected)
  if acknowledge:
    assert owner.collectCheckpointExport(ticket).kind ==
        ApplicationCheckpointCompletionKind.Completed
  else:
    assert owner.peekCheckpointExport(ticket).kind ==
        ApplicationCheckpointCompletionKind.Completed # Observation alone retains the receipt through shutdown.
  owner.close() # Join both independent threads before canonical/input retirement.
  owner.close()
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.checkpointShutdownPending == (not acknowledge)
  if not acknowledge:
    var transferred = move(owner) # Closed parent relocation transfers the retained fixed journal safely.
    defer: transferred.close()
    assert not owner.checkpointShutdownPending
    assert sameApplicationCheckpoint(transferred.checkpointShutdown.completion.value.value, expected)
    assert transferred.start(checkpointServicesOptions(SeedPath), "lease restart")
    assert transferred.startCheckpointExport(FileName) == ApplicationCheckpointFileError.Busy
    let shutdown = transferred.takeCheckpointShutdown()
    assert shutdown.retirementError == ApplicationCheckpointFileError.None
    assert sameApplicationCheckpoint(shutdown.completion.value.value, expected)
    assert transferred.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
    assert not transferred.beginCheckpointExport(ticket)
    transferred.close() # Clean idle restart must not fabricate a duplicate joined publication receipt.
    assert not transferred.checkpointShutdownPending
  assert loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      1000000)).error == ApplicationCheckpointFileError.None
proc main() {.raises.} =
  ## Both acknowledged and joined-only publication preserve the independent preparation gate and actual disk outcome.
  defer:
    for name in [SeedPath, FileName, FileName & ".lock"]:
      var path = name
      discard posix.unlink(path.toCString()) # Both threads and all lock owners retire before test-only cleanup.
  scenario(true)
  scenario(false)
  echo "PASS service checkpoint lease: detached publication during execution, independent gates and exact collected/joined receipts"
try:
  main() # Fixture/native/thread errors remain integration failures.
except:
  quit(2)
