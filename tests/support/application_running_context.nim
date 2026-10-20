# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A signed parent commits one real gas-bounded self-loop before any asynchronous preparation.

import std/[assertions, strutils]
import ../../src/app/candidate
import ../../src/chain/parameters
import ../../src/lib/json_writer
import ../../src/codec/[bounded, block_codec, header, report_owned, state_layout,
  state_privileges, state_accounts, state_service_values, state_authorization, state_statistics, work_digest]
import ../../src/state/store
import ../../src/crypto/primitives
import ../../src/pvm/step
import ./[application_candidate_context, accumulation_runner_context,
  accumulation_execution_context, accumulation_activity_context, pvm_accumulation_context,
  pvm_accumulation_program]
import ./report_admission_context as signed_fixture

const RunningGas* = 40_000_000'u64 ## Finite guest credit, independent of test deadlines or host sleeps.

type RunningFixture* = object ## Detached exact wire bytes and complete seed text own no live worker aliases.
  seed*: string
  frame*: seq[byte]

proc hex(raw: openArray[byte]): string =
  ## Emit independent lowercase JSON hex without a production state serializer.
  result = ""
  for octet in raw: result.add(toHex(int(octet), 2).toLowerAscii()) # Preserve every committed byte.

proc runningLimits*(): ApplicationCandidateLimits =
  ## One allowance fits the explicit trusted round budget; local step capacity cannot terminate the loop early.
  result = preparationLimits()
  result.round.blockGas = Gas(RunningGas)
  result.execution.steps = ExecutionStepLimit(RunningGas)

proc runningFixture*(base: OwnedReport): RunningFixture =
  ## Commit the loop/preimage/allowance before recomputing roots and actual signatures; never forge a completion.
  result = RunningFixture(seed: "", frame: @[])
  var code = @[0'u8]
  for octet in guestEnvelope([@[40'u8, 0]]): code.add(
      octet) # Entry-5 static jump to itself, charged anew on every iteration.
  let hash = array[32, byte](blake2b256(code).value)
  let contexts = pvmContextConfig()
  let privileges = privilegeStateEntry(PrivilegeState(manager: ServiceIndex(0),
    delegator: ServiceIndex(0), assigners: @[ServiceIndex(0), ServiceIndex(0)],
    always: @[AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(RunningGas))]),
    executionRoundConfig().privileges).value
  let queues = authorizationEntry(AuthorizationKind.Queues,
    @[newSeq[AuthorizerHash](80), newSeq[AuthorizerHash](80)], contexts.queues).value
  let preimage = servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), code,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(code.len))).value
  var options = signed_fixture.signedBlockFixtureConfig()
  options.reports = 0
  options.accountCode = code
  options.extra = @[privileges, queues, preimage, activityParentEntry()]
  let context = signed_fixture.authored(base, options)
  let parent = context.original.snapshot.value
  var headerBytes = newSeq[byte](context.parent.headerInfo.value.consumed)
  assert encodeOwnedHeader(context.parent, headerBytes).error == HeaderError.None, "encode signed parent"
  var state = JsonObject()
  for index in 0..<parent.commitment.entries:
    let key = parent.keyAt(StateEntryIndex(index)).value
    state.add(hex(array[31, byte](key)), json(hex(parent.lookup(
        key).value.bytes))) # Complete original map, including committed loop code.
  result.seed = $jsonObject([("protocol_parameters", json(hex(runnerParameters(
    ).encodeParameters))),
    ("genesis_header", json(hex(headerBytes))), ("genesis_state", json(state))])
  let body = context.candidate.blockInfo.value.consumed
  result.frame = newSeq[byte](body + 4)
  for index in 0..<4: result.frame[index] = byte((uint64(body) shr (8 * index)) and
      255) # CE E4 framing remains unchanged.
  assert encodeBlock(Block(header: context.candidate.blockHeader.value,
    extrinsic: context.candidate.blockExtrinsic.value), preparationLimits(
    ).reporting.admission.frame,
    result.frame.toOpenArray(4, result.frame.high)).error == FrameError.None, "encode signed loop candidate"

proc assertRunningGas*(snapshot: StateStoreSnapshot) =
  ## Canonical post-adoption statistics must certify one real busy service, not a missing-code skip or cheap panic.
  let raw = snapshot.lookup(chapterKey(StateChapter(13))).value.bytes
  let decoded = decodeActivityState(raw, ActivityConfig(cores: CoreCount(2),
    current: ValidatorCount(6), previous: ValidatorCount(6), maxServices: ElementLimit(1),
    maxBytes: ByteLimit(4096)))
  assert decoded.error == ActivityError.None, "complete canonical running statistics"
  let activity = decoded.value.snapshot
  assert activity.activityInfo.value.services == 1, "one executed busy service"
  let service = activity.serviceActivityAt(StatisticsServiceIndex(0)).value
  assert service.service == ServiceIndex(42), "committed busy service identity"
  assert uint64(service.statistics.counters[ServiceMeasure.AccumulationCount]) == 0,
    "allowance-only loop has no accumulated report digests"
  let used = uint64(service.statistics.accumulationGas)
  assert used <= RunningGas and used > RunningGas - 1000,
    "self-loop consumes its finite gas credit: " &
        $used # The final unaffordable block is bounded by the 1000-cycle pricing ceiling.
