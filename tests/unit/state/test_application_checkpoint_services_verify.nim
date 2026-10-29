# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Services verification owns independent decoded state and preserves its distinct joined receipt through a canonical execution lease.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/services
import "../../../src/app/block/input" as block_input
import ../../../src/app/checkpoint/[worker as checkpoint_worker, identity as checkpoint_identity,
    transfer as checkpoint_transfer, file as checkpoint_file]
import ../../../src/rpc/server
import ../../../src/codec/bounded
import ../../../src/chain/genesis
import ../../support/application_checkpoint_services_context
const
  SeedPath = "application-checkpoint-services-verify-chain.json"
  FileName = "application-checkpoint-services-verify"
proc main() {.raises.} =
  ## Verification touches no canonical graph and must not be reported as durable publication or canonical recovery.
  defer:
    for name in [SeedPath, FileName, FileName & ".lock"]:
      var path = name
      discard posix.unlink(path.toCString()) # Both native workers retire before test-only file cleanup.
  var input = default(BlockInput)
  var owner = default(Services) # Borrowed input outlives explicit aggregate joined close.
  defer: owner.close()
  owner.startCheckpointServices(SeedPath)
  let expected = owner.checkpointIdentity.value
  var prepared = owner.prepareCheckpoint(ByteLimit(1000000))
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  let publication = owner.stageCheckpointExport(prepared, ByteLimit(1000000)).value
  assert owner.beginCheckpointExport(publication)
  owner.waitCheckpointServices()
  assert owner.collectCheckpointExport(publication).operation ==
      ApplicationCheckpointOperation.Publish
  discard owner.beginCheckpointLease(input)
  assert owner.preparationActive and owner.rpc.chainPaused
  assert owner.stageCheckpointVerification(default(ApplicationCheckpointIdentity),
      genesisStoreLimits(), ByteLimit(1000000)).error ==
      ApplicationCheckpointWorkerError.InvalidContext
  let ticket = owner.stageCheckpointVerification(expected, genesisStoreLimits(), ByteLimit(1000000)).value
  assert owner.beginCheckpointExport(ticket)
  owner.waitCheckpointServices()
  assert owner.preparationActive and owner.rpc.chainPaused # I/O verification cannot release the independent canonical exclusion gate.
  let completed = owner.peekCheckpointExport(ticket)
  assert completed.operation == ApplicationCheckpointOperation.Verify
  assert completed.value.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(completed.value.value, expected)
  assert owner.stageCheckpointVerification(expected, genesisStoreLimits(), ByteLimit(
      1000000)).error == ApplicationCheckpointWorkerError.Busy
  owner.close()
  owner.close()
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.checkpointShutdownPending
  assert owner.checkpointShutdown.completion.operation == ApplicationCheckpointOperation.Verify
  let shutdown = owner.takeCheckpointShutdown()
  assert shutdown.retirementError == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(shutdown.completion.value.value, expected)
  assert owner.checkpointIdentity.error == ApplicationCheckpointIdentityError.MissingHead # Verification never installs an application chain implicitly.
  assert verifyApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      1000000)).error == ApplicationCheckpointFileError.None
  echo "PASS service checkpoint verification: fixed independent trust during execution and distinct retained verification receipts"
try:
  main() # Fixture/thread/native startup errors cannot pass verification integration.
except:
  quit(2)
