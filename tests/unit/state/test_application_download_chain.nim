# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_download_chain_arc_release"}

## Successive genuine signed blocks consume the previously composed map and preserve exact parent history.
import std/[assertions, syncio, envvars]
import ../../../src/app/[chain, candidate]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, report_owned]
import ../../support/[application_download_chain, application_candidate_context,
  accumulation_completion_context, arc_evidence]

proc cycle(context: DownloadChainFixture) =
  ## An independent decoded seed executes each retained signed child and releases all composed owners on return.
  var working = initialized(context.seed)
  var older: seq[OwnedHeader] = @[]
  for index, child in context.children:
    let parent = working.chainView.bestBlock.value
    let prepared = prepareCandidate(working, child, older, preparationLimits())
    assert prepared.error == ApplicationCandidateError.None, "replayed chain preparation " &
        $index & " " & $prepared.error
    let adopted = working.applyAccumulation(prepared.value, chainCompositionLimits())
    assert adopted.error == ApplicationChainError.None, "replayed chain composition " & $index &
        " " & $adopted.error
    assert array[32, byte](adopted.value.parentHash) == array[32, byte](parent.blockHash)
    assert sameCompleteState(adopted.value.stateSnapshot, context.heads[index + 1].stateSnapshot)
    assert working.chainView.retainedCount == index + 2
    assert working.chainView.parentOf(adopted.value.blockHash).error == GenesisError.None
    var next = @[parent.header]
    for owner in older: next.add(owner) # Validate the complete newest-first chain on every subsequent report-admission pass.
    older = next
  let before = working.stateSnapshot.value
  let replay = prepareCandidate(working, context.children[0], older, preparationLimits())
  assert replay.error == ApplicationCandidateError.BlockFailure
  assert sameCompleteState(working.stateSnapshot.value, before)
  assert working.chainView.finalizedBlock.error == GenesisError.Unavailable

proc main() {.raises.} =
  ## The source-owned report fixture seeds real code/state; later signatures use each actual selected parent.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(wire, 2).value)
  assert context.children.len == 3 and context.heads.len == 4
  for index in 0..<context.children.len:
    assert uint32(context.heads[index + 1].slot) == uint32(context.heads[index].slot) + 1
    assert expectedRequest(context.heads[index]) != expectedRequest(context.heads[index +
        1]) # Replaying the old CE request cannot request the next child.
  cycle(context)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context) # Genuine sequential execution/composition must release all per-run state graphs.
  let after = getOccupiedMem()
  assert before == after, "sequential ARC release " & $before & " " & $after
  recordArcRelease("application_download_chain", 1000, before, after)
  echo "PASS application download chain: genuine successive signatures, full-map parity and stale refusal"
try:
  main() # Fixture/native failures cannot masquerade as a successful chain.
except:
  quit(2)
