# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Separate candidate preparation reproduces every complete phase-composed successor of genuine consecutive signed blocks.
import std/[assertions, syncio, envvars]
import ../../../src/app/[chain, candidate]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, header]
import ../../../src/codec/state/[layout as state_layout, safrole as state_safrole]
import ../../../src/codec/bounded
import ../../../src/state/store
import ../../../src/state/accumulation/current/[update as accumulation_current_update,
    consensus as accumulation_current_consensus]
import ../../support/[current_consecutive_context, current_rotated_sequence_context,
    accumulation_current_chain_context, current_services_disk_samples]

proc main() {.raises.} =
  ## Three current successors preserve parent authority, exact full maps and original aliases while refusing old-child replay.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentRotatedSequenceFixture(decodeOwnedReport(bytes, 2).value)
  assert fixture.children.len == 3 and fixture.heads.len == 4
  assert uint32(fixture.heads[0].slot) == 1 and uint32(fixture.heads[1].slot) == 12 and uint32(
      fixture.heads[2].slot) == 13 and uint32(fixture.heads[3].slot) == 14
  let key = chapterKey(StateChapter(8))
  let previous = chapterKey(StateChapter(9))
  let original = fixture.heads[0].stateSnapshot.lookup(key).value.bytes
  let rotated = fixture.heads[1].stateSnapshot.lookup(key).value.bytes
  assert original != rotated # Explicit Ed25519 ordering rotates, while the uniform fallback seal key remains valid.
  assert fixture.heads[1].stateSnapshot.lookup(previous).value.bytes == original
  for index in 2..3:
    assert fixture.heads[index].stateSnapshot.lookup(key).value.bytes == rotated
    assert fixture.heads[index].stateSnapshot.lookup(previous).value.bytes == original

  equalCurrentDiskMap(fixture.heads[1].stateSnapshot,
      fixture.seed.source.currentConsensusState.value)
  var chain = initApplicationChain(genesisView(fixture.seed.parent)).value
  var ancestors = fixture.seed.older
  let historical = chain.stateSnapshot.value
  for index, child in fixture.children:
    let before = chain.chainView.bestBlock.value
    let prepared = prepareCurrentCandidate(chain, child, ancestors, currentConsecutiveLimits())
    assert prepared.error == CurrentCandidateError.None, "genuine consecutive candidate"
    assert sameStateSnapshot(chain.stateSnapshot.value, before.stateSnapshot)
    let update = prepared.value
    equalCurrentDiskMap(update.currentUpdateState, fixture.heads[index+1].stateSnapshot)
    assert array[32, byte](update.currentUpdateChild.blockHash) == array[32, byte](fixture.heads[
        index+1].blockHash)
    assert array[32, byte](update.currentUpdateChild.parentHash) == array[32, byte](
        before.blockHash)
    assert array[32, byte](update.currentUpdateChild.header.headerInfo.value.unsigned.priorState) ==
        array[32, byte](before.stateSnapshot.commitment.root)
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    assert chain.chainView.retainedCount == index+2
    assert chain.chainView.finalizedBlock.error == GenesisError.Unavailable
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # The next original prefix is explicit, never synthesized from a root.
  equalCurrentDiskMap(historical, fixture.seed.parent.value.stateSnapshot)
  let replay = prepareCurrentCandidate(chain, fixture.children[0], ancestors,
      currentConsecutiveLimits())
  assert replay.error != CurrentCandidateError.None
  equalCurrentDiskMap(chain.stateSnapshot.value, fixture.heads[3].stateSnapshot)
try:
  main()
except:
  quit(2) # Native proof, admission, execution or complete-map failure remains a strict suite failure.
echo "PVM current rotated fixture passed"
