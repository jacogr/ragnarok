# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "accumulation_chain_arc_release"}

## Signed end-to-end state/chain adoption, hash-free parent preflight and atomic late-refusal rollback.

import std/[assertions, envvars, syncio]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[header, bounded, report_owned, state_layout, state_trie]
import ../../../src/state/[store, accumulation_chain, accumulation_state, accumulation_completion,
  accumulation_finalization, accumulation_times, accumulation_statistics, accumulation_validators,
  accumulation_activity, accumulation_consensus, report_admission, block_transition, block_admission]
import ../../support/[accumulation_activity_context, accumulation_completion_context, arc_evidence]

# Inject failures only after genuine signed finalized owners and structural parent views exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

type ChainFixture = object ## Retained real execution authority and its exact structurally captured original parent.
  source: PreparedFinalAccumulation
  parent: BlockSnapshotResult

proc settings(epoch = 12'u8): Parameters =
  ## Decode one complete fixture tuple; only the epoch domain changes for the preflight mismatch probe.
  let original = decodeParametersHex("ffffffffffffffff020000000000000003000000000000000200050000000c0000000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c0000000a000000").value
  var wire = original.encodeParameters
  wire[30] = epoch
  decodeParameters(wire).value

proc bytes(owner: OwnedHeader): seq[byte] =
  ## Re-emit the exact immutable sealed header from its source-bound metadata extent.
  result = newSeq[byte](owner.headerInfo.value.consumed)
  assert encodeOwnedHeader(owner, result).error == HeaderError.None

proc fixture(base: OwnedReport, uses = 0, available = false, blobs = false,
    disputed = false, ticket = false, rotated = false, writes = 1000'u64): ChainFixture =
  ## Every source is actually signed/executed; neither tests nor callers can forge a finalized certificate.
  let authored = activityFixture(base, guarantees = uses, available = available, blobs = blobs,
    provided = blobs, withDispute = disputed, withTicket = ticket, shiftPending = rotated,
    slot = (if rotated: 12'u32 else: 2'u32), storeWrites = writes)
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let binding = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  let captured = captureBlockSnapshot(bytes(binding.admittedParent),
      source.finalAccumulationParent.value,
    settings())
  assert captured.error == GenesisError.None
  ChainFixture(source: source, parent: captured)

proc seeded(context: ChainFixture): ChainView =
  ## Explicit finality remains on the retained parent through a best-head append.
  let initial = genesisView(context.parent)
  initial.finalizeView(context.parent.value.blockHash).value

proc unchanged(state: StateStore, view: ChainView, prior: StateStoreSnapshot, old: ChainView) =
  ## Failed staged operations preserve exact map identity, selected head, retained count and explicit finality.
  assert sameStateSnapshot(state.snapshot.value, prior)
  assert view.retainedCount == old.retainedCount
  assert array[32, byte](view.bestBlock.value.blockHash) == array[32, byte](
      old.bestBlock.value.blockHash)
  assert sameStateSnapshot(view.bestBlock.value.stateSnapshot, old.bestBlock.value.stateSnapshot)
  assert array[32, byte](view.finalizedBlock.value.blockHash) == array[32, byte](
      old.finalizedBlock.value.blockHash)

proc witness(context: ChainFixture) =
  ## Compare against independently spelled state apply, source-header capture and direct-child append.
  let parent = context.source.finalAccumulationParent.value
  let original = seeded(context)
  let header = context.source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted.admittedHeader
  var expectedState = forkStateStore(parent).value
  failHash(0)
  let expected = applyAccumulationState(expectedState, context.source, completionLimits().composition).value
  let child = captureBlockSnapshot(bytes(header), expected, settings())
  let expectedView = original.advanceView(child).value
  let expectedHashes = hashCalls()
  assert expectedHashes > 1
  var state = forkStateStore(parent).value
  var view = original
  let alias = state
  let oldTime = parent.lookup(chapterKey(StateChapter(11))).value
  failHash(0)
  let applied = applyAccumulationChain(state, view, context.source, completionLimits().composition)
  assert applied.error == AccumulationChainError.None, $applied.error
  assert hashCalls() == expectedHashes, "compose once and hash only the admitted sealed header afterward"
  let actual = applied.value
  assert sameStateSnapshot(actual.stateSnapshot, state.snapshot.value)
  assert sameStateSnapshot(actual.stateSnapshot, view.bestBlock.value.stateSnapshot)
  assert view.retainedCount == 2 and original.retainedCount == 1
  assert array[32, byte](actual.blockHash) == array[32, byte](
      expectedView.bestBlock.value.blockHash)
  assert array[32, byte](actual.stateRoot) == array[32, byte](expected.commitment.root)
  assert actual.keyCount == expected.commitment.entries
  for index in 0..<expected.commitment.entries:
    # Compare every posterior key, including newly created entries, against the independently applied map.
    let key = expected.keyAt(StateEntryIndex(index)).value
    assert actual.lookup(key).value.bytes == expected.lookup(key).value.bytes
  assert sameStateSnapshot(view.parentOf(actual.blockHash).value.stateSnapshot, parent)
  assert sameStateSnapshot(view.finalizedBlock.value.stateSnapshot, parent)
  assert actual.chainParameters.encodeParameters ==
      context.parent.value.chainParameters.encodeParameters
  assert sameStateSnapshot(alias.snapshot.value, parent)
  assert oldTime.bytes == @[1'u8, 0, 0, 0]
  failHash(1)
  assert applyAccumulationChain(state, view, context.source, default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.StaleState
  assert hashCalls() == 0
  assert sameStateSnapshot(state.snapshot.value, actual.stateSnapshot)
  failHash(0)
  var branch = alias
  var branchedView = original
  assert applyAccumulationChain(branch, branchedView, context.source, completionLimits(
    ).composition).error ==
    AccumulationChainError.None
  assert sameStateSnapshot(original.bestBlock.value.stateSnapshot, parent)

proc preflight(context: ChainFixture, foreign: ChainFixture) =
  ## Invalid source/target precedes missing or stale view checks; equal bytes cannot grant original-parent authority.
  let parent = context.source.finalAccumulationParent.value
  let original = seeded(context)
  var state = forkStateStore(parent).value
  var view = original
  var absent = default(StateStore)
  var empty = default(ChainView)
  failHash(1)
  assert applyAccumulationChain(absent, empty, default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.InvalidSource
  let missing = applyAccumulationChain(absent, view, context.source, default(AccumulationCompositionLimits))
  assert missing.error == AccumulationChainError.StateFailure and missing.stateError ==
      StateStoreError.Uninitialized
  assert applyAccumulationChain(state, empty, context.source, default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.UninitializedView
  var foreignState = forkStateStore(foreign.source.finalAccumulationParent.value).value
  assert applyAccumulationChain(foreignState, empty, context.source, default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.StaleState
  var foreignView = seeded(foreign)
  assert applyAccumulationChain(state, foreignView, context.source, default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.StaleView
  assert hashCalls() == 0
  failHash(0)
  var entries: seq[StateEntry] = @[]
  for index in 0..<parent.commitment.entries:
    # Reconstruct identical root bytes under a new owner to prove preflight uses version identity.
    let key = parent.keyAt(StateEntryIndex(index)).value
    entries.add(StateEntry(key: key, value: parent.lookup(key).value.bytes))
  let wire = bytes(context.parent.value.header)
  let reconstructed = captureBlockSnapshot(wire, entries, settings()).value
  assert array[32, byte](reconstructed.stateRoot) == array[32, byte](context.parent.value.stateRoot)
  var sameRoot = genesisView(captureBlockSnapshot(wire, reconstructed.stateSnapshot, settings()))
  var wrongProfile = genesisView(captureBlockSnapshot(wire, parent, settings(24)))
  failHash(1)
  assert applyAccumulationChain(state, sameRoot, context.source, default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.StaleView
  var rebuilt = forkStateStore(reconstructed.stateSnapshot).value
  assert applyAccumulationChain(rebuilt, view, context.source, default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.StaleState
  assert applyAccumulationChain(state, wrongProfile, context.source, default(
      AccumulationCompositionLimits)).error ==
    AccumulationChainError.ProfileMismatch
  assert hashCalls() == 0
  unchanged(state, view, parent, original)
  let uninitialized = default(AccumulationChainResult)
  assert uninitialized.error == AccumulationChainError.Uninitialized
  failHash(0)

proc failures(context: ChainFixture) =
  ## Private state, final capture hashing and a genuine failed direct-child append each roll both handles back.
  let policy = completionLimits().composition
  let parent = context.source.finalAccumulationParent.value
  let original = seeded(context)
  var state = forkStateStore(parent).value
  var view = original
  var short = policy
  short.consensus.chapterBytes = ByteLimit(0)
  let refused = applyAccumulationChain(state, view, context.source, short)
  assert refused.applicationFailure.compositionFailure.error ==
      AccumulationCompletionError.ConsensusFailure
  unchanged(state, view, parent, original)
  failHash(1)
  assert applyAccumulationChain(state, view, context.source, completionLimits(
    ).composition).error ==
    AccumulationChainError.ApplicationFailure
  failHash(0)
  unchanged(state, view, parent, original)
  var oracle = state
  discard applyAccumulationState(oracle, context.source, policy).value
  let compositionHashes = hashCalls()
  failAfter(compositionHashes - 1)
  let lateComposition = applyAccumulationChain(state, view, context.source, policy)
  failHash(0)
  assert lateComposition.applicationFailure.compositionFailure.consensusFailure.stateError ==
      StateStoreError.BackendFailure
  unchanged(state, view, parent, original)
  failAfter(compositionHashes)
  let captureRefused = applyAccumulationChain(state, view, context.source, policy)
  failHash(0)
  assert captureRefused.error == AccumulationChainError.CaptureFailure and
      captureRefused.captureError == GenesisError.Invalid
  unchanged(state, view, parent, original)
  var changed = bytes(context.parent.value.header)
  changed[changed.len - 1] = changed[changed.len -
      1] xor 1 # Structurally valid alternative seal keeps the same exact map but changes parent block identity.
  let otherParent = captureBlockSnapshot(changed, parent, settings())
  let wrong = genesisView(otherParent).finalizeView(otherParent.value.blockHash).value
  var wrongView = wrong
  let appendRefused = applyAccumulationChain(state, wrongView, context.source, policy)
  assert appendRefused.error == AccumulationChainError.ViewFailure and appendRefused.viewError ==
      ViewAdvanceError.NotChild
  unchanged(state, wrongView, parent, wrong)
  assert applyAccumulationChain(state, view, context.source, policy).error ==
      AccumulationChainError.None

proc cycle(context: ChainFixture, wrong: ChainView) =
  ## Repeated success/replay and late view refusal destroy their private composition/capture graphs each cycle.
  let policy = completionLimits().composition
  let parent = context.source.finalAccumulationParent.value
  var state = forkStateStore(parent).value
  var view = seeded(context)
  assert applyAccumulationChain(state, view, context.source, policy).error ==
      AccumulationChainError.None
  assert applyAccumulationChain(state, view, context.source, policy).error ==
      AccumulationChainError.StaleState
  var refused = forkStateStore(parent).value
  var wrongView = wrong
  assert applyAccumulationChain(refused, wrongView, context.source, policy).viewError ==
      ViewAdvanceError.NotChild
  assert sameStateSnapshot(refused.snapshot.value, parent)

proc main() {.raises.} =
  ## Genuine signed scenarios exercise admission through final publication without manufacturing result successes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  witness(fixture(base))
  witness(fixture(base, uses = 2))
  let context = fixture(base, uses = 2, available = true, blobs = true)
  witness(context)
  witness(fixture(base, disputed = true))
  witness(fixture(base, ticket = true))
  witness(fixture(base, rotated = true))
  preflight(context, fixture(base, uses = 1))
  failures(context)
  let capped = fixture(base, writes = 6)
  var limitedState = forkStateStore(capped.source.finalAccumulationParent.value).value
  var limitedView = seeded(capped)
  let limited = applyAccumulationChain(limitedState, limitedView, capped.source, completionLimits().composition)
  assert limited.applicationFailure.compositionFailure.consensusFailure.stateError ==
      StateStoreError.LimitExceeded
  unchanged(limitedState, limitedView, capped.source.finalAccumulationParent.value, seeded(capped))
  var detached = default(BlockSnapshot)
  block:
    # The returned child retains its map/header after all live and execution handles leave scope.
    let local = fixture(base)
    var localState = forkStateStore(local.source.finalAccumulationParent.value).value
    var localView = seeded(local)
    detached = applyAccumulationChain(localState, localView, local.source, completionLimits().composition).value
  assert detached.lookup(chapterKey(StateChapter(11))).value.bytes == @[2'u8, 0, 0, 0]
  var changed = bytes(context.parent.value.header)
  changed[changed.len - 1] = changed[changed.len - 1] xor 1
  let wrong = genesisView(captureBlockSnapshot(changed,
      context.source.finalAccumulationParent.value, settings()))
  cycle(context, wrong)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context, wrong) # Successful publication and late refusal release all temporary owners.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_chain", 1000, before, after)
  echo "Atomic accumulation state and chain adoption passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O errors must fail the native suite.
except:
  quit(2)
