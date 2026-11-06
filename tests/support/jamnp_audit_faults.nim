# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentionally dishonest raw reports pass genuine signatures, current admission, assurances and whole-state publication before authenticated original bundle data demonstrates their invalidity. No computed-success or pending-assignment certificate is fabricated.
import std/[assertions, syncio, monotimes, times, posix/posix]
import ../../src/app/[chain, services, options, audit_state]
import ../../src/app/proof/worker
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, report_owned, assurances, composite, owned]
import ../../src/codec/work/report
from ../../src/codec/state/trie import TrieNodeLimit
import ../../src/codec/state/safrole
import ../../src/crypto/primitives
import ../../src/crypto/assurance_context
import ../../src/state/computed/report
import ../../src/state/availability/specifier
import ../../src/state/erasure/[words, layout]
import ../../src/jamnp-s/[audit_context, audit_origin, audit_evaluation, audit_recovery,
  availability_proof, availability_merkle, audit_registry, work_signer]
import ./[current_guarantee_sequence_context, current_consecutive_context,
  current_stf_reporting_context, pvm_computed_report, jamnp_audit_evaluation,
  jamnp_audit_signing, assurance_signer_context, current_application_context]

type FaultPacket = object ## Deliberately authored public wire remains untrusted until the ordinary independent CE138 verifier accepts it.
  request: AvailabilityRequest
  chunk, proof: seq[byte]
type PaddingFault = object ## Test-owned raw malicious encoding, never a fabricated production availability/computation capability.
  root: ErasureRoot
  length: BundleLength
  packets: seq[FaultPacket]
type FaultAuditFixture = object ## The immutable view contains genuinely published raw guarantees and actual assurance votes; raw packet proofs authenticate the genuinely signed root before recovery.
  view: ChainView
  blockHash: genesis.BlockHash
  context: AuditContextLimits
  packets: seq[FaultPacket]
proc malformedPadding(source: seq[FaultPacket], length: BundleLength): PaddingFault =
  ## Encode a genuinely consistent full codeword whose final declared padding byte is nonzero, then commit/prove every raw validator leaf before real guarantee signatures.
  result = default(PaddingFault)
  let geometry = erasureGeometry(length, ErasureShards(6)).value
  assert source.len == 6 and geometry.originalShards == 3 and geometry.paddedBytes > 1
  let width = int(geometry.bundleChunkBytes)
  var originals = newSeq[seq[byte]](3)
  for row in 0..<3:
    originals[row] = newSeq[byte](width)
    for position in 0..<width: originals[row][position] = source[row].chunk[position]
  originals[2][width-1] = 1
  var chunks = newSeq[seq[byte]](6)
  for ordinal in 0..<6: chunks[ordinal] = newSeq[byte](width)
  for column in 0..<width div 2:
    var input = default(array[3, ErasureWord])
    for row in 0..<3:
      input[row] = ErasureWord(uint16(originals[row][column*2]) or (uint16(originals[row][
          column*2+1]) shl 8))
    let encoded = encodeErasureWords(input, ErasureShards(6),
      ErasureWordLimits(bytes: ByteLimit(10000), products: FieldProductLimit(1000000))).value
    for ordinal in 0..<6:
      let word = uint16(encoded.codeWord(ErasureShardIndex(uint64(ordinal))).value)
      chunks[ordinal][column*2] = byte(word and 255)
      chunks[ordinal][column*2+1] = byte(word shr 8)
  var leaves = newSeq[byte](6*64)
  for ordinal in 0..<6:
    let hash = blake2b256(chunks[ordinal]).value
    for position in 0..<32: leaves[ordinal*64+position] = array[32, byte](hash)[position]
    for position in 32..<64: leaves[ordinal*64+position] = 0 # The original genuine source has zero exports.
  let limits = AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(10000),
      hashBytes: ByteLimit(1000000))
  result.root = ErasureRoot(bytes: array[32, byte](availabilityMerkleRoot(leaves, 64, 6,
      limits).value))
  result.length = BundleLength(uint32(geometry.paddedBytes-1)) # Exactly one nonzero byte lies outside the signed declared length.
  for ordinal in 0..<6:
    let trace = prepareAvailabilityTrace(leaves, 64, 6, ordinal, 1, limits).value
    assert array[32, byte](trace.root) == result.root.bytes
    var proof = trace.bytes
    proof.add(0'u8)
    for position in 0..<32: proof.add(0'u8)
    result.packets.add(FaultPacket(request: AvailabilityRequest(
      kind: AvailabilityTransferKind.Audit,
      root: result.root, shard: ErasureShardIndex(uint64(ordinal))), chunk: chunks[ordinal], proof: proof))
proc dishonestAvailability(base: OwnedReport, root: ErasureRoot,
    length: BundleLength): OwnedReport =
  ## Alter raw unsigned report metadata before genuine credential signing/admission; no computed certificate is retagged.
  var bytes = newSeq[byte](base.ownedReportInfo.value.consumed)
  assert base.encodeOwnedReport(bytes).error == OwnershipError.None
  var report = decodeReportBorrowed(bytes, 2).value
  report.header.erasureRoot = root
  report.header.bundleLength = length
  var output = newSeq[byte](bytes.len)
  let written = encodeReportBorrowed(report, bytes, 2, output)
  assert written.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, written.written-1), 2).value
proc faultFixture(padding: bool): FaultAuditFixture =
  ## A raw report may lie about its package hash while retaining valid erasure commitments; full node admission cannot replace private auditing.
  result = default(FaultAuditFixture)
  let available = computedAvailabilityAtCore(0, 0, 6)
  let computed = prepareComputedReport(available, ByteLimit(100000)).value
  let original = decodeOwnedReport(computed.computedReportBytes.value, 2).value
  let descriptor = available.availabilityInfo.value.specifier
  assert uint16(descriptor.segmentCount) == 0, "the original actual guest exported no rows"
  let proof = AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(10000),
      hashBytes: ByteLimit(1000000))
  var packets: seq[FaultPacket] = @[]
  for ordinal in 0..<6:
    let request = AvailabilityRequest(kind: AvailabilityTransferKind.Audit,
      root: descriptor.erasureRoot, shard: ErasureShardIndex(uint64(ordinal)))
    let prepared = prepareAvailabilityTransfer(available, request, proof).value
    packets.add(FaultPacket(request: request, chunk: prepared.bundleShard,
        proof: prepared.justification))
  var base = original
  if padding:
    let malformed = malformedPadding(packets, descriptor.bundleLength)
    base = dishonestAvailability(original, malformed.root, malformed.length)
    packets = malformed.packets
  let sequence = currentGuaranteeSequenceFixture(base)
  var chain = initApplicationChain(genesisView(sequence.sequence.seed.parent)).value
  var ancestors = sequence.sequence.seed.older
  let limits = reportingLimits()
  for child in sequence.sequence.children:
    let before = chain.chainView.bestBlock.value
    let update = phaseCurrentUpdate(chain, child, ancestors, limits)
    assert chain.canInstallPrepared(update)
    chain.installPrepared(update)
    var next = @[before.header]
    for header in ancestors: next.add(header)
    ancestors = next
  let parent = chain.chainView.bestBlock.value
  var votes = newSeq[Assurance](5)
  for ordinal in 0..<votes.len:
    var seed = default(array[32, byte])
    seed[0] = byte(ordinal+11)
    var bits = default(AssuranceBits)
    bits.bytes[0] = 3 # Both actual pending signed guarantees become available through a real five-of-six quorum.
    let message = assuranceMessage(AssuranceParent(array[32, byte](parent.blockHash)), bits,
        CoreCount(2)).value
    let signed = importSeed(seed).value.sign(array[45, byte](message)).value
    votes[ordinal] = Assurance(bits: bits, validator: ValidatorIndex(ordinal),
      signature: AssuranceSignature(bytes: array[64, byte](signed)))
  var encoded = newSeq[byte](1000)
  let written = encodeAssurances(votes, AssuranceConfig(cores: CoreCount(2),
      validators: ValidatorCount(6)), encoded)
  assert written.error == AssuranceError.None
  var body = @[0'u8, 0, 0] # Canonical empty tickets, preimages and guarantees precede actual assurance bytes.
  for ordinal in 0..<written.written: body.add(encoded[ordinal])
  for ordinal in 0..<3: body.add(0'u8) # Three canonical empty dispute vectors complete the body.
  let child = currentBodyChild(parent, body)
  let update = phaseCurrentUpdate(chain, child, ancestors, limits)
  assert chain.canInstallPrepared(update)
  chain.installPrepared(update)
  let final = chain.chainView.bestBlock.value
  assert final.hasBlockBody, "genuine whole-current publication retains the admitted assurance body"
  let rules = limits.reporting
  result.context = AuditContextLimits(admission: rules.admission, disputes: rules.disputes,
    safrole: rules.safrole, availability: rules.availability,
    bodyBytes: ByteLimit(100000), chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(8000000),
        workspaceBytes: ByteLimit(128000000),
    outputBytes: ByteLimit(8000000), reports: ElementLimit(2), hashes: ElementLimit(4),
        hashBytes: ByteLimit(1000000))
  result.view = chain.chainView
  result.blockHash = final.blockHash
  result.packets = packets

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Test process paths belong to the native runner's private directory.
proc waitOwner(owner: var Services) =
  ## Observe only synchronized scalar phase until Done, without touching canonical, key or origin aliases.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
proc authenticatedFaultCase(padding: bool) {.raises.} =
  ## A genuinely admitted/assured dishonest report remains undecided from unproved direct bytes; original-coordinate authenticated recovery creates its actual negative capability.
  let fixture = faultFixture(padding)
  let retained = captureAuditOrigin(fixture.view, fixture.blockHash, fixture.context,
    AuditOriginLimits(entries: ElementLimit(10000), nodes: TrieNodeLimit(1000000),
        valueBytes: ByteLimit(8000000)))
  if retained.error != AuditOriginError.None:
    echo "authenticated fault origin refusal ", retained.error
    if retained.error == AuditOriginError.ContextFailure:
      echo "authenticated fault context refusal ", retained.contextError.error
  assert retained.error == AuditOriginError.None, "real current available dishonest reports retain complete execution origin"
  let origin = retained.value
  assert origin.originInfo.value.reports == 2, "only actual assurance output creates these audit targets"
  var keyFile = "negative-audit-key-" & $processId() & ".pem"
  var certificateFile = "negative-audit-certificate-" & $processId() & ".pem"
  var stateFile = "negative-audit-state-" & $processId() & ".json"
  assuranceSignerFiles(keyFile, certificateFile, 12)
  writeFile(stateFile, currentApplicationText(fixture.view.bestBlock.value))
  defer:
    discard posix.unlink(keyFile.toCString())
    discard posix.unlink(certificateFile.toCString())
    discard posix.unlink(stateFile.toCString())
  let signer = loadWorkSigner(certificateFile, keyFile).value
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", stateFile], options)
  var owner = default(Services)
  defer:
    owner.close()
  assert owner.start(options, "actual negative audit evaluation")
  assert owner.configureAudits(registryLimits())
  let selected = owner.retainAuditOrigin(origin).value
  let identity = origin.originContext.value.auditorAt(1).value.ed25519
  assert owner.configureAuditSigner(certificateFile, keyFile, identity).error ==
      WorkSigningSetupError.None
  for ordinal in 0..<2:
    let target = origin.reportAt(ordinal).value
    let header = target.originReport.value.ownedReportInfo.value.header
    let expected = AvailabilitySpecifier(packageHash: header.packageHash,
      bundleLength: header.bundleLength,
      erasureRoot: header.erasureRoot, erasureShards: header.erasureShards,
      segmentRoot: header.segmentRoot, segmentCount: header.segmentCount)
    let proof = AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(10000),
        hashBytes: ByteLimit(1000000))
    var packets: seq[VerifiedAvailabilityTransfer] = @[]
    for index in [0, 4, 5]:
      let packet = fixture.packets[index]
      let verified = verifyAvailabilityTransfer(expected, packet.request,
        packet.chunk, [], packet.proof, proof)
      assert verified.error == AvailabilityTransferError.None, "root-bound bytes authenticate independently of dishonest signed package metadata"
      packets.add(verified.value)
    let recovered = recoverAuditBundle(target, packets, recoveryLimits())
    assert recovered.error == AuditRecoveryError.None and recovered.value.invalidPadding == padding
    if padding:
      assert recovered.value.recoveredBundle.error == AuditRecoveryError.InvalidPacket, "authenticated nonzero padding grants no successful raw bundle prefix"
    else:
      let direct = evaluateDirectAudit(target, recovered.value.recoveredBundle.value,
          evaluationLimits())
      assert direct.error == AuditEvaluationError.BundleFailure and direct.needsRecovery, "unproved direct mismatch grants no negative capability"
    let completed = evaluateRecoveredAudit(target, recovered.value, evaluationLimits())
    assert completed.error == AuditEvaluationError.None and
        not completed.value.evaluationInfo.value.positive, "actual authenticated original bundle proves the admitted package commitment dishonest"
    assert completed.value.matchesOrigin(target), "negative evidence binds the exact genuine private source"
    let signed = signAuditJudgment(signer, completed.value, StateValidatorIndex(1))
    assert signed.error == AuditSigningError.None
    verifySignedAudit(signed.value, target, false)
    assert owner.beginAuditSigning(selected, ordinal, StateValidatorIndex(1)).error ==
        StateProofAdmissionError.QueryFailure, "an actual negative claim or public metadata still cannot fill Services' private evaluation slot"
    let cancelled = owner.beginAuditRecoveryEvaluation(selected, ordinal, packets, recoveryLimits(),
        evaluationLimits()).value
    owner.waitOwner()
    assert owner.cancelStateProof(cancelled)
    assert owner.collectAudit(cancelled).kind == ManagedAuditKind.Cancelled, "cancelled Done authenticated evaluation does not install a private negative capability"
    assert owner.beginAuditSigning(selected, ordinal, StateValidatorIndex(1)).error ==
        StateProofAdmissionError.QueryFailure
    let duplicated = @[packets[0], packets[0], packets[2]]
    let bad = owner.beginAuditRecoveryEvaluation(selected, ordinal, duplicated, recoveryLimits(),
        evaluationLimits()).value
    owner.waitOwner()
    let rejected = owner.collectAudit(bad)
    assert rejected.kind == ManagedAuditKind.RecoveryFailure and rejected.recoveryError.error ==
        AuditRecoveryError.DuplicateShard, "actual worker recovery failure exposes no accepted prefix"
    assert owner.beginAuditSigning(selected, ordinal, StateValidatorIndex(1)).error ==
        StateProofAdmissionError.QueryFailure
    let started = owner.beginAuditRecoveryEvaluation(selected, ordinal, packets, recoveryLimits(),
        evaluationLimits()).value
    owner.waitOwner()
    assert owner.collectStateProof(started).kind == ProofWorkerCompletionKind.Uninitialized, "generic collection cannot expose recovered private evaluation"
    let evaluated = owner.collectAudit(started)
    assert evaluated.kind == ManagedAuditKind.Evaluated and not evaluated.evaluationInfo.positive, "whole authenticated recovery/evaluation installs actual private negative evidence"
    let signing = owner.beginAuditSigning(selected, ordinal, StateValidatorIndex(1)).value
    owner.waitOwner()
    let managed = owner.collectAudit(signing)
    assert managed.kind == ManagedAuditKind.JudgmentSigned and managed.signingId == selected and
        managed.signingOrdinal == ordinal
    verifySignedAudit(managed.signedJudgment, target, false)

    var registry = default(AuditOriginRegistry)
    assert registry.configure(registryLimits())
    let id = registry.retain(origin).value
    assert registry.rememberEvaluation(id, ordinal, completed.value).error ==
        AuditRegistryError.None, "only complete exact source evidence installs a private negative evaluation"
    assert not registry.evaluationInfo(id, ordinal).value.positive
    registry.clear()

proc authenticatedFaultChecks*() {.raises.} =
  ## Genuine current publication separately proves dishonest package identity and authenticated invalid erasure padding, with no synthetic source or private key injection.
  authenticatedFaultCase(false)
  authenticatedFaultCase(true)
