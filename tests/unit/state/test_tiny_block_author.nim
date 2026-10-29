# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Six distinct native signing roles cross a Tiny epoch through ordinary candidate validation.
import std/[assertions, syncio]
import "../../../src/app/block/author" as block_author
import ../../../src/app/[tiny_genesis, chain, candidate]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, block_codec]
import ../../../src/state/store
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/bandersnatch/bandersnatch
import ../../support/current_consecutive_context

proc main() {.raises.} =
  ## Correct keys produce one eligible block; wrong keys, stale slots, invalid seals and replay preserve the exact parent.
  let initial = initTinyGenesis()
  assert initial.error == GenesisError.None
  var storeLimits = genesisStoreLimits()
  storeLimits.writes = ElementLimit(1000)
  storeLimits.writeValueBytes = ByteLimit(1048576)
  let loaded = initApplicationChain(tinyChainText(initial.value), storeLimits)
  assert loaded.error == ApplicationChainError.None
  var chain = loaded.value
  let limits = currentConsecutiveLimits()
  var initialWire = newSeq[byte](297)
  assert initial.value.header.encodeOwnedHeader(initialWire).error == HeaderError.None
  let fuzzSeed = captureFuzzSeedSnapshot(initialWire, initial.value.stateSnapshot,
    initial.value.chainParameters)
  assert fuzzSeed.error == GenesisError.None
  let fuzzRefusal = authorEmptyBlock(fuzzSeed.value, HeaderSlot(1), tinySigningKey(1).value,
    limits.reporting.admission.frame, limits.reporting.safrole)
  assert fuzzRefusal.error == BlockAuthorError.InvalidProfile
  var wrongProfile = limits.reporting.admission.frame
  wrongProfile.epochSlots = EpochSlots(600)
  let profileRefusal = authorEmptyBlock(initial.value, HeaderSlot(1), tinySigningKey(1).value,
    wrongProfile, limits.reporting.safrole)
  assert profileRefusal.error == BlockAuthorError.InvalidProfile
  var shortFrame = limits.reporting.admission.frame
  shortFrame.maxBytes = ByteLimit(303)
  let shortRefusal = authorEmptyBlock(initial.value, HeaderSlot(1), tinySigningKey(1).value,
    shortFrame, limits.reporting.safrole)
  assert shortRefusal.error == BlockAuthorError.LimitExceeded
  var produced = default(array[6, int])
  for slot in 1..14:
    let parent = chain.chainView.bestBlock.value
    let original = parent.stateSnapshot
    var eligible = 0
    var child = default(OwnedBlock)
    for index in 0..<6:
      let key = tinySigningKey(index)
      assert key.error == BsError.None
      let authored = authorEmptyBlock(parent, HeaderSlot(uint32(slot)), key.value,
        limits.reporting.admission.frame, limits.reporting.safrole)
      if authored.error == BlockAuthorError.None:
        inc eligible
        inc produced[index]
        child = authored.value
      else:
        assert authored.error == BlockAuthorError.NotEligible # An incorrect key must never seal another validator's slot.
      assert sameStateSnapshot(original, chain.stateSnapshot.value)
    assert eligible == 1
    let repeated = authorEmptyBlock(parent, HeaderSlot(parent.slot), tinySigningKey(0).value,
      limits.reporting.admission.frame, limits.reporting.safrole)
    assert repeated.error == BlockAuthorError.InvalidSlot
    var damaged = newSeq[byte](65536)
    let encoded = encodeOwnedBlock(child, damaged)
    assert encoded.error == FrameError.None
    damaged.setLen(encoded.value)
    damaged[damaged.len-8] = damaged[damaged.len-8] xor 1 # Corrupt the seal while preserving all body framing.
    let parsed = decodeBlock(damaged, limits.reporting.admission.frame)
    assert parsed.error == FrameError.None
    let refused = prepareCurrentCandidate(chain, parsed.value.owner, [], limits)
    assert refused.error != CurrentCandidateError.None
    assert sameStateSnapshot(original, chain.stateSnapshot.value)
    let prepared = prepareCurrentCandidate(chain, child, [], limits)
    if prepared.error != CurrentCandidateError.None:
      echo "candidate ", $prepared.error
    assert prepared.error == CurrentCandidateError.None
    assert chain.canInstallPrepared(prepared.value)
    chain.installPrepared(prepared.value)
    assert chain.chainView.bestBlock.value.slot == uint32(slot)
    let replay = prepareCurrentCandidate(chain, child, [], limits)
    assert replay.error != CurrentCandidateError.None
    assert sameStateSnapshot(chain.stateSnapshot.value, prepared.value.currentUpdateState)
  for count in produced: assert count > 0 # Every process identity authors during the first complete epoch.
  assert chain.chainView.finalizedBlock.error == GenesisError.Unavailable
try:
  main()
except:
  quit(2) # Genuine runtime/candidate/primitive failure is never an expected refusal control.
echo "Tiny block author passed"
