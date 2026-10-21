# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_roundtrip_arc_release"}

## Exact checkpoint roundtrips preserve complete state while importing no producer history, finality or mutation policy.
import std/[assertions, syncio, envvars]
import ../../../src/app/[chain, candidate, checkpoint_identity, checkpoint_codec, checkpoint_recovery]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, report_owned, state_layout]
import ../../../src/state/store
import ../../support/application_candidate_context as candidate_context
import ../../support/accumulation_completion_context
import ../../support/[application_recovery_execution, arc_evidence]
proc cycle(envelope, sealed: seq[byte], expected: ApplicationCheckpointIdentity) =
  ## All restored graph and re-encoded byte owners retire before the next memory observation.
  let restored = decodeRecoveryCheckpoint(envelope, sealed, expected, genesisStoreLimits(),
      ByteLimit(high(uint64))).value
  assert restored.chainView.retainedCount == 1
  assert restored.chainView.finalizedBlock.error != GenesisError.None
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(restored).value, expected)
  assert encodeApplicationCheckpoint(restored, ByteLimit(high(uint64))).value == envelope
proc main() {.raises.} =
  ## Genuine execution creates two retained blocks before caller-certified finality is selected solely for this local serialization witness.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Initialize every fixture octet before owned report decode.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  var producer = candidate_context.initialized(fixture.origin)
  let prepared = producer.prepareCandidate(candidate_context.candidateBlock(fixture.origin), [],
      candidate_context.preparationLimits())
  assert prepared.error == ApplicationCandidateError.None
  assert producer.applyAccumulation(prepared.value, completionLimits().composition).error ==
      ApplicationChainError.None
  assert producer.chainView.retainedCount == 2
  let head = producer.chainView.bestBlock.value
  let parent = producer.chainView.parentOf(head.blockHash).value
  let expected = captureApplicationCheckpointIdentity(producer).value
  let envelope = encodeApplicationCheckpoint(producer, ByteLimit(high(uint64))).value
  let header = head.header
  var sealed = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, sealed).error == HeaderError.None
  for selected in [parent.blockHash, head.blockHash]:
    let finalized = producer.chainView.finalizeView(selected)
    assert finalized.error == ViewFinalizeError.None
    let source = initApplicationChain(finalized.value).value
    assert source.chainView.retainedCount == 2
    assert source.chainView.finalizedBlock.error == GenesisError.None
    assert encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value ==
        envelope # Checkpoint format contains selected context/map, not provider history/finality.
    let restored = decodeRecoveryCheckpoint(envelope, sealed, expected, genesisStoreLimits(),
        ByteLimit(high(uint64))).value
    assert restored.chainView.retainedCount == 1
    assert restored.chainView.finalizedBlock.error != GenesisError.None
    assert restored.chainView.blockAt(parent.blockHash).error != GenesisError.None
    let historyKey = chapterKey(StateChapter(3))
    assert restored.stateSnapshot.value.lookup(historyKey).value.bytes ==
        source.stateSnapshot.value.lookup(historyKey).value.bytes
    assert array[32, byte](restored.stateSnapshot.value.commitment.root) == array[32, byte](
        source.stateSnapshot.value.commitment.root)
    var branch = forkStateStore(restored.stateSnapshot.value).value
    assert branch.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
        value: @[1'u8])]).error == StateStoreError.LimitExceeded
    assert source.chainView.finalizedBlock.error ==
        GenesisError.None # Import cannot mutate the producer's independently retained certified selection.
  assert producer.chainView.finalizedBlock.error != GenesisError.None
  cycle(envelope, sealed, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(envelope, sealed, expected) # Complete map/header/byte ownership must not accumulate across exact roundtrips.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_recovery_roundtrip", 1000, before, after)
  echo "PASS application recovery roundtrip: exact bytes and state, one imported head, unset finality and explicit policy"
try:
  main() # Codec/native/fixture failure cannot masquerade as preserved trusted state.
except:
  quit(2)
