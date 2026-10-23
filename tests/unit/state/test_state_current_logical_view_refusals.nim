# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine next current preparations with the same exact parent map cannot replace original ordered history, finality or full economic configuration.
# @@Verification={"arc":"state_current_logical_view_refusals_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_repeated_logical_context, current_identity_context,
    accumulation_current_candidate_context, accumulation_current_chain_context,
    application_download_chain, arc_evidence]
import ../../../src/state/[current_identities, current_logical, current_state, current_globals,
    current_profile, accumulation_current_update, store]
import ../../../src/chain/[provider, genesis, parameters]
import ../../../src/app/[chain, candidate]
import ../../../src/codec/[bounded, report_owned]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Every alternative is genuinely prepared before hash-free original-view comparison.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Context/view rejection cannot rehash or infer a replacement root authority.
proc prepare(source: PreparedCurrentChainUpdate, view: ChainView): PreparedCurrentChainUpdate =
  ## Only maintained signed empty block bytes are reused; actual current candidate owns each changed-prior-view preparation.
  let bounds = view.viewRetentionInfo
  assert bounds.owners <= 9 and bounds.bytes <= 8388608
  let application = initApplicationChain(view).value
  var limits = currentCandidateLimits()
  limits.completion.composition.validators.services = ElementLimit(2)
  prepareCurrentCandidate(application, signedChild(source.currentUpdateChild), [], limits).value
proc check(source: CurrentLogicalState, updates: openArray[PreparedCurrentChainUpdate]) =
  ## Actual same-map prepared parents with changed context must fail full-view provenance before any continuation prefix.
  for update in updates:
    assert preserveCurrentIdentities(source, update, currentIdentityTestLimits).error ==
        CurrentIdentityError.ViewMismatch
proc main() {.raises.} =
  ## Original completed source has ordered1/2 history and explicit finalized1; all alternatives keep exact physical head2.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  let previous = fixture.first.update
  let view = previous.currentUpdateView
  assert view.retainedCount == 2 and view.finalizedBlock.value.slot == 1
  let finalized = view.finalizeView(previous.currentUpdateChildContext.hash).value
  let absent = restoreLocalChainView([view.retainedBlockAt(RetainedBlockIndex(0)),
      view.retainedBlockAt(RetainedBlockIndex(1))]).value
  let shortened = restoreLocalChainView([view.retainedBlockAt(RetainedBlockIndex(1))],
      view.finalizedBlock).value
  var parameterWire = previous.currentUpdateChildContext.parameters.encodeParameters
  parameterWire[8] = 1 # Only original zero byte-price changes; core/current/previous/epoch cardinalities remain identical.
  let alternative = decodeParameters(parameterWire).value
  var history: seq[BlockSnapshotResult] = @[]
  for i in 0..<view.retainedCount:
    let snapshot = view.retainedBlockAt(RetainedBlockIndex(i)).value
    let captured = captureBlockSnapshot(currentChainBytes(snapshot.header), snapshot.stateSnapshot, alternative)
    assert captured.error == GenesisError.None
    history.add(captured) # Honest structural recapture retains original exact state/header ownership under its explicitly different configured tuple.
  let repriced = restoreLocalChainView(history, history[0]).value
  let updates = [prepare(previous, finalized), prepare(previous, absent), prepare(previous,
      shortened), prepare(previous, repriced)]
  for update in updates:
    assert sameStateSnapshot(update.currentUpdatePriorState, previous.currentUpdateState)
  let different = updates[3].currentUpdatePriorView.bestBlockContext
  let original = previous.currentUpdateChildContext
  assert different.parameters.get(coreCount) == original.parameters.get(coreCount)
  assert different.parameters.get(epochPeriod) == original.parameters.get(epochPeriod)
  assert uint64(different.validators) == uint64(original.validators)
  assert different.parameters.encodeParameters != original.parameters.encodeParameters
  assert shortened.retainedCount == 1 and shortened.finalizedBlock.value.slot == 1
  assert finalized.retainedCount == 2 and finalized.finalizedBlock.value.slot == 2
  assert absent.retainedCount == 2 and absent.finalizedBlock.error == GenesisError.Unavailable
  fail(1)
  check(fixture.logical, updates)
  assert preserveCurrentIdentities(fixture.logical, fixture.next,
      currentIdentityTestLimits).error == CurrentIdentityError.None
  assert sameChainView(previous.currentUpdateView, view) and calls() == 0
  for i in 0..<25: check(fixture.logical, updates)
  let before = getOccupiedMem()
  for i in 0..<1000: check(fixture.logical, updates)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_logical_view_refusals", 1000, before, finalBytes)
  fail(0)
  echo "state-current-logical-view-refusals: ok"
try:
  main()
except:
  quit(2) # A failed changed-prior candidate cannot substitute the genuine same-parent/full-view mismatch witnesses.
