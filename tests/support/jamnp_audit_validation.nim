# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal independent shuffle expectations and actual prior-roster Bandersnatch proofs qualify initial CE144 evidence without adopting the unresolved later-tranche scheme.
import std/assertions
import ../../src/jamnp-s/[audit_context, audit_validation, audit_receipt, audits]
import ../../src/chain/provider
import ../../src/app/audit_pool
import ../../src/bandersnatch/bandersnatch
import ../../src/codec/[bounded, assurances, disputes]
import ../../src/codec/work/report
proc proofLimits(): AuditProofLimits =
  ## One actual Thin proof and two BLAKE2b groups have separate literal finite resource reservations.
  AuditProofLimits(proofs: ElementLimit(1), hashes: ElementLimit(2), bytes: ByteLimit(4096),
      hashBytes: ByteLimit(72))
proc shuffleVectors() =
  ## Python hashlib's independent seed0..31 vectors preserve shrinking-swap and group-counter/LE32 semantics at full active-core population.
  var seed = default(array[32, byte])
  for index in 0..<seed.len: seed[index] = byte(index)
  let full = initialAuditSelection(CoreCount(341), BsOutput(seed), proofLimits())
  assert full.error == AuditValidationError.None and full.value.count == 10, "bounded maximum initial tranche"
  const maximum = [213, 174, 36, 148, 230, 128, 303, 78, 40, 33]
  const smaller = [11, 6, 15, 12, 14, 8, 5, 2, 4, 10]
  let small = initialAuditSelection(CoreCount(17), BsOutput(seed), proofLimits()).value
  for ordinal in 0..<10:
    assert uint64(full.value.cores[ordinal]) == uint64(maximum[ordinal]), "independent full-size shuffle vector"
    assert uint64(small.cores[ordinal]) == uint64(smaller[ordinal]), "independent two-group smaller vector"
  let tiny = initialAuditSelection(CoreCount(3), BsOutput(seed), proofLimits()).value
  var mask = 0'u8
  for ordinal in 0..<tiny.count:
    mask = mask or byte(1 shl int(uint64(tiny.cores[
        ordinal]))) # All three original core positions remain selected even when only a subset has available work.
  assert tiny.count == 3 and mask == 7, "short vectors select all active cores"
  assert initialAuditSelection(CoreCount(0), BsOutput(seed), proofLimits()).error ==
      AuditValidationError.InvalidSource, "zero active population is unavailable"
  assert initialAuditSelection(CoreCount(342), BsOutput(seed), proofLimits()).error ==
      AuditValidationError.InvalidSource, "physical maximum is checked before indexing"
  var limited = proofLimits()
  limited.hashes = ElementLimit(1)
  assert initialAuditSelection(CoreCount(341), BsOutput(seed), limited).error ==
      AuditValidationError.LimitExceeded, "two complete groups reserved before hashing"
  limited = proofLimits()
  limited.hashBytes = ByteLimit(71)
  assert initialAuditSelection(CoreCount(341), BsOutput(seed), limited).error ==
      AuditValidationError.LimitExceeded, "exact entropy-input byte reservation"
  limited = proofLimits()
  limited.bytes = ByteLimit(4095)
  assert initialAuditSelection(CoreCount(341), BsOutput(seed), limited).error ==
      AuditValidationError.LimitExceeded, "transient work reservation before crypto"
proc receiptLimits*(context: AuditContextLimits): AuditReceiptLimits =
  ## Two complete context/proof occurrences have explicit aggregate input, output and crypto reservations.
  AuditReceiptLimits(message: AuditLimits(validators: ValidatorCount(9), cores: CoreCount(3),
      bytes: ByteLimit(266), records: ElementLimit(2)),
    context: context, proof: AuditProofLimits(proofs: ElementLimit(2), hashes: ElementLimit(4),
        bytes: ByteLimit(4096), hashBytes: ByteLimit(144)),
    retainedBytes: ByteLimit(17000000))
proc auditValidationChecks*(context: AuditContext, source: ChainView,
    contextLimits: AuditContextLimits): seq[byte] =
  ## A genuine complete context and real prior-C8 private test scalar produce the original proof; independent literal wire then passes the maintained message decoder.
  shuffleVectors()
  let info = context.contextInfo.value
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  let public = key.publicKey.value
  var index = -1
  for ordinal in 0..<info.auditors:
    if array[32, byte](context.auditorAt(ordinal).value.bandersnatch) == array[32, byte](
        public): index = ordinal
  assert index >= 0, "test-owned scalar matches an actual original auditor key"
  var transcript: seq[byte] = @[106'u8, 97, 109, 95, 97, 117, 100, 105, 116]
  for octet in info.entropy: transcript.add(octet) # Literal ASCII jam_audit followed by the actual verified header output, no prefix/dollar/terminator.
  let signed = sign(key, transcript, [])
  assert signed.error == BsError.None, "real original Thin audit signature"
  let ordinal = JudgeIndex(uint16(index))
  assert produceInitialAudit(context, ordinal, key, proofLimits()).error ==
      AuditValidationError.LimitExceeded, "production reserves signing and verification"
  var productionLimits = proofLimits()
  productionLimits.proofs = ElementLimit(2)
  let produced = produceInitialAudit(context, ordinal, key, productionLimits)
  assert produced.error == AuditValidationError.None, "local key produces a qualified CE144 claim"
  let producedProof = produced.value.announcementRecord.value.proof
  let independentlyVerified = verify(public, BsSignature(array[96, byte](producedProof)),
      transcript, [])
  assert independentlyVerified.error == BsError.None, "production signs the independent pinned transcript"
  assert produced.value.announcementInfo.value.selected == info.reports,
      "production retains all available reports selected in the small core domain"
  scalar[0] = 2
  let wrong = importScalar(scalar).value
  assert produceInitialAudit(context, ordinal, wrong, productionLimits).error ==
      AuditValidationError.InvalidAuditor, "a foreign private key cannot claim the original ordinal"
  var wire: seq[byte] = @[]
  for octet in array[32, byte](info.blockHash): wire.add(octet)
  wire.add(byte(index and 255))
  wire.add(byte((index shr 8) and 255))
  wire.add(0) # E2 validator ordinal and one-byte initial intent, with no outer sequence count.
  for octet in array[96, byte](signed.value): wire.add(octet)
  assert wire.len == 131, "independent exact initial announcement extent"
  let decoded = decodeAnnouncements(wire, AuditLimits(validators: ValidatorCount(uint64(
      info.auditors)),
    cores: info.maximumCores, bytes: ByteLimit(131), records: ElementLimit(1)))
  assert decoded.error == AuditError.None and decoded.value.len == 1, "real current CE144 message schema"
  let claim = decoded.value.announcementAt(0).value
  let accepted = qualifyInitialAudit(context, claim, proofLimits())
  assert accepted.error == AuditValidationError.None, "genuine source-bound initial audit proof: " &
      $accepted.error
  let checked = accepted.value
  assert checked.valid and checked.announcementInfo.value.tranche == 0 and
      checked.announcementInfo.value.selected == info.reports,
    "all three active cores are considered before filtering actual available reports"
  for ordinal in 0..<info.reports:
    assert uint64(checked.selectedCore(ordinal).value) == uint64(context.availableCore(
        ordinal).value), "only original newly available reports become obligations"
  assert checked.selectedCore(info.reports).error == AuditValidationError.InvalidIndex, "no selected prefix beyond actual work"
  assert not default(CheckedAuditAnnouncement).valid and default(
      CheckedAuditAnnouncement).announcementInfo.error == AuditValidationError.Uninitialized,
    "metadata defaults cannot stand in for proof qualification"
  var changed = claim
  var header = array[32, byte](changed.header)
  header[0] = header[0] xor 1
  changed.header = AuditHeaderHash(header)
  assert qualifyInitialAudit(context, changed, proofLimits()).error ==
      AuditValidationError.InvalidClaim, "exact block identity precedes crypto"
  changed = claim
  changed.validator = JudgeIndex(uint16(info.auditors))
  assert qualifyInitialAudit(context, changed, proofLimits()).error ==
      AuditValidationError.InvalidAuditor, "original ordinal namespace bounds"
  changed = claim
  changed.intent = AuditIntent.Later
  assert qualifyInitialAudit(context, changed, proofLimits()).error ==
      AuditValidationError.UnsupportedTranche, "unapproved later-tranche interpretation stays gated"
  changed = claim
  var damaged = array[96, byte](changed.proof)
  damaged[0] = damaged[0] xor 1
  changed.proof = AuditProof(damaged)
  let refused = qualifyInitialAudit(context, changed, proofLimits())
  assert refused.error == AuditValidationError.ProofFailure and refused.proofError.error !=
      BsError.None, "actual malformed/invalid proof failure remains selected"
  var dollar: seq[byte] = @[36'u8]
  for octet in transcript: dollar.add(octet)
  changed = claim
  changed.proof = AuditProof(array[96, byte](sign(key, dollar, []).value))
  assert qualifyInitialAudit(context, changed, proofLimits()).error ==
      AuditValidationError.ProofFailure, "token dollar is never a signing-domain byte"
  var limited = proofLimits()
  limited.hashes = ElementLimit(0)
  assert qualifyInitialAudit(context, claim, limited).error == AuditValidationError.LimitExceeded, "whole initial selection work precedes cryptographic primitive admission"

  let limits = receiptLimits(contextLimits)
  var batch = wire
  for octet in wire: batch.add(octet) # Repeated declarations remain visible to the later obligation pool; receipt does not invent duplicate consensus authority.
  var invalid = limits
  invalid.message.validators = ValidatorCount(0)
  assert not invalid.valid and qualifyAuditAnnouncements(source, batch, invalid).error ==
      AuditReceiptError.InvalidPolicy, "missing wire population cannot activate managed receipt"
  invalid = limits
  invalid.message.cores = CoreCount(2)
  assert not invalid.valid, "wire core domain must match actual context capture policy"
  invalid = limits
  invalid.message.validators = ValidatorCount(6)
  assert not invalid.valid, "wire original-ordinal ceiling must match canonical roster policy"
  let complete = qualifyAuditAnnouncements(source, batch, limits)
  assert complete.error == AuditReceiptError.None and complete.value.valid and complete.value.len ==
      2, "whole two-record authenticated batch"
  assert complete.value.announcementAt(2).error == AuditReceiptError.InvalidIndex, "bounded immutable batch lookup"
  var pool = default(AuditIntentPool)
  assert pool.configure(1, ByteLimit(17000000)), "explicit bounded intent storage"
  assert pool.remember(complete.value) and pool.len == 1, "same-message duplicate intent occupies one slot"
  let occupied = pool.occupiedBytes
  assert pool.remember(complete.value) and pool.len == 1 and pool.occupiedBytes == occupied, "retransmitted proof cannot multiply retained obligations"
  var different = batch
  different[32] = 0
  different[33] = 0
  let differentBatch = qualifyAuditAnnouncements(source, different, limits)
  assert differentBatch.error == AuditReceiptError.None, "same actual Bandersnatch key at another original ordinal has its own proof namespace"
  assert not pool.remember(differentBatch.value) and pool.len == 1 and pool.occupiedBytes ==
      occupied, "full pool refuses whole additional batch without changing existing intent"
  pool.expireBefore(info.epoch)
  assert pool.len == 1 and pool.occupiedBytes == occupied
  pool.expireBefore(info.epoch+1)
  assert pool.len == 0 and pool.occupiedBytes == 0, "retired declaration releases its context charge"
  pool.expireBefore(info.epoch)
  assert not pool.remember(complete.value), "the old qualified batch cannot reopen a retired epoch"
  pool.clear()
  assert pool.configure(1, ByteLimit(17000000)), "closed storage starts a fresh incarnation"
  assert not pool.remember(differentBatch.value) and pool.len == 0 and pool.occupiedBytes == 0, "late entry preflight cannot insert an earlier valid prefix"
  pool.clear()
  assert pool.configure(1, ByteLimit(info.retainedBytes+1023)), "independent byte-only capacity"
  assert not pool.remember(complete.value) and pool.len == 0, "context and fixed record overhead precede insertion"
  pool.clear()
  let absent = default(ChainView)
  let empty: seq[byte] = @[]
  assert qualifyAuditAnnouncements(absent, empty, limits).error ==
      AuditReceiptError.InvalidSource, "empty input cannot turn a default source into a checked batch"
  var reduced = limits
  reduced.proof.proofs = ElementLimit(1)
  assert qualifyAuditAnnouncements(source, batch, reduced).error == AuditReceiptError.LimitExceeded, "whole proof reservation precedes any record execution"
  reduced = limits
  reduced.retainedBytes = ByteLimit(16000000)
  assert qualifyAuditAnnouncements(source, batch, reduced).error == AuditReceiptError.LimitExceeded, "all output owners and record overhead are reserved"
  var malformed = batch
  malformed[malformed.len-1] = malformed[malformed.len-1] xor 1
  let failed = qualifyAuditAnnouncements(source, malformed, limits)
  assert failed.error == AuditReceiptError.ProofFailure and failed.proofError.error ==
      AuditValidationError.ProofFailure, "late proof refusal never returns an earlier accepted prefix"
  malformed = batch
  malformed[131] = malformed[131] xor 1
  let unknown = qualifyAuditAnnouncements(source, malformed, limits)
  assert unknown.error == AuditReceiptError.ContextFailure and unknown.contextError.error ==
      AuditContextError.UnknownBlock, "each header in a batch resolves against actual retained authority"
  assert not default(CheckedAuditBatch).valid and default(CheckedAuditBatch).announcementAt(
      0).error == AuditReceiptError.Uninitialized, "default is not a checked empty batch"
  return batch
