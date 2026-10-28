# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared signed current Services setup and scalar-only native waits preserve exact disk publication ownership.
import std/[assertions, monotimes, times]
import std/posix/posix
import ../../src/app/[services, options, preparation_worker, current_block_input, candidate, disk_worker]
import ../../src/rpc/server
import ../../src/codec/[bounded, block_codec]
import ../../src/state/[store, accumulation_current_update, block_admission, report_admission]
import ./[accumulation_current_chain_context, accumulation_current_candidate_context]
proc yieldCurrentDiskThread*() =
  ## Yield within bounded waits without creating or retiring any leased graph alias.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)
proc currentDiskOptions*(path, database: string, managed: bool, port: uint16): Options =
  ## Explicit local startup selects either strict disk layout and the original complete parent map.
  var args = @["server", "--with-state", "--chain", path, "--state-storage", "disk",
    "--state-db", database]
  if managed:
    args.add("--state-layout")
    args.add("managed")
    args.add("--state-compact-bytes")
    args.add("0") # Publication tests keep automatic maintenance out of the selected physical lifetime.
  if port != 0:
    args.add("--with-rpc")
    args.add("--rpc-port")
    args.add($port) # Only the test-owned loopback reservation chooses this listener.
  result = default(Options)
  assert parseCanonicalOptions(args, result)
proc currentDiskChildBytes*(context: CurrentChainFixture): seq[byte] =
  ## Capture signed wire bytes before native Services ownership can be borrowed.
  let child = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  result = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(result).error == FrameError.None
proc prepareCurrentServicesUpdate*(owner: var Services, input: var CurrentBlockInput,
    wire: openArray[byte]): PreparedCurrentChainUpdate {.raises.} =
  ## Actual execution returns a current update without installing or changing the durable parent.
  let admitted = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)), ancestorBytes: ByteLimit(10000),
      ancestors: ElementLimit(4), discoverAncestors: false), currentCandidateLimits())
  assert admitted.error == CurrentBlockInputError.None
  assert input.append(admitted.value, wire, true) == CurrentBlockInputError.None
  let ticket = owner.beginPreparation(input, admitted.value)
  assert ticket.error == PreparationError.None
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    yieldCurrentDiskThread() # Only dispatcher/scalar state is touched until collection ends preparation exclusion.
  assert owner.preparationActive and owner.rpc.chainPaused
  let completion = owner.collectPreparation(ticket.value)
  assert completion.kind == PreparationCompletionKind.CurrentCompleted
  assert completion.currentValue.error == CurrentBlockInputError.None
  completion.currentValue.value
proc waitCurrentDiskDone*(owner: var Services) =
  ## Done alone never releases the exclusive native lease; deliberately do not tick/collect here.
  let started = getMonoTime()
  while owner.diskPublicationPhase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    yieldCurrentDiskThread()
proc equalCurrentDiskMap*(actual, expected: StateStoreSnapshot) =
  ## Every reopened entry and byte value is compared against independently composed current state.
  assert actual.commitment.entries == expected.commitment.entries
  assert array[32, byte](actual.commitment.root) == array[32, byte](expected.commitment.root)
  for index in 0..<expected.commitment.entries:
    let key = expected.keyAt(StateEntryIndex(index)).value
    assert actual.lookup(key).error == StateStoreError.None
    assert actual.lookup(key).value.bytes == expected.lookup(key).value.bytes
