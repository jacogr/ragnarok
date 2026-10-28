# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked canonical/lifecycle guards must reject access even after execution finishes but before collection.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/app/services as app_services
import ../../src/app/options as app_options
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/block_input as app_block_input
import ../../src/app/candidate as app_candidate
import ../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../src/app/checkpoint_transfer as app_checkpoint_transfer
import ../../src/app/checkpoint_codec as app_checkpoint_codec
import ../../src/rpc/server as rpc_server
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/header as codec_header
import ../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../src/state/accumulation_completion as state_accumulation_completion
import ../support/app_candidate_context

proc main() {.raises.} =
  ## The positive case joins explicitly; every invalid mode must fail at its selected guard with no graph access.
  let mode = paramStr(1)
  if mode == "rpc-destroy":
    var rpc = default(Server)
    discard rpc.pauseChain()
    return # Destruction requires release even with disabled sockets.
  var input = default(BlockInput)
  var owner = default(Services) # Guarded destruction precedes retirement of its borrowed input.
  if mode == "default-begin":
    discard owner.beginPreparation(input, BlockInputId(0))
    return # A default Services owner grants no preparation authority.
  let raw = readFile("tests/fixtures/state-report.bin")
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet) # The ordinary native suite independently verifies this pinned fixture.
  let context = fixture(decodeOwnedReport(bytes, 2).value)
  const path = "build/preparation-lease-guard-chain.json"
  writeFile(path, context.text)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", path, "--with-state", "--state-writes", "1000",
    "--state-write-bytes", "1000000"], options)
  assert owner.start(options, "guard")
  let captured = owner.checkpointIdentity
  assert captured.error == ApplicationCheckpointIdentityError.None
  block:
    var prepared = owner.prepareCheckpoint(ByteLimit(1000000))
    assert prepared.error == ApplicationCheckpointError.None # Genuine positive capture/preparation occurs before the managed graph lease.
  let admitted = owner.beginBlockInput(input, ByteLimit(1), [], BlockInputLimits(
      blockBytes: ByteLimit(1)), preparationLimits())
  assert admitted.error == BlockInputError.None
  assert input.append(admitted.value, [255'u8], true) == BlockInputError.None
  let job = owner.beginPreparation(input, admitted.value)
  assert job.error == PreparationError.None
  case mode
  of "checkpoint-identity": discard owner.checkpointIdentity # No canonical capture may inspect a leased graph.
  of "checkpoint-prepare": discard owner.prepareCheckpoint(ByteLimit(
      1000000)) # No serialization may traverse a leased graph.
  of "view": discard owner.chainView # No new selected-history alias may escape.
  of "snapshot": discard owner.stateSnapshot # No complete-map alias may escape.
  of "apply": discard owner.applyAccumulation(default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits)) # Canonical mutation/preparation must stop at the exclusion guard.
  of "enqueue": discard owner.enqueueAccumulation(default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits)) # Canonical mutation/preparation must stop at the exclusion guard.
  of "candidate": discard owner.enqueueCandidate(default(OwnedBlock), [], default(
      ApplicationCandidateLimits), default(
      AccumulationCompositionLimits)) # Canonical mutation/preparation must stop at the exclusion guard.
  of "begin-input": discard owner.beginBlockInput(input, ByteLimit(1), [], default(
      BlockInputLimits), default(ApplicationCandidateLimits)) # Reception cannot capture canonical state during a lease.
  of "enqueue-input": discard owner.enqueueBlockInput(input, admitted.value, default(
      AccumulationCompositionLimits)) # Canonical mutation/preparation must stop at the exclusion guard.
  of "rpc-close": owner.rpc.close() # Direct listener retirement cannot release worker-shared history.
  of "services-destroy": return # The composite worker destructor must run before any shared canonical alias retires.
  else:
    owner.close() # Joining an active worker releases the RPC gate before listener/snapshot destruction.
    assert not owner.preparationActive and not owner.rpc.chainPaused
  owner.close() # Unexpected guard success still exits normally, making the strict failure probe fail its verdict.

try:
  main() # Raising fixture/startup errors never count as the required assertion defect.
except:
  quit(2)
