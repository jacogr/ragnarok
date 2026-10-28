# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Existing public disk/application APIs verify complete durable prefixes and explicit finality without changing storage contracts.
import std/assertions
import ../../src/app/[services, options, chain, candidate, disk_chain]
import ../../src/chain/[genesis, provider, parameters]
import ../../src/codec/[bounded, state_trie]
import ../../src/state/[store, disk_store]
import ../../src/storage/[file_repository, node_repository, node_records, record_codec, database_identity]
import ../../src/crypto/primitives
import ./[application_download_chain, application_candidate_context]

proc diskOptions*(chainPath, path: string): Options =
  ## Normal restart chooses the same explicit configured chain and mutation policy without any external import controls.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", chainPath, "--state-writes", "1000",
    "--state-write-bytes", "1000000", "--state-storage", "disk", "--state-db", path], result)

proc assertDiskPrefix*(context: DownloadChainFixture, completed: int, chainPath, path: string,
    finalizedIndex = -1) {.raises.} =
  ## Fresh local startup must restore every retained full map/root/header and only the explicitly persisted finality selection.
  var owner = default(Services)
  defer: owner.close() # No disk lock, native worker or restored graph escapes this synchronous inspection.
  assert owner.start(diskOptions(chainPath, path), "inspect confirmed download prefix")
  let view = owner.chainView
  let head = view.bestBlock.value
  assert array[32, byte](head.blockHash) == array[32, byte](context.heads[completed].blockHash)
  assert sameCompleteState(owner.stateSnapshot.value, context.heads[completed].stateSnapshot)
  assert view.retainedCount == min(completed + 1, MaxRetainedBlocks)
  let first = max(0, completed + 1 - MaxRetainedBlocks)
  for index in first..completed:
    let actual = view.blockAt(context.heads[index].blockHash)
    assert actual.error == GenesisError.None
    assert sameCompleteState(actual.value.stateSnapshot, context.heads[index].stateSnapshot)
    assert actual.value.sameParameters(context.heads[index])
    if index > first:
      assert array[32, byte](view.parentOf(actual.value.blockHash).value.blockHash) ==
        array[32, byte](context.heads[index - 1].blockHash) # Only actually retained parent/child pairs are queryable.
  if first > 0 and finalizedIndex != 0:
    assert view.blockAt(context.heads[0].blockHash).error == GenesisError.Unavailable
  if finalizedIndex >= 0:
    assert array[32, byte](view.finalizedBlock.value.blockHash) == array[32, byte](context.heads[
        finalizedIndex].blockHash)
    assert sameCompleteState(view.finalizedBlock.value.stateSnapshot, context.heads[
        finalizedIndex].stateSnapshot)
  else:
    assert view.finalizedBlock.error == GenesisError.Unavailable # No count of successful downloads infers consensus finality.

proc initializeFinalizedPrefix*(context: DownloadChainFixture, path: string) =
  ## Bootstrap the existing public disk format with a genuine first child and explicitly caller-certified original-parent finality.
  var owner = initialized(context.seed)
  let prepared = prepareCandidate(owner, context.children[0], [], preparationLimits())
  assert prepared.error == ApplicationCandidateError.None
  assert owner.applyAccumulation(prepared.value, chainCompositionLimits()).error ==
      ApplicationChainError.None
  let finalized = owner.chainView.finalizeView(context.heads[0].blockHash)
  assert finalized.error == ViewFinalizeError.None
  let selected = initApplicationChain(finalized.value).value
  var identity: seq[byte] = @[]
  for character in "RAGNAROK-CHAIN-V1\n": identity.add(byte(character))
  for octet in array[32, byte](context.heads[0].blockHash): identity.add(octet)
  for octet in array[32, byte](context.heads[0].stateRoot): identity.add(octet)
  for octet in context.heads[0].chainParameters.encodeParameters: identity.add(
      octet) # Independently encode the documented runtime chain identity.
  let digest = blake2b256(identity)
  assert digest.error == CryptoError.None
  let storePolicy = policy()
  let limits = JournalLimits(repository: RepositoryLimits(codec: RecordLimits(
    trie: storePolicy.trie,
    records: TrieExportLimits(records: TrieNodeLimit(1000000), valueBytes: ByteLimit(16777216)),
    encoded: ByteLimit(33554432)), records: ElementLimit(2000000), valueBytes: ByteLimit(67108864)),
    bytes: ByteLimit(134217728), contextBytes: ByteLimit(1048576))
  var disk = default(DiskStateStore)
  defer: discard disk.close()
  let initialized = initializeDiskChain(disk, path, StorageChainId(array[32, byte](digest.value)),
      selected, limits)
  assert initialized.error == DiskChainError.None
  assert disk.close() == FileError.None # The new command acquires its own independent lock/ownership after this helper returns.
