# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal preimage values and availability slots qualify nonempty current continuation and typed prior-request replay refusal.
import std/[assertions, syncio, envvars]
import ../../../src/app/[chain, candidate]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, bounded, composite]
import ../../../src/codec/state/[service_values as state_service_values, requests as state_requests]
import ../../../src/crypto/primitives
import ../../../src/state/store
import ../../../src/state/accumulation/current/[update as accumulation_current_update,
    completion as accumulation_current_completion, activity as accumulation_current_activity]
import ../../../src/state/preimages
import ../../support/[current_preimage_sequence_context, current_consecutive_context,
  current_services_disk_samples]

proc namespaceValues(fixture: CurrentPreimageSequenceFixture) =
  ## Empty values remain present preimages, and each request becomes available only at the actual second-child slot3.
  let blobs = @[@[73'u8], newSeq[byte](0), @[81'u8, 82, 83]]
  for index, blob in blobs:
    let service = ServiceIndex(if index == 0: 42 else: 99)
    let digest = blake2b256(blob)
    assert digest.error == CryptoError.None
    let hash = ServicePreimageHash(array[32, byte](digest.value))
    let value = servicePreimageEntry(service, hash, blob,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(32))).value
    let request = serviceRequestEntry(service, hash, RequestLength(uint32(blob.len)),
      availableHistory(RequestSlot(3)), RequestEntryConfig(keyBytes: ByteLimit(32),
          history: RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(32)))).value
    for before in 0..1:
      let snapshot = fixture.sequence.heads[before].stateSnapshot
      assert snapshot.lookup(value.key).error == StateStoreError.MissingKey
      let actual = snapshot.lookup(request.key)
      let original = fixture.sequence.heads[0].stateSnapshot.lookup(request.key)
      assert actual.error == StateStoreError.None and original.error == StateStoreError.None
      assert actual.value.bytes == original.value.bytes
    let delivered = fixture.sequence.heads[2].stateSnapshot
    let actualValue = delivered.lookup(value.key)
    let actualRequest = delivered.lookup(request.key)
    assert actualValue.error == StateStoreError.None and actualRequest.error == StateStoreError.None
    assert actualValue.value.bytes == blob
    assert actualRequest.value.bytes == request.value

proc main() {.raises.} =
  ## Candidate-wrapper preparation independently consumes the authored wires; the expected maps come from individual phase calls.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentPreimageSequenceFixture(decodeOwnedReport(bytes, 2).value)
  namespaceValues(fixture)
  var chain = initApplicationChain(genesisView(fixture.sequence.seed.parent)).value
  var ancestors = fixture.sequence.seed.older
  for index, child in fixture.sequence.children:
    let before = chain.chainView.bestBlock.value
    let prepared = prepareCurrentCandidate(chain, child, ancestors, currentConsecutiveLimits())
    assert prepared.error == CurrentCandidateError.None
    equalCurrentDiskMap(prepared.value.currentUpdateState, fixture.sequence.heads[
        index+1].stateSnapshot)
    assert chain.canInstallPrepared(prepared.value)
    chain.installPrepared(prepared.value)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # No original context is inferred from state roots or a nominal head label.
  let before = chain.stateSnapshot.value
  let repeated = prepareCurrentCandidate(chain, fixture.repeated, ancestors,
      currentConsecutiveLimits())
  assert repeated.error == CurrentCandidateError.CompletionFailure
  let completion = repeated.completionFailure
  assert completion.error == CurrentAccumulationCompletionError.ActivityFailure
  let activity = completion.activityFailure
  assert activity.error == CurrentAccumulationActivityError.PreimageFailure
  assert activity.preimageError == PreimageTransitionError.NotRequested
  assert sameStateSnapshot(before, chain.stateSnapshot.value)
  equalCurrentDiskMap(chain.stateSnapshot.value, fixture.sequence.heads[2].stateSnapshot)
try:
  main()
except:
  quit(2) # A different refusal, premature availability or changed canonical prefix cannot satisfy this witness.
echo "PVM current preimage sequence fixture passed"
