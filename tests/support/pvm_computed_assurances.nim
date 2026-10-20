# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real successor signatures use the actual computed parent hash, state root, entropy history and nine authored parent keys.

import std/assertions
import ../../src/state/[computed_assurances, computed_chain, store]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, header, block_codec, assurances, state_layout, state_consensus,
    state_safrole, state_trie]
import ../../src/crypto/[primitives, assurance_context, extrinsic_commitment]
import ../../src/bandersnatch/bandersnatch
import ./[pvm_computed_chain, pvm_computed_roster, pvm_computed_storage_program, pvm_computed_state_publication]

proc computedAssuranceConfig*(): ComputedAssuranceConfig =
  ## Preserve actual three-core/nine-validator domains and independent finite report comparison policies.
  let config = rosterTransitionConfig()
  ComputedAssuranceConfig(admission: config.admission, disputes: config.disputes,
    safrole: config.safrole,
    availability: config.availability, reports: ElementLimit(3), reportBytes: ByteLimit(100000),
        totalReportBytes: ByteLimit(400000))
proc assurancePrior*(): AdvancedComputedChain =
  ## Execute and publish the real first block before authoring any later assurance or header.
  let source = chainFixture(storage = ComputedStorageMode.Commit)
  let parent = source.chainFixtureParent(source.chainFixtureParameters)
  var state = forkStateStore(source.statePublicationParent).value
  var view = genesisView(parent)
  advanceComputedChain(state, view, source).value
proc context(domain: string, seed: array[32, byte]): seq[byte] =
  ## Independently encode literal signing domain followed by exactly one raw fixed entropy/output word.
  result = newSeq[byte](domain.len+32)
  for index, octet in domain: result[index] = byte(octet) # No terminator, token dollar sign or length prefix.
  for index in 0..<32: result[domain.len+index] = seed[index]
proc assuranceCandidate*(source: AdvancedComputedChain, votes = 7, badSignature = false,
    badAnchor = false, badSeal = false): OwnedBlock =
  ## Sign each actual parent validator's three-core bit vector, commit the entire body, then sign the real successor header.
  assert votes >= 0 and votes <= 9
  let parent = source.computedChainBlock.value
  assert parent.slot < high(uint32), "authored successor slot must not wrap"
  let config = computedAssuranceConfig()
  let hash = array[32, byte](parent.blockHash)
  var anchor = hash
  if badAnchor: anchor[0] = anchor[0] xor 1 # Sign the wrong named parent honestly so the maintained context check must reject it.
  var records = newSeq[Assurance](votes)
  for index in 0..<votes:
    var seed = default(array[32, byte])
    seed[0] = byte(index+11)
    let key = importSeed(seed).value
    var bits = default(AssuranceBits)
    bits.bytes[0] = 3 # Both genuinely pending computed cores0/1 receive every actual vote.
    let message = array[45, byte](assuranceMessage(AssuranceParent(anchor), bits, CoreCount(3)).value)
    records[index] = Assurance(anchor: AssuranceAnchor(bytes: anchor), bits: bits,
        validator: ValidatorIndex(uint16(index)),
      signature: AssuranceSignature(bytes: array[64, byte](sign(key, message).value)))
  if badSignature and votes != 0: records[^1].signature.bytes[0] = records[^1].signature.bytes[
      0] xor 1 # Body commitment and seal are still recomputed over this hostile signature.
  var assuranceWire = newSeq[byte](10000)
  let written = encodeAssurances(records, AssuranceConfig(cores: CoreCount(3),
      validators: ValidatorCount(9)), assuranceWire)
  assert written.error == AssuranceError.None
  var body = @[0'u8, 0, 0] # Canonical empty tickets, preimages and new guarantees.
  for index in 0..<written.written: body.add(assuranceWire[index])
  for index in 0..<3: body.add(0'u8) # Three independently empty dispute families.
  let extrinsic = decodeExtrinsic(body, config.admission.frame).value.owner
  var header = default(header.Header)
  header.unsigned.epoch = absentEpoch()
  header.unsigned.winners = absentWinners()
  header.unsigned.parent = HeaderParent(hash)
  header.unsigned.priorState = PriorStateRoot(array[32, byte](parent.stateRoot))
  header.unsigned.slot = HeaderSlot(parent.slot+1)
  header.unsigned.extrinsics = ExtrinsicRoot(array[32, byte](extrinsicCommitment(extrinsic,
      ByteLimit(100000)).value))
  let entropy = decodeStateEntropy(parent.stateSnapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  let public = publicKey(key).value
  let input = context("jam_fallback_seal", array[32, byte](entropy[
      3])) # This real non-epoch child uses the inherited history[3], never a hardcoded zero.
  let provisional = sign(key, input, []).value
  let output = array[32, byte](verify(public, provisional, input, []).value)
  header.unsigned.entropyProof = HeaderEntropyProof(array[96, byte](sign(key, context("jam_entropy",
      output), []).value))
  let headerConfig = HeaderConfig(cores: CoreCount(3), authorValidators: ValidatorCount(9),
      epochSlots: EpochSlots(12), maxBytes: ByteLimit(10000))
  var unsigned = newSeq[byte](10000)
  let unsignedSize = encodeUnsignedHeader(header.unsigned, headerConfig, unsigned).value
  header.seal = HeaderSeal(array[96, byte](sign(key, input, unsigned.toOpenArray(0,
      unsignedSize-1)).value))
  close(key)
  if badSeal:
    var broken = array[96, byte](header.seal)
    broken[0] = broken[0] xor 1
    header.seal = HeaderSeal(broken) # The actual header remains canonical while authentication must fail.
  var headerWire = newSeq[byte](10000)
  let headerSize = encodeHeader(header, headerConfig, headerWire).value
  let owned = decodeComponent[ComponentKind.Header](headerWire.toOpenArray(0, headerSize-1),
      config.admission.frame).value.owner
  var wire = newSeq[byte](100000)
  let size = encodeBlock(Block(header: owned, extrinsic: extrinsic), config.admission.frame, wire).value
  decodeBlock(wire.toOpenArray(0, size-1), config.admission.frame).value.owner
