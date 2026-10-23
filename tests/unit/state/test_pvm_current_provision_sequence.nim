# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real guest values remain supplied at slot2 across duplicate calls; mixed body refusal and a short local union budget preserve exact prefixes.
import std/[assertions, syncio, envvars, monotimes]
import std/posix/posix
import ../../../src/app/[chain, candidate, services, current_download_command]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, bounded, composite, state_service_values, state_requests]
import ../../../src/crypto/primitives
import ../../../src/state/[store, accumulation_current_update, accumulation_current_completion,
  accumulation_current_activity, preimages]
import ../../../src/storage/managed_manifest
import ../../support/[current_provision_sequence_context, current_consecutive_download_context,
  current_sequence_command_context, current_services_disk_samples, managed_storage_samples,
  block_download_transport]

proc namespaceValues(fixture: CurrentProvisionSequenceFixture) =
  ## The first program provides its literal RO73 and RW81; remaining lookup requests must stay outstanding after rejected delivery.
  for index, raw in [73'u8, 81]:
    let service = ServiceIndex(if index == 0: 42 else: 99)
    let blob = @[raw]
    let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
    let value = servicePreimageEntry(service, hash, blob, ServiceEntryLimits(keyBytes: ByteLimit(
        32), valueBytes: ByteLimit(32))).value
    let expected = serviceRequestEntry(service, hash, RequestLength(1), availableHistory(
        RequestSlot(2)),
      RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
          3), maxBytes: ByteLimit(32)))).value
    assert fixture.sequence.heads[0].stateSnapshot.lookup(value.key).error ==
        StateStoreError.MissingKey
    for child in 1..2:
      let actualValue = fixture.sequence.heads[child].stateSnapshot.lookup(value.key)
      let actualRequest = fixture.sequence.heads[child].stateSnapshot.lookup(expected.key)
      assert actualValue.error == StateStoreError.None and actualRequest.error ==
          StateStoreError.None
      assert actualValue.value.bytes == blob and actualRequest.value.bytes == expected.value
  for blob in [newSeq[byte](0), @[81'u8, 82, 83]]:
    let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
    let value = servicePreimageEntry(ServiceIndex(99), hash, blob, ServiceEntryLimits(
        keyBytes: ByteLimit(32), valueBytes: ByteLimit(32))).value
    let request = serviceRequestKey(ServiceIndex(99), hash, RequestLength(uint32(blob.len)),
        ByteLimit(32)).value
    for child in 0..2:
      let snapshot = fixture.sequence.heads[child].stateSnapshot
      assert snapshot.lookup(value.key).error == StateStoreError.MissingKey
      let actual = snapshot.lookup(request)
      assert actual.error == StateStoreError.None and actual.value.bytes == @[0'u8]

proc shortLimits(): CurrentCandidateLimits =
  ## Keep actual guest capture capacity while refusing the two-value union under an explicit one-item local ceiling.
  result = currentProvisionSequenceLimits()
  result.completion.execution.initial.provisions.values.items = ElementLimit(1)
  result.completion.execution.execution.round = result.completion.execution.initial

proc candidateChecks(fixture: CurrentProvisionSequenceFixture) =
  ## Typed direct preparation distinguishes prior-request refusal from a local execution budget, without installing either failed update.
  var chain = initApplicationChain(genesisView(fixture.sequence.seed.parent)).value
  var ancestors = fixture.sequence.seed.older
  let original = chain.stateSnapshot.value
  let limited = prepareCurrentCandidate(chain, fixture.sequence.children[0], ancestors, shortLimits())
  assert limited.error == CurrentCandidateError.CompletionFailure
  assert limited.completionFailure.error == CurrentAccumulationCompletionError.SequenceFailure
  assert sameStateSnapshot(original, chain.stateSnapshot.value)
  for index, child in fixture.sequence.children:
    let before = chain.chainView.bestBlock.value
    let prepared = prepareCurrentCandidate(chain, child, ancestors, currentProvisionSequenceLimits())
    assert prepared.error == CurrentCandidateError.None
    equalCurrentDiskMap(prepared.value.currentUpdateState, fixture.sequence.heads[
        index+1].stateSnapshot)
    chain.installPrepared(prepared.value)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next # Full original lookup handles remain explicit at each successful candidate turn.
  let before = chain.stateSnapshot.value
  let mixed = prepareCurrentCandidate(chain, fixture.mixed, ancestors,
      currentProvisionSequenceLimits())
  assert mixed.error == CurrentCandidateError.CompletionFailure
  let completion = mixed.completionFailure
  assert completion.error == CurrentAccumulationCompletionError.ActivityFailure
  let activity = completion.activityFailure
  assert activity.error == CurrentAccumulationActivityError.PreimageFailure
  assert activity.preimageError == PreimageTransitionError.NotRequested
  assert sameStateSnapshot(before, chain.stateSnapshot.value)

proc commandChecks(fixture: CurrentProvisionSequenceFixture, layout, variant: int) {.raises.} =
  ## Full progress, mixed-body refusal and a local first-round refusal retain only their actual confirmed durable prefixes.
  var database = "pvm-current-provision-sequence-state-" & $getMonoTime().ticks
  defer:
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString())
  var extra: seq[string] = @[]
  if layout != 0:
    extra = @["--state-storage", "disk", "--state-db", database]
    if layout == 2:
      for argument in ["--state-layout", "managed", "--state-compact-bytes", "0"]:
        extra.add(argument) # Preserve the existing explicit no-maintenance physical publication scope.
  var responses = @[currentConsecutiveResponse(fixture.sequence.children[0])]
  if variant != 2: responses.add(currentConsecutiveResponse(fixture.sequence.children[1]))
  if variant == 1: responses.add(currentConsecutiveResponse(fixture.mixed))
  var modes: seq[DownloadTransferMode] = @[]
  for index in 0..<responses.len: modes.add(Healthy)
  var policy = currentConsecutivePolicy()
  policy.candidate = if variant == 2: shortLimits() else: currentProvisionSequenceLimits()
  let requested = if variant == 1: 3 else: 2
  let observed = exchangeCurrentSequence(fixture.sequence, 0, requested, responses, modes, policy,
    "pvm-current-provision-sequence-chain", "pvm-current-provision-sequence-policy",
    "pvm-current-provision-sequence", extra)
  assert observed.outcome.error == (if variant == 0: CurrentDownloadCommandResult.Adopted else: CurrentDownloadCommandResult.Exhausted)
  let adopted = if variant == 2: 0 else: 2
  assert observed.outcome.adoptedBlocks == adopted and observed.outcome.requestedBlocks == requested
  assert observed.firstRequests == 0 and observed.secondRequests == responses.len
  if layout == 0: return # Public memory command outcomes intentionally contain only confirmed scalar progress.
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(currentDiskOptions("pvm-current-provision-sequence-chain", database, layout ==
      2, 0), "strict provision prefix restart")
  let view = owner.chainView
  assert view.retainedCount == adopted+1 and view.finalizedBlock.error == GenesisError.Unavailable
  for index in 0..adopted:
    let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
    assert array[32, byte](actual.blockHash) == array[32, byte](fixture.sequence.heads[
        index].blockHash)
    equalCurrentDiskMap(actual.stateSnapshot, fixture.sequence.heads[index].stateSnapshot)
  owner.close()

proc main() {.raises.} =
  ## Every native command lifetime is serial; exact generated controls and storage retire only after collection/join.
  defer:
    for name in ["pvm-current-provision-sequence-chain", "pvm-current-provision-sequence-policy"]:
      var path = name
      discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentProvisionSequenceFixture(decodeOwnedReport(bytes, 2).value)
  namespaceValues(fixture)
  candidateChecks(fixture)
  for layout in 0..2:
    for variant in 0..2: commandChecks(fixture, layout, variant)
try:
  main()
except:
  quit(2) # Rewritten availability slots, partial mixed delivery or lost local-resource refusal remain strict failures.
echo "PVM current provision sequence passed"
