# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_block_input"}

## Fragment ownership, generation isolation and exact selected-head preparation feed deferred canonical adoption.

import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[block_input, candidate, chain, handoff, services, options]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, block_codec, header, report_owned, assurances]
import ../../../src/state/[store, accumulation_finalization, accumulation_runner, report_admission, report_anchors]
import ../../support/[application_candidate_context, accumulation_completion_context, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refusal observer proves reception/backpressure perform no primitive work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Read actual primitive call counts, independently of application result status.

proc resources(bytes: int): BlockInputLimits =
  ## Every allocation/retained ancestor ceiling remains an explicit local resource decision.
  BlockInputLimits(blockBytes: ByteLimit(uint64(bytes)), ancestorBytes: ByteLimit(8192),
      ancestors: ElementLimit(4))

proc encoded(context: SeedFixture): seq[byte] =
  ## Emit the genuine signed full block using the canonical codec before independently fragmenting it.
  let owner = candidateBlock(context)
  result = newSeq[byte](owner.blockInfo.value.consumed)
  let source = Block(header: owner.blockHeader.value, extrinsic: owner.blockExtrinsic.value)
  assert encodeBlock(source, preparationLimits().reporting.admission.frame, result).error ==
      FrameError.None

proc receive(input: var BlockInput, chain: ApplicationChain, wire: openArray[byte],
    policies: ApplicationCandidateLimits): BlockInputId =
  ## Complete an exact trusted test payload through the same public callback-facing surface.
  let admitted = input.begin(chain, ByteLimit(uint64(wire.len)), [], resources(wire.len), policies)
  assert admitted.error == BlockInputError.None
  result = admitted.value
  assert input.append(result, wire, true) == BlockInputError.None
  assert input.stage == BlockInputStage.Ready

proc fragmentation(context: SeedFixture, wire: seq[byte]) =
  ## Every split copies initialized bytes; overwriting caller storage cannot alter retained reception.
  let chain = initialized(context)
  let before = chain.stateSnapshot.value
  let policies = preparationLimits()
  for split in 0..wire.len:
    var input = default(BlockInput)
    failHash(1)
    let admitted = input.begin(chain, ByteLimit(uint64(wire.len)), [], resources(wire.len), policies)
    assert admitted.error == BlockInputError.None and hashCalls() == 0
    let id = admitted.value
    assert input.prepare(id, chain).error == BlockInputError.NotReady
    var first = newSeq[byte](split)
    for index in 0..<split: first[index] = wire[index] # Caller-owned fragments need not outlive append.
    assert input.append(id, first, false) == BlockInputError.None
    for index in 0..<first.len: first[index] = 255 # Mutation after append must not reach the owned byte buffer.
    assert input.stage == BlockInputStage.Receiving
    assert input.append(id, wire.toOpenArray(split, wire.high), true) == BlockInputError.None
    assert input.stage == BlockInputStage.Ready and hashCalls() == 0
    assert input.append(id, [], true) == BlockInputError.Busy
    failHash(0)
    let prepared = input.prepare(id, chain)
    assert prepared.error == BlockInputError.None, $prepared.error & " at split " & $split
    assert sameStateSnapshot(prepared.value.finalAccumulationParent.value, before)
    assert input.stage == BlockInputStage.Idle
    assert input.prepare(id, chain).error == BlockInputError.StaleInput
    assert sameStateSnapshot(before, chain.stateSnapshot.value)

proc refusals(context: SeedFixture, wire: seq[byte]) =
  ## Limit, lifecycle and generation refusals cannot replace another reception or authorize partial decoding.
  let chain = initialized(context)
  let policies = preparationLimits()
  let size = ByteLimit(uint64(wire.len))
  var input = default(BlockInput)
  failHash(1)
  var missing = default(ApplicationChain)
  assert input.begin(missing, size, [], resources(wire.len), policies).error ==
      BlockInputError.MissingHead
  for extent in [0'u64, high(uint64)]:
    assert input.begin(chain, ByteLimit(extent), [], resources(wire.len), policies).error ==
        BlockInputError.InvalidExtent
  assert input.begin(chain, size, [], resources(wire.len - 1), policies).error ==
      BlockInputError.LimitExceeded
  var changed = policies
  changed.reporting.admission.frame.maxBytes = ByteLimit(uint64(wire.len - 1))
  assert input.begin(chain, size, [], resources(wire.len), changed).error ==
      BlockInputError.LimitExceeded
  for field in 0..<3:
    changed = policies
    case field
    of 0: changed.reporting.admission.frame.cores = CoreCount(3) # Head core profile cannot be substituted.
    of 1: changed.reporting.admission.frame.validators = ValidatorCount(
        7) # Validator domain belongs to this head.
    else: changed.reporting.admission.frame.epochSlots = EpochSlots(13) # Epoch domain is equally bound.
    assert input.begin(chain, size, [], resources(wire.len), changed).error ==
        BlockInputError.ProfileMismatch
  let parent = chain.chainView.bestBlock.value.header
  var bound = resources(wire.len)
  bound.ancestors = ElementLimit(0)
  assert input.begin(chain, size, [parent], bound, policies).error == BlockInputError.LimitExceeded
  bound = resources(wire.len)
  bound.ancestorBytes = ByteLimit(uint64(parent.headerInfo.value.consumed - 1))
  assert input.begin(chain, size, [parent], bound, policies).error == BlockInputError.LimitExceeded
  assert input.begin(chain, size, [default(OwnedHeader)], resources(wire.len), policies).error ==
      BlockInputError.InvalidAncestor
  assert input.stage == BlockInputStage.Idle and hashCalls() == 0
  var ancestors = @[parent]
  bound.ancestorBytes = ByteLimit(uint64(parent.headerInfo.value.consumed))
  let first = input.begin(chain, size, ancestors, bound, policies).value
  ancestors[0] = default(OwnedHeader) # The retained immutable handle is independent of this mutable container.
  assert input.begin(chain, size, [], bound, policies).error == BlockInputError.Busy
  assert input.append(first, wire, true) == BlockInputError.None
  failHash(0)
  let actual = input.prepare(first, chain)
  assert actual.error == BlockInputError.PreparationFailure
  assert actual.preparationFailure.error == ApplicationCandidateError.ReportFailure
  assert actual.preparationFailure.reportFailure.error == ReportAdmissionError.AnchorFailure
  assert actual.preparationFailure.reportFailure.anchorError == ReportAnchorError.BrokenAncestry,
    "the copied parent remains valid after caller mutation and is refused as a duplicate ancestor"
  failHash(1)
  assert not input.cancel(first)
  let second = input.begin(chain, size, [], resources(wire.len), policies).value
  assert second != first
  assert input.append(first, wire, true) == BlockInputError.StaleInput
  assert not input.cancel(first) and input.stage == BlockInputStage.Receiving
  assert input.prepare(first, chain).error == BlockInputError.StaleInput
  assert input.append(second, [], true) == BlockInputError.Truncated
  let third = input.begin(chain, ByteLimit(1), [], resources(1), policies).value
  assert input.append(third, [1'u8, 2], true) == BlockInputError.LimitExceeded
  assert input.stage == BlockInputStage.Idle and hashCalls() == 0
  failHash(0)

proc preparation(context: SeedFixture, wire: seq[byte]) =
  ## Exact decoding and actual stage causes survive consumption; a changed canonical head refuses before hashing.
  let chain = initialized(context)
  let before = chain.stateSnapshot.value
  let policies = preparationLimits()
  var input = default(BlockInput)
  let stale = input.receive(chain, wire, policies)
  let unrelated = initialized(context)
  failHash(1)
  assert input.prepare(stale, unrelated).error == BlockInputError.StateChanged
  assert input.stage == BlockInputStage.Idle and hashCalls() == 0
  failHash(0)
  var trailing = wire
  trailing.add(0)
  let extra = input.receive(chain, trailing, policies)
  failHash(1)
  assert input.prepare(extra, chain).error == BlockInputError.TrailingBytes
  assert hashCalls() == 0 and input.stage == BlockInputStage.Idle
  let invalid = input.receive(chain, [1'u8], policies)
  let malformed = input.prepare(invalid, chain)
  assert malformed.error == BlockInputError.DecodeFailure
  assert malformed.decodeFailure.error != FrameError.None and hashCalls() == 0
  failHash(0)
  var limited = policies
  limited.execution.completion.services = ElementLimit(0)
  let refused = input.receive(chain, wire, limited)
  let failed = input.prepare(refused, chain)
  assert failed.error == BlockInputError.PreparationFailure
  assert failed.preparationFailure.error == ApplicationCandidateError.RunnerFailure
  assert failed.preparationFailure.runnerFailure.error == AccumulationRunnerError.LimitExceeded
  let retry = input.receive(chain, wire, policies)
  let prepared = input.prepare(retry, chain)
  assert prepared.error == BlockInputError.None and input.stage == BlockInputStage.Idle
  assert sameStateSnapshot(before, prepared.value.finalAccumulationParent.value)
  assert sameStateSnapshot(before, chain.stateSnapshot.value)

proc deferred(context: SeedFixture, wire: seq[byte]) {.raises.} =
  ## Service intake binds its private canonical owner; Busy retains Ready input and adoption waits for tick.
  const path = "application-block-input-chain.json"
  writeFile(path, context.text)
  defer: discard posix.unlink("application-block-input-chain.json")
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", path, "--state-writes", "1000",
    "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "test")
  defer: owner.close()
  let before = owner.stateSnapshot.value
  let policies = preparationLimits()
  let composition = completionLimits().composition
  var input = default(BlockInput)
  let first = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [], resources(wire.len),
      policies).value
  assert input.append(first, wire, true) == BlockInputError.None
  let queued = owner.enqueueBlockInput(input, first, composition)
  assert queued.error == BlockInputError.None
  assert owner.accumulationStage == AccumulationHandoffStage.Pending
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  let second = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [], resources(wire.len),
      policies).value
  assert input.append(second, wire, true) == BlockInputError.None
  failHash(1)
  assert owner.enqueueBlockInput(input, second, composition).error == BlockInputError.Busy
  assert input.stage == BlockInputStage.Ready and hashCalls() == 0
  failHash(0)
  owner.tick(0)
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  failHash(1)
  assert owner.enqueueBlockInput(input, second, composition).error == BlockInputError.Busy
  assert hashCalls() == 0
  failHash(0)
  assert owner.takeAccumulation.error == ApplicationChainError.None
  failHash(1)
  assert owner.enqueueBlockInput(input, second, composition).error == BlockInputError.StateChanged
  assert hashCalls() == 0 and input.stage == BlockInputStage.Idle
  failHash(0)
  assert owner.chainView.retainedCount == 2
  assert not sameStateSnapshot(before, owner.stateSnapshot.value)

proc cycle(chain: ApplicationChain, wire: seq[byte], execute: bool) =
  ## Each cycle drops complete executed graphs or partially received payload/context without leaking ownership.
  var input = default(BlockInput)
  let id = input.begin(chain, ByteLimit(uint64(wire.len)), [], resources(wire.len),
      preparationLimits()).value
  if execute:
    assert input.append(id, wire, true) == BlockInputError.None
    assert input.prepare(id, chain).error == BlockInputError.None
  else:
    assert input.append(id, [wire[0]], false) == BlockInputError.None
    assert input.cancel(id) # Cancellation also releases the retained map and explicit policy graph.

proc main() {.raises.} =
  ## Decode the pinned report once, then test real signed blocks and scoped native ARC release.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Copy only initialized independent fixture bytes.
  let context = fixture(decodeOwnedReport(report, 2).value)
  let wire = encoded(context)
  fragmentation(context, wire)
  refusals(context, wire)
  preparation(context, wire)
  deferred(context, wire)
  let chain = initialized(context)
  cycle(chain, wire, true)
  cycle(chain, wire, false)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(chain, wire, iteration mod 2 ==
      0) # Every scoped receiver retires before measurement.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_block_input", 1000, before, after)
  echo "Application block input passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # File/fixture failures terminate the supported native suite.
except:
  quit(2)
