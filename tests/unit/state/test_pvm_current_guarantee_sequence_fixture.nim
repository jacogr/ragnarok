# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A real adopted predecessor precedes authenticated guarantees requiring original lookup context; missing context cannot change canonical state.
import std/[assertions, syncio, envvars]
import ../../../src/app/[chain, candidate]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, state_layout]
import ../../../src/state/[store, accumulation_current_update, report_admission, guarantee_credentials]
import ../../support/[current_guarantee_sequence_context, current_consecutive_context,
  accumulation_current_chain_context, current_services_disk_samples]

proc main() {.raises.} =
  ## Actual phase composition freezes expected maps before the separate candidate wrapper checks missing and complete lookup inputs.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentGuaranteeSequenceFixture(decodeOwnedReport(bytes, 2).value)
  assert fixture.sequence.children.len == 2 and fixture.ancestors.len > 0
  let admission = fixture.sequence.seed.source.currentChainAdmission
  assert admission.reportCredentials.value.verifiedGuaranteeCount.value == 2
  let availability = chapterKey(StateChapter(10))
  assert fixture.sequence.heads[1].stateSnapshot.lookup(availability).value.bytes !=
      fixture.sequence.heads[2].stateSnapshot.lookup(availability).value.bytes
  var chain = initApplicationChain(genesisView(fixture.sequence.seed.parent)).value
  let first = prepareCurrentCandidate(chain, fixture.sequence.children[0], [],
      currentConsecutiveLimits())
  assert first.error == CurrentCandidateError.None
  chain.installPrepared(first.value)
  equalCurrentDiskMap(chain.stateSnapshot.value, fixture.sequence.heads[1].stateSnapshot)
  let before = chain.stateSnapshot.value
  let missing = prepareCurrentCandidate(chain, fixture.sequence.children[1], [],
      currentConsecutiveLimits())
  assert missing.error == CurrentCandidateError.ReportFailure
  assert sameStateSnapshot(before, chain.stateSnapshot.value)
  let completed = prepareCurrentCandidate(chain, fixture.sequence.children[1], fixture.ancestors,
      currentConsecutiveLimits())
  assert completed.error == CurrentCandidateError.None
  equalCurrentDiskMap(completed.value.currentUpdateState, fixture.sequence.heads[2].stateSnapshot)
  assert chain.canInstallPrepared(completed.value)
  chain.installPrepared(completed.value)
  assert chain.chainView.retainedCount == 3 and chain.chainView.finalizedBlock.error ==
      GenesisError.Unavailable
try:
  main()
except:
  quit(2) # Genuine signature, original lookup, admission or map failures cannot become a completed successor.
echo "PVM current guarantee sequence fixture passed"
