# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted light application heads retain partial facts and bounded linked headers without complete-map execution authority.
# @@Verification={"arc":"light_application_head_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_disk_history_context
import ../../support/app_checkpoint_context
import ../../../src/app/light_head as app_light_head
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_trust as app_checkpoint_trust
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/state/store as state_store
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/proof_view as state_proof_view
proc headerWire(sourceBlock: BlockSnapshotResult): seq[byte] =
  ## Test-only complete snapshots supply independently chosen canonical header bytes, never partial-root inference.
  let selected = sourceBlock.value.header
  result = newSeq[byte](selected.headerInfo.value.consumed)
  assert encodeOwnedHeader(selected, result).error == HeaderError.None
proc trust(sourceBlock: BlockSnapshotResult): TrustedApplicationCheckpoint =
  ## Caller-selected identity/header inputs are captured before the light owner sees proof evidence.
  let owner = initApplicationChain(genesisView(sourceBlock)).value
  let identity = captureApplicationCheckpointIdentity(owner).value
  let encoded = encodeApplicationCheckpointIdentity(identity, ByteLimit(4096)).value
  let captured = captureCheckpointTrust(encoded, sourceBlock.headerWire, ByteLimit(1048576))
  assert captured.error == CheckpointTrustError.None
  captured.value
proc policy(sourceBlock: BlockSnapshotResult): LightHeadLimits =
  ## Active validator geometry is selected independently from complete genesis context, never inferred from fetch parameters or partial facts.
  LightHeadLimits(header: HeaderConfig(cores: sourceBlock.value.cores,
    authorValidators: sourceBlock.value.activeValidators, epochSlots: sourceBlock.value.epochSlots,
    maxBytes: ByteLimit(262144)), headers: ElementLimit(3), headerBytes: ByteLimit(1048576),
    view: ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(4194304)))
proc entries(snapshot: StateStoreSnapshot): seq[StateEntry] =
  ## An independent complete fixture map is used only to author genuine membership/absence proofs.
  result = @[]
  for index in 0..<snapshot.commitment.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    result.add(StateEntry(key: key, value: snapshot.lookup(key).value.bytes))
proc batch(snapshot: StateStoreSnapshot, keys: openArray[StateKey],
    limits: StateStoreLimits): VerifiedStateProofBatch =
  ## Full fixture generation and exact-root verification precede every partial view used by the application API.
  let perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4194304))
  let aggregate = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
      valueBytes: ByteLimit(4194304))
  let generated = generateStateProofs(snapshot.entries, keys, limits.trie, perProof, aggregate)
  assert generated.error == StateProofError.None
  var queries = newSeq[StateProofQuery](generated.value.len)
  for index in 0..<queries.len: queries[index] = generated.value.queryAt(
      index).value # Immutable raw witnesses carry no trust until verified.
  let checked = verifyStateProofs(queries, snapshot.commitment.root, perProof, aggregate)
  assert checked.error == StateProofError.None
  checked.value
func key(value: byte): StateKey =
  ## High-byte fixture keys distinguish genuine absent witnesses from unrequested unknown facts.
  var bytes = default(array[31, byte])
  for index in 0..<bytes.len: bytes[index] = value
  StateKey(bytes)
proc checksum(bytes: var seq[byte]) =
  ## Independent identity-frame oracle rehashes the documented fixed 206-byte payload after one deliberate scalar change.
  assert bytes.len == 238
  let hashed = blake2b256(bytes.toOpenArray(0, 205))
  assert hashed.error == CryptoError.None
  let digest = array[32, byte](hashed.value)
  for index in 0..<32: bytes[206+index] = digest[index]
proc rootTrust(original: TrustedApplicationCheckpoint,
    root: StateRoot): TrustedApplicationCheckpoint =
  ## Test-only operator posterior-root choice remains independent of the sealed header's prior root; no consensus certificate is claimed.
  var identity = encodeApplicationCheckpointIdentity(original.identity, ByteLimit(4096)).value
  let digest = array[32, byte](root)
  for index in 0..<32: identity[48+index] = digest[index]
  checksum(identity)
  var header = newSeq[byte](original.sealedHeaderLength)
  assert original.copySealedHeader(header)
  let captured = captureCheckpointTrust(identity, header, ByteLimit(1048576))
  assert captured.error == CheckpointTrustError.None
  captured.value
proc transport(sourceBlock: BlockSnapshotResult) =
  ## Captured trust and exported light header copies cannot alias the caller's mutable buffers.
  var source = sourceBlock.headerWire
  let identity = captureApplicationCheckpointIdentity(initApplicationChain(genesisView(
      sourceBlock)).value).value
  let encoded = encodeApplicationCheckpointIdentity(identity, ByteLimit(4096)).value
  let owner = captureCheckpointTrust(encoded, source, ByteLimit(1048576)).value
  let original = source[0]
  source[0] = source[0] xor 1
  var copied = newSeq[byte](owner.sealedHeaderLength)
  assert owner.copySealedHeader(copied) and copied[0] == original
  var short = newSeq[byte](copied.len-1)
  for index in 0..<short.len: short[index] = 0xA5 # All insufficient-capacity paths must preserve every caller byte.
  assert not owner.copySealedHeader(short)
  for octet in short: assert octet == 0xA5
  assert default(TrustedApplicationCheckpoint).sealedHeaderLength == 0
  assert not default(TrustedApplicationCheckpoint).copySealedHeader(short)
  let head = captureLightHead(owner, sourceBlock.policy).value
  let selected = head.current.value
  assert selected.valid and selected.byteLength == copied.len
  assert not selected.copyHeader(short)
  for octet in short: assert octet == 0xA5
  assert selected.copyHeader(copied)
  copied[0] = copied[0] xor 1
  assert selected.copyHeader(copied) and copied[0] == original
  assert sameApplicationCheckpoint(selected.identity, identity)
proc semanticFacts(fixture: DiskHistoryFixture) =
  ## Present, present-empty, proven absent and unknown remain different facts under an independently selected posterior root.
  let source = fixture.blocks[0].value.stateSnapshot
  let selected = fixture.blocks[0].trust
  let limits = fixture.blocks[0].policy
  let clock = chapterKey(StateChapter(11))
  let absent = key(255)
  let unknown = key(254)
  let checked = batch(source, [clock, absent], fixture.policy)
  let view = captureProofView(checked, selected.identity.stateRoot, limits.view).value
  let head = captureLightHead(selected, view, limits).value
  assert head.valid and head.len == 1 and head.proofView.len == 2
  assert head.proofView.lookup(clock).value.present
  assert not head.proofView.lookup(absent).value.present
  assert head.proofView.lookup(unknown).error == ProofViewError.MissingWitness
  let empty = captureLightHead(selected, limits).value
  assert empty.proofView.valid and empty.proofView.len == 0
  assert empty.proofView.lookup(absent).error == ProofViewError.MissingWitness
  assert array[32, byte](empty.stateRoot) == array[32, byte](selected.identity.stateRoot)
  let enriched = mergeLightProofs(empty, checked, limits).value
  assert enriched.proofView.len == 2 and empty.proofView.len == 0
  assert mergeLightProofs(enriched, checked, limits).value.proofView.len == 2
  assert mergeLightProofs(empty, default(VerifiedStateProofBatch), limits).viewError ==
      ProofViewError.Uninitialized
  var short = limits
  short.view.items = ElementLimit(1)
  assert captureLightHead(selected, view, short).viewError == ProofViewError.LimitExceeded
  assert mergeLightProofs(empty, checked, short).viewError == ProofViewError.LimitExceeded
  let foreign = captureLightHead(fixture.blocks[1].trust, limits).value
  assert captureLightHead(selected, foreign.proofView, limits).viewError == ProofViewError.WrongRoot
  assert mergeLightProofs(foreign, checked, limits).viewError == ProofViewError.WrongRoot
  var changed = source.entries
  let emptyKey = key(253)
  for entry in changed: assert array[31, byte](entry.key) != array[31, byte](
      emptyKey) # The empty value is an actual new present leaf.
  changed.add(StateEntry(key: emptyKey, value: @[]))
  let complete = newStateStore(changed, fixture.policy).value.snapshot.value
  let independent = rootTrust(selected, complete.commitment.root)
  let emptyFact = batch(complete, [emptyKey], fixture.policy)
  let partial = captureProofView(emptyFact, independent.identity.stateRoot, limits.view).value
  let emptyHead = captureLightHead(independent, partial, limits).value
  assert emptyHead.proofView.lookup(emptyKey).value.present
  assert emptyHead.proofView.lookup(emptyKey).value.byteLength == 0
  assert emptyHead.proofView.lookup(unknown).error == ProofViewError.MissingWitness
  assert array[32, byte](emptyHead.stateRoot) != array[32, byte](
      emptyHead.current.value.headerInfo.unsigned.priorState)
proc window(fixture: DiskHistoryFixture): LightApplicationHead =
  ## Fresh successor roots clear old evidence and retain only the configured newest directly linked headers.
  let limits = fixture.blocks[0].policy
  let checked = batch(fixture.blocks[0].value.stateSnapshot, [chapterKey(StateChapter(11))],
      fixture.policy)
  let view = captureProofView(checked, fixture.blocks[0].value.stateRoot, limits.view).value
  let retained = captureLightHead(fixture.blocks[0].trust, view, limits).value
  var head = retained
  for index in 1..<fixture.blocks.len:
    head = advanceLightHead(head, fixture.blocks[index].trust, limits).value
    assert head.proofView.len == 0 and head.proofView.lookup(chapterKey(StateChapter(11))).error ==
        ProofViewError.MissingWitness
  assert head.len == 3
  assert uint64(head.headerAt(LightHeaderIndex(0)).value.identity.slot) == uint64(fixture.blocks[
      fixture.blocks.len-3].value.slot)
  assert sameApplicationCheckpoint(head.current.value.identity, fixture.blocks[
      fixture.blocks.len-1].trust.identity)
  assert retained.len == 1 and retained.proofView.len == 1
  assert retained.proofView.lookup(chapterKey(StateChapter(11))).value.present
  head
proc refusals(fixture: DiskHistoryFixture) {.raises.} =
  ## Defaults, profile geometry, slot, direct parent and prior-root failures never publish a partially usable head.
  let limits = fixture.blocks[0].policy
  let selected = fixture.blocks[0].trust
  let head = captureLightHead(selected, limits).value
  assert not default(LightApplicationHead).valid and default(LightApplicationHead).len == 0
  assert default(LightApplicationHead).current.error == LightHeadError.Uninitialized
  assert head.headerAt(LightHeaderIndex(high(uint32))).error == LightHeadError.InvalidIndex
  assert captureLightHead(default(TrustedApplicationCheckpoint), limits).error ==
      LightHeadError.MissingTrust
  assert captureLightHead(selected, default(ProofView), limits).viewError ==
      ProofViewError.Uninitialized
  assert advanceLightHead(head, selected, limits).error == LightHeadError.SlotRegression
  assert advanceLightHead(head, fixture.blocks[2].trust, limits).error == LightHeadError.WrongParent
  var wire = fixture.blocks[1].headerWire
  wire[32] = wire[32] xor 1
  let wrongPrior = captureBlockSnapshot(wire, fixture.blocks[1].value.stateSnapshot, fixture.blocks[
      1].value.chainParameters)
  assert wrongPrior.error == GenesisError.None
  assert advanceLightHead(head, wrongPrior.trust, limits).error == LightHeadError.WrongPriorRoot
  var profile = limits
  profile.header.cores = CoreCount(uint64(limits.header.cores)+1)
  assert captureLightHead(selected, profile).error == LightHeadError.ProfileMismatch
  profile = limits
  profile.header.authorValidators = ValidatorCount(3)
  let invalid = captureLightHead(selected, profile)
  assert invalid.error == LightHeadError.HeaderFailure and invalid.headerError ==
      HeaderError.InvalidConfig
  profile = limits
  profile.headers = ElementLimit(0)
  assert captureLightHead(selected, profile).error == LightHeadError.LimitExceeded
  profile = limits
  profile.headerBytes = ByteLimit(uint64(selected.sealedHeaderLength-1))
  assert captureLightHead(selected, profile).error == LightHeadError.LimitExceeded
  profile = limits
  profile.headers = ElementLimit(uint64(MaxLightHeaders)+1)
  assert captureLightHead(selected, profile).error ==
      LightHeadError.LimitExceeded # A caller cannot widen the fixed application window.
  let different = checkpointFixture(CheckpointFixtureVariant.Profile).chainView.bestBlock
  assert advanceLightHead(head, different.trust, limits).error ==
      LightHeadError.ProfileMismatch # Equal geometry does not permit another parameter profile.
  var trailing = fixture.blocks[0].headerWire
  trailing.add(0)
  var altered = encodeApplicationCheckpointIdentity(selected.identity, ByteLimit(4096)).value
  let hash = array[32, byte](blake2b256(trailing).value)
  for index in 0..<32: altered[16+index] = hash[index] # Independent identity oracle binds the entire deliberately extended transport.
  checksum(altered)
  let extended = captureCheckpointTrust(altered, trailing, ByteLimit(1048576)).value
  assert captureLightHead(extended, limits).error ==
      LightHeadError.InvalidFormat # Exact sealed-header consumption remains mandatory after trust capture.
  var identity = encodeApplicationCheckpointIdentity(selected.identity, ByteLimit(4096)).value
  identity[80] = identity[80] xor 1
  checksum(identity)
  let wrongSlot = captureCheckpointTrust(identity, fixture.blocks[0].headerWire, ByteLimit(1048576)).value
  assert captureLightHead(wrongSlot, limits).error == LightHeadError.TrustMismatch
proc codec(head: LightApplicationHead, fixture: DiskHistoryFixture) =
  ## Every retained header is hash/slot/profile/parent/prior-root checked, with independent current trust and exact framing.
  let limits = fixture.blocks[0].policy
  let expected = fixture.blocks[fixture.blocks.len-1].trust
  let encoded = encodeLightHead(head, ByteLimit(4194304)).value
  let restored = restoreLightHead(encoded, expected, head.proofView, limits, ByteLimit(4194304))
  assert restored.error == LightHeadError.None
  assert restored.value.len == head.len and sameApplicationCheckpoint(
      restored.value.current.value.identity, expected.identity)
  assert encodeLightHead(restored.value, ByteLimit(4194304)).value == encoded
  assert encodeLightHead(head, ByteLimit(uint64(encoded.len-1))).error ==
      LightHeadError.LimitExceeded
  assert restoreLightHead(encoded, expected, head.proofView, limits, ByteLimit(uint64(
      encoded.len-1))).error == LightHeadError.LimitExceeded
  assert restoreLightHead(encoded, fixture.blocks[0].trust, head.proofView, limits, ByteLimit(
      4194304)).error == LightHeadError.TrustMismatch
  assert restoreLightHead(encoded, expected, default(ProofView), limits, ByteLimit(
      4194304)).viewError == ProofViewError.Uninitialized
  let foreign = captureLightHead(fixture.blocks[0].trust, limits).value
  assert restoreLightHead(encoded, expected, foreign.proofView, limits, ByteLimit(
      4194304)).viewError == ProofViewError.WrongRoot
  for mode in 0..5:
    var changed = encoded
    case mode
    of 0: changed[0] = changed[0] xor 1 # No other local/storage-only context schema is accepted.
    of 1: changed.add(0) # Trailing data cannot hide a second context or proof payload.
    of 2: changed[25] = 0 # Explicit literal format oracle: 23-byte magic, E2 population, E1 count.
    of 3: changed[25] = 9 # The fixed eight-header application ceiling precedes allocation.
    of 4: changed[23] = changed[23] xor 1 # Stored author geometry must equal independent caller configuration.
    else:
      for index in 0..<4: changed[26+238+index] = 255 # Huge first-header length refuses before narrowing or copying.
    assert restoreLightHead(changed, expected, head.proofView, limits, ByteLimit(4194304)).error !=
        LightHeadError.None
proc cycle(fixture: DiskHistoryFixture) =
  ## All newly created immutable header/view/context owners must release after this isolated operation activation.
  let head = window(fixture)
  let limits = fixture.blocks[0].policy
  let selected = fixture.blocks[fixture.blocks.len-1]
  let enriched = mergeLightProofs(head, batch(selected.value.stateSnapshot, [chapterKey(
      StateChapter(11))], fixture.policy), limits).value
  let bytes = encodeLightHead(enriched, ByteLimit(4194304)).value
  let restored = restoreLightHead(bytes, selected.trust, enriched.proofView, limits, ByteLimit(4194304)).value
  assert restored.proofView.lookup(chapterKey(StateChapter(11))).value.present
proc main() {.raises.} =
  ## The native suite uses genuine independently authored complete fixtures only as external proof/header oracles.
  let fixture = diskHistoryFixture(withFinality = false)
  transport(fixture.blocks[0])
  semanticFacts(fixture)
  refusals(fixture)
  let head = window(fixture)
  codec(head, fixture)
  cycle(fixture)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(fixture) # Repeated capture/enrichment/advancement/context round trips retain no ownership prefix.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_light_application_head", 1000, before, after)
  echo "light application head PASS"
try:
  main()
except:
  quit(2) # Fixture IO and native setup failures cannot count as successful light authority validation.
