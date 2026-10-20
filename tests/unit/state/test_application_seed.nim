# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_seed_arc_release"}

## Explicit configured seed policies, one-pass capture and genuine re-admission against the newly decoded owner.

import std/[assertions, syncio, envvars, strutils]
import ../../../src/app/chain
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/rpc/protocol
import ../../../src/json_writer
import ../../../src/codec/[header, bounded, report_owned, state_layout, state_trie]
import ../../../src/state/[store, accumulation_state, accumulation_chain, accumulation_completion,
  accumulation_finalization, accumulation_times, accumulation_statistics, accumulation_validators,
  accumulation_activity, accumulation_round, accumulation_queue, accumulation_runner,
  accumulation_driver, report_admission, block_transition, block_admission]
import ../../support/[accumulation_activity_context, accumulation_completion_context,
  accumulation_execution_context, accumulation_runner_context, arc_evidence]
import ../../support/report_admission_context as report_fixture

# Backend faults begin after all authored source/context bytes are independently retained.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

type SeedFixture = object ## Test text comes from a genuine signed original parent; its original certificate remains a separate owner.
  text: string
  source: PreparedFinalAccumulation
  header: seq[byte]
  entries: seq[StateEntry]

proc hex(value: openArray[byte]): string =
  ## Emit canonical lowercase hexadecimal independently of the production configuration decoder.
  result = ""
  for octet in value: result.add(toHex(int(octet), 2).toLowerAscii())

proc policy(writes = 1000'u64, bytes = 1000000'u64): StateStoreLimits =
  ## Writable mutation ceilings are caller decisions; fixed trie capture ceilings retain the legacy limits.
  result = genesisStoreLimits()
  result.writes = ElementLimit(writes)
  result.writeValueBytes = ByteLimit(bytes)

proc fixture(base: OwnedReport): SeedFixture =
  ## Capture all original entries of an empty signed block, including opaque and service chapters.
  let authored = activityFixture(base)
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let parent = source.finalAccumulationParent.value
  let bound = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  var wire = newSeq[byte](bound.admittedParent.headerInfo.value.consumed)
  assert encodeOwnedHeader(bound.admittedParent, wire).error == HeaderError.None
  var entries: seq[StateEntry] = @[]
  var state = JsonObject()
  for index in 0..<parent.commitment.entries:
    let key = parent.keyAt(StateEntryIndex(index)).value
    let value = parent.lookup(key).value.bytes
    entries.add(StateEntry(key: key, value: value)) # Independent complete-map oracle retains every exact key/value.
    state.add(hex(array[31, byte](key)), json(hex(value)))
  let text = $jsonObject([("protocol_parameters", json(hex(runnerParameters().encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(state))])
  SeedFixture(text: text, source: source, header: wire, entries: entries)

proc witness(context: SeedFixture) =
  ## Compare direct map/capture work with configured initialization; every returned view shares the exact new version.
  let limits = policy()
  failHash(0)
  let direct = newStateStore(context.entries, limits).value.snapshot.value
  let captured = captureBlockSnapshot(context.header, direct, runnerParameters()).value
  let cost = hashCalls()
  failHash(0)
  let seeded = initApplicationChain(context.text, limits)
  assert seeded.error == ApplicationChainError.None
  assert hashCalls() == cost, "one complete trie commitment and one sealed-header hash"
  let owner = seeded.value
  let current = owner.stateSnapshot.value
  let head = owner.chainView.bestBlock.value
  assert sameStateSnapshot(current, head.stateSnapshot)
  assert not sameStateSnapshot(current, context.source.finalAccumulationParent.value)
  assert array[32, byte](current.commitment.root) == array[32, byte](captured.stateRoot)
  assert head.keyCount == context.entries.len
  assert head.chainParameters.encodeParameters == runnerParameters().encodeParameters
  for entry in context.entries:
    assert current.lookup(entry.key).value.bytes ==
        entry.value # Configured hex and structured JSON preserve every original byte.
  let legacy = configuredGenesis(context.text, runnerParameters()).value
  assert array[32, byte](legacy.stateRoot) == array[32, byte](head.stateRoot)
  assert array[32, byte](legacy.blockHash) == array[32, byte](head.blockHash)
  var readonly = forkStateStore(legacy.stateSnapshot).value
  assert readonly.apply([StateWrite(key: chapterKey(StateChapter(249)), kind: StateWriteKind.Put,
    value: @[1'u8])]).error == StateStoreError.LimitExceeded
  var mutable = forkStateStore(current).value
  assert mutable.apply([StateWrite(key: chapterKey(StateChapter(249)), kind: StateWriteKind.Put,
    value: @[1'u8])]).error == StateStoreError.None
  assert current.lookup(chapterKey(StateChapter(249))).error == StateStoreError.MissingKey
  var copy = owner
  failHash(1)
  let foreign = copy.applyAccumulation(context.source, completionLimits().composition)
  assert foreign.chainFailure.error == AccumulationChainError.StaleState and hashCalls() == 0
  failHash(0)
  var text = context.text
  let detached = initApplicationChain(text, limits).value
  text = "invalid" # The configured owner retains no caller text or decoded mutable buffers.
  assert detached.stateSnapshot.value.lookup(chapterKey(StateChapter(11))).value.bytes == @[1'u8, 0, 0, 0]

proc limits(context: SeedFixture) =
  ## Independent mutation and trie ceilings survive initialization without widening or silent clamping.
  let writes = [StateWrite(key: chapterKey(StateChapter(248)), kind: StateWriteKind.Put, value: @[1'u8]),
    StateWrite(key: chapterKey(StateChapter(249)), kind: StateWriteKind.Put, value: @[2'u8])]
  let limited = initApplicationChain(context.text, policy(1)).value
  var branch = forkStateStore(limited.stateSnapshot.value).value
  assert branch.apply(writes).error == StateStoreError.LimitExceeded
  assert branch.apply([writes[0]]).error == StateStoreError.None
  let bytes = initApplicationChain(context.text, policy(bytes = 1)).value
  branch = forkStateStore(bytes.stateSnapshot.value).value
  assert branch.apply(writes).error == StateStoreError.LimitExceeded
  let readonly = initApplicationChain(context.text, genesisStoreLimits()).value
  branch = forkStateStore(readonly.stateSnapshot.value).value
  assert branch.apply([writes[0]]).error == StateStoreError.LimitExceeded
  for index in 0..<4:
    var broad = policy()
    case index
    of 0: broad.trie.items = ElementLimit(16385) # Startup policy cannot admit a larger future map than chain capture.
    of 1: broad.trie.perValue = ByteLimit(4 * 1024 * 1024 + 1) # Independent per-value ceiling stays fixed.
    of 2: broad.trie.totalValueBytes = ByteLimit(4 * 1024 * 1024 + 1) # Aggregate ceiling is checked separately.
    else: broad.trie.nodes = TrieNodeLimit(1048577) # Reject broad node work before any hashing.
    failHash(1)
    let refused = initApplicationChain(context.text, broad)
    assert refused.genesisFailure == GenesisError.Invalid and hashCalls() == 0
    failHash(0)
  var short = policy()
  short.trie.items = ElementLimit(uint64(context.entries.len - 1))
  assert initApplicationChain(context.text, short).genesisFailure == GenesisError.Invalid
  short = policy()
  short.trie.perValue = ByteLimit(0)
  assert initApplicationChain(context.text, short).genesisFailure == GenesisError.Invalid
  short = policy()
  short.trie.totalValueBytes = ByteLimit(1)
  assert initApplicationChain(context.text, short).genesisFailure == GenesisError.Invalid
  short = policy()
  short.trie.nodes = TrieNodeLimit(0)
  assert initApplicationChain(context.text, short).genesisFailure == GenesisError.Invalid

proc refusals(context: SeedFixture) =
  ## Missing/bad parameters precede absent/invalid genesis; failures and late primitive refusal retain no partial owner.
  let limits = policy()
  for text in ["", "{}", "[]", context.text & " trailing", "\xff", repeat(" ", 8 * 1024 * 1024 + 1)]:
    failHash(1)
    let invalid = initApplicationChain(text, limits)
    assert invalid.error == ApplicationChainError.ParametersFailure and hashCalls() == 0
    discard invalid.parametersError
    failHash(0)
  let prefix = "{\"protocol_parameters\":\"" & hex(runnerParameters().encodeParameters) & "\""
  let missing = initApplicationChain(prefix & "}", limits)
  assert missing.error == ApplicationChainError.GenesisFailure and missing.genesisFailure ==
      GenesisError.Unavailable
  for suffix in [",\"genesis_header\":\"00\"}", ",\"genesis_state\":{}}",
    ",\"genesis_header\":false,\"genesis_state\":{}}",
    ",\"genesis_header\":\"00\",\"genesis_state\":[]}",
    ",\"genesis_header\":\"0x00\",\"genesis_state\":{}}",
    ",\"genesis_header\":\"00\",\"genesis_state\":{\"00\":\"00\"}}"]:
    assert initApplicationChain(prefix & suffix, limits).genesisFailure == GenesisError.Invalid
  let duplicateRoot = context.text.substr(0, context.text.len - 2) &
    ",\"protocol_parameters\":\"" & hex(runnerParameters().encodeParameters) & "\"}"
  failHash(1)
  assert initApplicationChain(duplicateRoot, limits).error ==
      ApplicationChainError.ParametersFailure
  assert hashCalls() == 0
  failHash(0)
  var state = JsonObject()
  for entry in context.entries:
    state.add(hex(array[31, byte](entry.key)), json(hex(
        entry.value))) # Preserve required roster/time while adding ambiguous or excessive entries.
  let first = context.entries[0]
  var duplicate = state
  duplicate.add(hex(array[31, byte](first.key)).toUpperAscii(), json(hex(first.value)))
  let ambiguous = $jsonObject([("protocol_parameters", json(hex(runnerParameters(
    ).encodeParameters))),
    ("genesis_header", json(hex(context.header))), ("genesis_state", json(duplicate))])
  failHash(1)
  assert initApplicationChain(ambiguous, limits).genesisFailure == GenesisError.Invalid
  assert hashCalls() == 0
  failHash(0)
  for index in 0..<(16385 - context.entries.len):
    var key = default(array[31, byte])
    key[0] = 248
    key[1] = byte(index and 255)
    key[2] = byte(index shr 8)
    state.add(hex(key), json("")) # Distinct opaque keys cross only the entry cap, within the total text/value budgets.
  let excessive = $jsonObject([("protocol_parameters", json(hex(runnerParameters(
    ).encodeParameters))),
    ("genesis_header", json(hex(context.header))), ("genesis_state", json(state))])
  failHash(1)
  assert initApplicationChain(excessive, limits).genesisFailure == GenesisError.Invalid
  assert hashCalls() == 0
  failHash(0)
  failHash(1)
  let early = initApplicationChain(context.text, limits)
  assert early.genesisFailure == GenesisError.Invalid
  failHash(0)
  discard initApplicationChain(context.text, limits).value
  let cost = hashCalls()
  failAfter(cost - 1)
  let late = initApplicationChain(context.text, limits)
  failHash(0)
  assert late.genesisFailure == GenesisError.Invalid
  assert initApplicationChain(context.text, limits).error == ApplicationChainError.None

proc execution(owner: var ApplicationChain, context: SeedFixture): PreparedFinalAccumulation =
  ## Re-admit the actual signed empty block against the decoded seed, then use only existing PVM execution/finalization owners.
  let bound = context.source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  var working = forkStateStore(owner.stateSnapshot.value).value
  let staged = report_fixture.stage(working, bound.admittedBlock, bound.admittedParent)
  assert staged.error == BlockTransitionError.None
  let reports = planBlockReports(staged, [], report_fixture.config())
  assert reports.error == ReportAdmissionError.None
  let queue = planBlockAccumulationQueue(reports.value, executionQueueConfig()).value
  let round = planBlockInitialAccumulation(queue, executionRoundConfig()).value
  let parameters = owner.chainView.bestBlock.value.chainParameters
  let initial = runBlockAccumulation(round, parameters, runnerLimits()).value
  let stopped = driveAccumulation(initial, parameters, completionDriverLimits()).value
  result = prepareFinalAccumulation(stopped, completionLimits().finalization).value
  assert sameStateSnapshot(result.finalAccumulationParent.value, owner.stateSnapshot.value)

proc adopt(context: SeedFixture) =
  ## The genuine source bound to the new seed succeeds; the separate equal-root original source never substitutes authority.
  let composition = completionLimits().composition
  var owner = initApplicationChain(context.text, policy()).value
  let parent = owner.stateSnapshot.value
  let final = execution(owner, context)
  let applied = owner.applyAccumulation(final, composition)
  assert applied.error == ApplicationChainError.None
  assert sameStateSnapshot(applied.value.stateSnapshot, owner.stateSnapshot.value)
  assert owner.stateSnapshot.value.lookup(chapterKey(StateChapter(11))).value.bytes == @[2'u8, 0, 0, 0]
  assert parent.lookup(chapterKey(StateChapter(11))).value.bytes == @[1'u8, 0, 0, 0]
  var capped = initApplicationChain(context.text, policy(6)).value
  let cappedParent = capped.stateSnapshot.value
  let cappedFinal = execution(capped, context)
  let refused = capped.applyAccumulation(cappedFinal, completionLimits().composition)
  assert refused.chainFailure.applicationFailure.compositionFailure.consensusFailure.stateError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(cappedParent, capped.stateSnapshot.value)

proc cycle(context: SeedFixture) =
  ## Configured success plus short-policy refusal releases parser tokens, decoded buffers and all private owners.
  let limits = policy()
  let seeded = initApplicationChain(context.text, limits)
  assert seeded.error == ApplicationChainError.None
  var short = limits
  short.trie.items = ElementLimit(0)
  assert initApplicationChain(context.text, short).genesisFailure == GenesisError.Invalid

proc main() {.raises.} =
  ## Decode the pinned independent report before any genuine fixture signing or configured seed tests.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let context = fixture(decodeOwnedReport(wire, 2).value)
  witness(context)
  limits(context)
  refusals(context)
  adopt(context)
  cycle(context)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context) # Each returned candidate and failed parse/capture graph leaves scope.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_seed", 1000, before, after)
  echo "Explicit configured application seeds passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O errors must fail the native suite.
except:
  quit(2)
