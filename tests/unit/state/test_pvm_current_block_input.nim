# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_block_input_arc_release"}

## Genuine signed bytes retain current-only authority through fragmented reception, lookup suspension and deferred installation.
import std/[assertions, envvars, syncio]
import ../../../src/app/[chain, candidate]
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, report_owned, block_codec, header, composite, assurances]
import ../../../src/state/store
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/report/admission as report_admission
import ../../../src/state/accumulation/current/[consensus as accumulation_current_consensus,
    update as accumulation_current_update]
import ../../support/[accumulation_current_chain_context, accumulation_current_candidate_context,
  arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Fault injection detects unexpected reception or backpressure hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Native observer counts actual primitive calls.
proc resources(size: int, discover = false): CurrentBlockInputLimits =
  ## Raw storage and ancestor handles have independent explicit bounds.
  CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(size)), ancestorBytes: ByteLimit(10000),
    ancestors: ElementLimit(4), discoverAncestors: discover)
proc encoded(context: CurrentChainFixture): seq[byte] =
  ## Serialize the actual authenticated child, without a synthetic certificate.
  let owner = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  result = newSeq[byte](owner.blockInfo.value.consumed)
  assert owner.encodeOwnedBlock(result).error == FrameError.None
proc receive(input: var CurrentBlockInput, owner: ApplicationChain, wire: openArray[byte],
    limits: CurrentCandidateLimits, discover = false): CurrentBlockInputId =
  ## Admit an exact payload and complete it using the public callback surface.
  let admitted = input.begin(owner, ByteLimit(uint64(wire.len)), [], resources(wire.len, discover), limits)
  assert admitted.error == CurrentBlockInputError.None
  result = admitted.value
  assert input.append(result, wire, true) == CurrentBlockInputError.None
proc fragments(context: CurrentChainFixture, wire: seq[byte]) =
  ## Boundary splits copy caller bytes; mutation after append cannot alter the authenticated current child.
  let owner = initApplicationChain(context.currentChainSeeded).value
  let limits = currentCandidateLimits()
  for split in [0, 1, wire.len div 2, wire.len - 1, wire.len]:
    var input = default(CurrentBlockInput)
    failHash(1)
    let admitted = input.begin(owner, ByteLimit(uint64(wire.len)), [], resources(wire.len), limits)
    assert admitted.error == CurrentBlockInputError.None
    let id = admitted.value
    assert input.prepare(id, owner).error == CurrentBlockInputError.NotReady
    var first = newSeq[byte](split)
    for index in 0..<split: first[index] = wire[index] # Caller fragments have independent mutable storage.
    assert input.append(id, first, false) == CurrentBlockInputError.None
    for index in 0..<first.len: first[index] = 255 # The receiver must own its initialized bytes.
    assert input.append(id, wire.toOpenArray(split, wire.high), true) == CurrentBlockInputError.None
    assert input.append(id, [], true) == CurrentBlockInputError.Busy
    assert hashCalls() == 0
    failHash(0)
    let prepared = input.prepare(id, owner)
    assert prepared.error == CurrentBlockInputError.None
    assert array[32, byte](prepared.value.currentUpdateState.commitment.root) ==
      array[32, byte](context.source.currentConsensusState.value.commitment.root)
    assert owner.canInstallPrepared(prepared.value)
    assert input.stage == CurrentBlockInputStage.Idle
    assert input.prepare(id, owner).error == CurrentBlockInputError.StaleInput
    assert sameStateSnapshot(owner.stateSnapshot.value, context.parent.value.stateSnapshot)
proc refusals(context: CurrentChainFixture, wire: seq[byte]) =
  ## Invalid limits, generations, decoding and actual pipeline errors never expose a successful prefix.
  let owner = initApplicationChain(context.currentChainSeeded).value
  let limits = currentCandidateLimits()
  let size = ByteLimit(uint64(wire.len))
  var input = default(CurrentBlockInput)
  failHash(1)
  let absent = default(ApplicationChain)
  assert input.begin(absent, size, [], resources(wire.len), limits).error ==
    CurrentBlockInputError.MissingHead
  for extent in [0'u64, high(uint64)]:
    assert input.begin(owner, ByteLimit(extent), [], resources(wire.len), limits).error ==
      CurrentBlockInputError.InvalidExtent
  assert input.begin(owner, size, [], resources(wire.len - 1), limits).error ==
      CurrentBlockInputError.LimitExceeded
  var wrong = limits
  wrong.reporting.admission.frame.cores = CoreCount(3)
  assert input.begin(owner, size, [], resources(wire.len), wrong).error ==
      CurrentBlockInputError.ProfileMismatch
  assert input.begin(owner, size, [default(OwnedHeader)], resources(wire.len), limits).error ==
    CurrentBlockInputError.InvalidAncestor
  let old = input.begin(owner, size, [], resources(wire.len), limits).value
  assert input.begin(owner, size, [], resources(wire.len), limits).error ==
      CurrentBlockInputError.Busy
  assert input.cancel(old)
  let fresh = input.begin(owner, size, [], resources(wire.len), limits).value
  assert fresh != old and not input.cancel(old)
  assert input.append(old, wire, true) == CurrentBlockInputError.StaleInput
  assert input.prepare(old, owner).error == CurrentBlockInputError.StaleInput
  assert input.append(fresh, [], true) == CurrentBlockInputError.Truncated
  let short = input.begin(owner, ByteLimit(1), [], resources(1), limits).value
  assert input.append(short, [1'u8, 2], true) == CurrentBlockInputError.LimitExceeded
  var trailing = wire
  trailing.add(0)
  let extra = input.receive(owner, trailing, limits)
  assert input.prepare(extra, owner).error == CurrentBlockInputError.TrailingBytes
  let malformed = input.receive(owner, [1'u8], limits)
  let decoded = input.prepare(malformed, owner)
  assert decoded.error == CurrentBlockInputError.DecodeFailure
  assert decoded.decodeFailure.error != FrameError.None
  let stale = input.receive(owner, wire, limits)
  let foreign = initApplicationChain(genesisView(context.parent)).value
  assert input.prepare(stale, foreign).error == CurrentBlockInputError.StateChanged
  assert hashCalls() == 0 and input.stage == CurrentBlockInputStage.Idle
  failHash(0)
  wrong = limits
  wrong.headerBytes = ByteLimit(1)
  let tiny = input.receive(owner, wire, wrong)
  let failed = input.prepare(tiny, owner)
  assert failed.error == CurrentBlockInputError.PreparationFailure
  assert failed.preparationFailure.error == CurrentCandidateError.PreparationFailure
proc ancestry(context: CurrentChainFixture, wire: seq[byte]) =
  ## Suspended discovery retains original current policies and generation, and resumes without repeating the prefix.
  let owner = initApplicationChain(context.currentChainSeeded).value
  var input = default(CurrentBlockInput)
  let id = input.receive(owner, wire, currentCandidateLimits(), true)
  let pending = input.prepare(id, owner)
  assert pending.error == CurrentBlockInputError.NeedsAncestors
  assert pending.ancestorDemand.missingLookups.value > 0
  assert input.stage == CurrentBlockInputStage.AwaitingAncestors
  assert input.prepare(id, owner).error == CurrentBlockInputError.NotReady
  failHash(1)
  assert input.resumeAncestors(id, owner, [default(OwnedHeader)]) ==
      CurrentBlockInputError.InvalidAncestor
  assert input.stage == CurrentBlockInputStage.AwaitingAncestors
  var ancestors = context.older
  assert input.resumeAncestors(id, owner, ancestors) == CurrentBlockInputError.None
  for index in 0..<ancestors.len: ancestors[index] = default(OwnedHeader) # Receiver retains independent handles.
  assert hashCalls() == 0
  failHash(0)
  let completed = input.prepare(id, owner)
  assert completed.error == CurrentBlockInputError.None
  assert array[32, byte](completed.value.currentUpdateState.commitment.root) ==
    array[32, byte](context.source.currentConsensusState.value.commitment.root)
proc handoff(context: CurrentChainFixture, wire: seq[byte]) =
  ## Both Pending and unacknowledged Finished impose backpressure before input decoding or graph access.
  var owner = initApplicationChain(context.currentChainSeeded).value
  var first, second = default(CurrentBlockInput)
  var slot = default(CurrentAccumulationHandoff)
  let id = first.receive(owner, wire, currentCandidateLimits())
  assert first.enqueue(id, owner, slot).error == CurrentBlockInputError.None
  let next = second.receive(owner, wire, currentCandidateLimits())
  failHash(1)
  assert second.enqueue(next, owner, slot).error == CurrentBlockInputError.Busy
  slot.process(owner)
  assert slot.phase == CurrentHandoffPhase.Finished
  assert second.enqueue(next, owner, slot).error == CurrentBlockInputError.Busy
  assert hashCalls() == 0 and second.stage == CurrentBlockInputStage.Ready
  assert slot.take.error == CurrentHandoffError.None
  assert second.enqueue(next, owner, slot).error == CurrentBlockInputError.StateChanged
  failHash(0)
proc cycle(context: CurrentChainFixture, wire: seq[byte]) =
  ## Complete raw preparation releases every source, prefix and captured update without installation.
  let owner = initApplicationChain(context.currentChainSeeded).value
  var input = default(CurrentBlockInput)
  let id = input.receive(owner, wire, currentCandidateLimits())
  assert input.prepare(id, owner).error == CurrentBlockInputError.None
proc main() {.raises.} =
  ## Actual signatures and current effects provide independent complete-map and ownership witnesses.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[
      index]) # Convert fixture bytes without a production parser substitute.
  let base = decodeOwnedReport(bytes, 2).value
  let context = currentChainFixture(base, available = true)
  let wire = context.encoded
  fragments(context, wire)
  refusals(context, wire)
  let lookup = currentChainFixture(base, uses = 2, available = true)
  ancestry(lookup, lookup.encoded)
  handoff(context, wire)
  cycle(context, wire)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context, wire) # Fresh activations must release all ARC-owned raw/current graphs.
  let after = getOccupiedMem()
  assert before == after, "current raw receiver releases"
  recordArcRelease("pvm_current_block_input", 1000, before, after)
  echo "PVM current block input passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected native, signature or current preparation failure remains a failed suite.
except:
  quit(2)
