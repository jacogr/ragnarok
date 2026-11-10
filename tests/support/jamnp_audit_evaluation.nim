# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual available reports and their original computed bundles reproduce through private complete-state origins; damaged direct bytes and local resource/cancellation failures never become negative evidence.

import std/[assertions, syncio]
import ../../src/jamnp-s/[audit_origin, audit_context, audit_evaluation, audit_registry,
    work_report, audit_fetch, read_stream]
import ../../src/jamnp-s/[audit_recovery, availability_proof, availability_merkle]
import ../../src/state/erasure/words
import ../../src/codec/work/report
import ../../src/jamnp-s/assurance_store
import ../../src/state/[audit_bundle, input_refinement]
import ../../src/codec/[bounded, header]
from ../../src/codec/state/trie import TrieNodeLimit
import ../../src/chain/[genesis, provider]
import ../../src/codec/work/[package as work_package, digest as work_digest]
import ./[jamnp_audit_context, jamnp_work_report_fixture, pvm_input_refinement]

proc evaluationLimits*(): AuditEvaluationLimits =
  ## Independent explicit child policies cover the genuine small reports; package prefixes can occupy the entire permitted wire.
  AuditEvaluationLimits(bundle: AuditBundleLimits(package: fullPackageConfig(ByteLimit(20000)),
    extrinsics: ElementLimit(16), imports: ElementLimit(16), hashes: ElementLimit(1000),
    bytes: ByteLimit(20000), workspaceBytes: ByteLimit(8*1024*1024), hashBytes: ByteLimit(1000000)),
    execution: executionLimits(), report: workReportLimits(), comparisonBytes: ByteLimit(100000))

proc originalWire*(fixture: AuditContextFixture, target: AuditReportOrigin): seq[byte] =
  ## Select only bytes retained from the exact original computed report, independently of available-core or batch ordering.
  let expected = array[32, byte](target.originReportHash.value)
  for bundle in fixture.bundles:
    if array[32, byte](bundle.reportHash) == expected: return bundle.wire
  assert false, "actual original computed bundle missing for selected report"
  return @[]

proc diagnose(outcome: AuditEvaluationResult[AuditEvaluation]) =
  ## Bounded typed failure diagnostics appear only if the actual positive reproduction unexpectedly fails, never dumping source state or code.
  if outcome.error == AuditEvaluationError.None: return
  echo "audit evaluation refusal: ", outcome.error
  case outcome.error
  of AuditEvaluationError.BundleFailure: echo "bundle: ", outcome.bundleError.error
  of AuditEvaluationError.ExecutionFailure: echo "execution: ", outcome.executionError.error
  of AuditEvaluationError.ReportFailure: echo "report: ", outcome.reportError.error
  else: discard # The top-level type already explains resource, source, cancellation or canonical mismatch.

proc fetchLimits*(): AuditFetchLimits =
  ## Test-owned routing and reply caps independently cover the genuine nine-validator original reports.
  AuditFetchLimits(bytes: ByteLimit(1000000), replyBytes: ByteLimit(1000000))

proc framedAuditTransfer(packet: PreparedAvailabilityTransfer): seq[byte] =
  ## Independently frame the genuine original bundle shard and Merkle path with exact E4 lengths.
  result = @[]
  for bytes in [packet.bundleShard, packet.justification]:
    for index in 0..<4: result.add(byte((uint32(bytes.len) shr (index*8)) and 255))
    for octet in bytes: result.add(octet)

proc fetchChecks*(fixture: AuditContextFixture) =
  ## Real original credentials and literal cR+v vectors distinguish roster positions from both dense report order and shard indices.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  let context = origin.originContext.value
  assert not default(AuditFetchPlan).valid
  assert captureAuditFetch(default(AuditReportOrigin), fetchLimits()).error ==
      AuditFetchError.InvalidOrigin
  for report in 0..<2:
    # Two genuine reports occupy cores zero and one; with N=9 the pinned greatest-divisor recovery threshold is four.
    let target = origin.reportAt(report).value
    let outcome = captureAuditFetch(target, fetchLimits())
    assert outcome.error == AuditFetchError.None, "actual source-derived detached routing"
    let plan = outcome.value
    let info = plan.fetchInfo.value
    assert info.assurers == 9 and info.threshold == 4
    assert info.guarantors == target.originGuarantee.value.credentialCount
    for ordinal in 0..<info.guarantors:
      # Original guarantee ordinals select their own exact historical key, independently of relay identity.
      let expected = context.auditGuarantor(report, ordinal).value
      let actual = plan.targetAt(false, ordinal).value
      assert array[32, byte](actual.identity) == array[32, byte](expected.ed25519)
      let request = plan.requestAt(false, ordinal).value
      assert request.kind == ReadKind.Bundle and request.payload.len == 32
      assert request.payload == @(info.specifier.erasureRoot.bytes)
    let expected = if report == 0: [0, 1, 2, 3, 4, 5, 6, 7, 8] else: [4, 5, 6, 7, 8, 0, 1, 2, 3]
    for ordinal in 0..<9:
      # Every original position is retained even when its metadata has no dialable endpoint.
      let actual = plan.targetAt(true, ordinal).value
      assert uint64(actual.validator) == uint64(ordinal)
      assert uint64(actual.shard) == uint64(expected[ordinal]), "independent original shard permutation"
      assert array[32, byte](actual.identity) == array[32, byte](context.auditorAt(
          ordinal).value.ed25519)
      let request = plan.requestAt(true, ordinal).value
      let bytes = request.payload
      assert request.kind == ReadKind.Audit and bytes.len == 34
      assert int(bytes[32])+int(bytes[33])*256 == expected[ordinal]
    let firstShard = int(uint64(plan.targetAt(true, 0).value.shard))
    # Select by the actual signed report hash rather than assuming the computation batch matches available-core order.
    var selected = default(PreparedAvailabilityTransfer)
    for original in fixture.bundles:
      if array[32, byte](original.reportHash) == array[32, byte](target.originReportHash.value):
        selected = original.auditShards[firstShard]
    assert selected.valid
    let wire = framedAuditTransfer(selected)
    let proofLimits = AvailabilityMerkleLimits(bytes: ByteLimit(1000000),
      hashes: ElementLimit(1000), hashBytes: ByteLimit(1000000))
    let verified = verifyAuditFetchShard(plan, 0, wire, proofLimits)
    assert verified.error == AuditFetchError.None and uint64(verified.value.request.shard) ==
        uint64(firstShard)
    assert verifyAuditFetchShard(plan, 1, wire, proofLimits).error ==
        AuditFetchError.TransferFailure, "valid evidence at another original coordinate cannot substitute this target"
    var trailing = wire
    trailing.add(0)
    assert verifyAuditFetchShard(plan, 0, trailing, proofLimits).error ==
        AuditFetchError.InvalidPacket
    var truncated = wire
    truncated.setLen(truncated.len-1)
    assert verifyAuditFetchShard(plan, 0, truncated, proofLimits).error ==
        AuditFetchError.InvalidPacket
    var oversized = wire
    for index in 0..<4: oversized[index] = 255
    assert verifyAuditFetchShard(plan, 0, oversized, proofLimits).error ==
        AuditFetchError.InvalidPacket
    assert plan.targetAt(true, -1).error == AuditFetchError.InvalidIndex
    assert plan.requestAt(true, 9).error == AuditFetchError.InvalidIndex
    var limited = fetchLimits()
    limited.bytes = ByteLimit(1)
    assert captureAuditFetch(target, limited).error == AuditFetchError.LimitExceeded
    limited = fetchLimits()
    limited.replyBytes = ByteLimit(8)
    assert captureAuditFetch(target, limited).error == AuditFetchError.LimitExceeded

proc evaluationCycle*(fixture: AuditContextFixture) =
  ## Real authorization/refinement and all availability/report fields must equal the originally guaranteed report before an opaque positive capability exists.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  let target = origin.reportAt(0).value
  let completed = evaluateDirectAudit(target, fixture.originalWire(target), evaluationLimits())
  diagnose(completed)
  assert completed.error == AuditEvaluationError.None, "whole genuine direct report reproduction"
  let checked = completed.value
  assert checked.valid and checked.matchesOrigin(target) and checked.evaluationInfo.value.positive, "only exact source-bound equality grants a positive capability"
  assert array[32, byte](checked.evaluationInfo.value.reportHash) == array[32, byte](
      target.originReportHash.value), "whole signed canonical report identity"

proc stopNow(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## Immediate trusted execution cancellation retains no external callback graph.
  true

proc evaluationChecks*(fixture: AuditContextFixture) =
  ## Both original available reports, private source identity, input corruption and local quota refusals use genuine execution rather than caller-provided validity flags.
  evaluationCycle(fixture)
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  for ordinal in 0..<origin.originInfo.value.reports:
    let target = origin.reportAt(ordinal).value
    let wire = fixture.originalWire(target)
    let missing = evaluateDirectAudit(target, [], evaluationLimits())
    assert missing.error == AuditEvaluationError.BundleFailure and missing.needsRecovery, "unproved empty data cannot invalidate a genuine nonzero bundle claim"
    let completed = evaluateDirectAudit(target, wire, evaluationLimits())
    diagnose(completed)
    assert completed.error == AuditEvaluationError.None and
        completed.value.evaluationInfo.value.positive, "each genuinely available report reproduces completely"
    let checked = completed.value
    var copied = checked.evaluationInfo.value
    copied.positive = false
    assert checked.evaluationInfo.value.positive, "a copied public validity bit cannot retag a private capability"
    let separate = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(),
        auditOriginLimits()).value.reportAt(ordinal).value
    assert not checked.matchesOrigin(separate), "equal public roots cannot replace exact registered origin ownership"
    var damaged = wire
    damaged[0] = damaged[0] xor 1
    let bad = evaluateDirectAudit(target, damaged, evaluationLimits())
    assert bad.error == AuditEvaluationError.BundleFailure and bad.needsRecovery, "damaged unproved CE147 bytes require authenticated reconstruction, not a negative capability"
    var limited = evaluationLimits()
    limited.bundle.workspaceBytes = ByteLimit(1)
    let memory = evaluateDirectAudit(target, wire, limited)
    assert memory.error == AuditEvaluationError.BundleFailure and memory.bundleError.error ==
        AuditBundleError.LimitExceeded and not memory.needsRecovery, "local decoder quota is unavailable evaluation rather than evidence about a report"
    limited = evaluationLimits()
    limited.comparisonBytes = ByteLimit(1)
    let copyLimit = evaluateDirectAudit(target, wire, limited)
    assert copyLimit.error == AuditEvaluationError.LimitExceeded and not copyLimit.needsRecovery, "known insufficient comparison credit refuses before guest work"
    limited = evaluationLimits()
    limited.bundle.package.refineGas = Gas(1)
    limited.bundle.package.accumulateGas = Gas(1)
    let actualProfile = evaluateDirectAudit(target, wire, limited)
    assert actualProfile.error == AuditEvaluationError.None, "actual retained source parameters determine consensus package gas, not caller policy fields"
    let stopped = evaluateDirectAudit(target, wire, evaluationLimits(), assuranceScanControl(
        stopNow, nil))
    assert stopped.error == AuditEvaluationError.Cancelled and not stopped.needsRecovery, "execution cancellation cannot grant a judgment capability"
  let absent = default(AuditReportOrigin)
  let empty: seq[byte] = @[]
  assert evaluateDirectAudit(absent, empty, evaluationLimits()).error ==
      AuditEvaluationError.InvalidOrigin, "no partial or fabricated full-state source"
  assert not default(AuditEvaluation).valid and default(AuditEvaluation).evaluationInfo.error ==
      AuditEvaluationError.Uninitialized, "default metadata cannot become an evaluation capability"

proc registryLimits*(): AuditRegistryLimits =
  ## Aggregate private pins have explicit whole-map and detached-context ceilings independent from per-origin limits.
  AuditRegistryLimits(blocks: ElementLimit(2), entries: ElementLimit(20000), nodes: TrieNodeLimit(2000000),
    valueBytes: ByteLimit(16000000), contextBytes: ByteLimit(16000000))

proc registryChecks*(fixture: AuditContextFixture) =
  ## Genuine full origins bind trusted checkpoints, and namespace/aggregate/source checks prevent stale selectors or public metadata from installing private evaluation authority.
  let captured = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(),
      auditOriginLimits()).value
  let trusted = fixture.view.bestBlock
  assert captured.matchesTrustedBlock(trusted), "actual complete canonical block binds its original body and predecessor"
  assert not captured.matchesTrustedBlock(fixture.prior.bestBlock), "a different trusted header cannot admit this origin"
  let selected = trusted.value
  var bytes = newSeq[byte](selected.header.headerInfo.value.consumed)
  assert selected.header.encodeOwnedHeader(bytes).error == HeaderError.None
  let checkpoint = captureBlockSnapshot(bytes, selected.stateSnapshot, selected.chainParameters)
  assert checkpoint.error == GenesisError.None and not checkpoint.value.hasBlockBody, "independent trusted checkpoint omits the original body"
  assert captured.matchesTrustedBlock(checkpoint), "an authenticated full origin can supply material missing from a trusted checkpoint, unlike a bare header"
  var registry = default(AuditOriginRegistry)
  assert not registry.configure(default(AuditRegistryLimits)), "default private registry remains inactive"
  assert registry.configure(registryLimits()) and not registry.configure(registryLimits()), "explicit once-only private namespace"
  let id = registry.retain(captured).value
  assert id.valid and registry.len == 1 and registry.origin(id).error == AuditRegistryError.None, "genuine immutable source retained after whole preflight"
  let duplicate = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(),
      auditOriginLimits()).value
  assert registry.retain(duplicate).value == id and registry.len == 1, "repeated equivalent captures retain the original source instead of replacing it"
  var oneRow = registryLimits()
  oneRow.blocks = ElementLimit(1)
  var declarations = default(AuditOriginRegistry)
  assert declarations.configure(oneRow)
  let firstDuty = declarations.retain(captured, forDeclaration = true).value
  assert declarations.retain(duplicate, forDeclaration = true).value == firstDuty
  assert declarations.releaseDeclaration(firstDuty) and declarations.len == 1,
      "one completed duty must preserve the pending duty's origin"
  assert declarations.releaseDeclaration(firstDuty) and declarations.len == 0,
      "the final duty frees the entire reservation in the same epoch"
  assert declarations.origin(firstDuty).error == AuditRegistryError.InvalidId
  let reused = declarations.retain(captured, forDeclaration = true).value
  assert reused != firstDuty and declarations.retain(duplicate).value == reused
  assert declarations.releaseDeclaration(reused) and declarations.len == 1,
      "explicit retention must survive the last declaration's release"
  assert not declarations.releaseDeclaration(reused)
  let target = registry.origin(id).value.reportAt(0).value
  assert registry.evaluationInfo(id, 0).error == AuditRegistryError.NotEvaluated, "registration alone grants no private judgment capability"
  let evaluated = evaluateDirectAudit(target, fixture.originalWire(target), evaluationLimits()).value
  let remembered = registry.rememberEvaluation(id, 0, evaluated)
  assert remembered.error == AuditRegistryError.None and remembered.value, "actual exact registered source can install completed evaluation"
  assert not registry.rememberEvaluation(id, 0, evaluated).value, "identical completed evaluation is idempotent"
  assert registry.evaluationInfo(id, 0).value.positive and registry.evaluation(id,
      0).value.matchesOrigin(target), "fixed host metadata remains separate from the source-bearing private capability"
  let otherTarget = duplicate.reportAt(0).value
  let foreign = evaluateDirectAudit(otherTarget, fixture.originalWire(otherTarget),
      evaluationLimits()).value
  assert registry.rememberEvaluation(id, 0, foreign).error == AuditRegistryError.SourceConflict, "equal public roots do not replace exact registered execution ownership"
  var other = default(AuditOriginRegistry)
  assert other.configure(registryLimits())
  let foreignId = other.retain(captured).value
  assert foreignId != id and registry.origin(foreignId).error == AuditRegistryError.InvalidId, "foreign serial1 cannot select or retire this registry's source"
  assert registry.evaluationInfo(id, -1).error == AuditRegistryError.InvalidIndex and
      registry.evaluationInfo(id, 2).error == AuditRegistryError.InvalidIndex, "original report ordinals remain bounded"
  var limited = default(AuditOriginRegistry)
  var policy = registryLimits()
  policy.valueBytes = ByteLimit(1)
  assert limited.configure(policy)
  assert limited.retain(captured).error == AuditRegistryError.LimitExceeded and limited.len == 0, "aggregate value refusal installs no origin prefix"
  limited.clear()
  policy = registryLimits()
  policy.contextBytes = ByteLimit(1)
  assert limited.configure(policy)
  assert limited.retain(captured).error == AuditRegistryError.LimitExceeded and limited.len == 0, "full context and evaluation-slot credit precedes retention"
  let epoch = captured.originContext.value.contextInfo.value.epoch
  registry.expireBefore(epoch)
  assert registry.origin(id).error == AuditRegistryError.None,
      "origins in the oldest eligible epoch retain their exact selectors"
  registry.expireBefore(epoch+1)
  assert registry.len == 0 and registry.evaluationInfo(id, 0).error == AuditRegistryError.InvalidId,
      "retirement releases the origin and completed evaluation"
  registry.expireBefore(epoch)
  assert registry.retain(captured).error == AuditRegistryError.Expired,
      "a lower cutoff cannot reopen retired work"
  registry.clear()
  assert registry.configure(registryLimits())
  let renewed = registry.retain(captured).value
  assert renewed != id and registry.origin(id).error == AuditRegistryError.InvalidId, "cleared lifetime cannot accept an old source selector"
  registry.clear()
  other.clear()
  limited.clear() # All complete-map/evaluation aliases retire only while no native borrower exists.

proc recoveryLimits*(): AuditRecoveryLimits =
  ## Finite independent arithmetic and whole-copy credit cover this genuine small four-original-shard fixture.
  AuditRecoveryLimits(bytes: ByteLimit(16000000), products: FieldProductLimit(10000000))

proc proofLimits(): AvailabilityMerkleLimits =
  ## Full packet verification happens independently before threshold reconstruction.
  AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(10000),
      hashBytes: ByteLimit(1000000))

proc originalShards(fixture: AuditContextFixture, target: AuditReportOrigin): seq[
    PreparedAvailabilityTransfer] =
  ## Source selection follows the full original canonical report identity rather than trusting an ordinal or a detached root alone.
  let expected = array[32, byte](target.originReportHash.value)
  for bundle in fixture.bundles:
    if array[32, byte](bundle.reportHash) == expected: return bundle.auditShards
  assert false, "genuine original availability source missing"
  return @[]

proc verifiedPacket(packet: PreparedAvailabilityTransfer): VerifiedAvailabilityTransfer =
  ## The maintained CE138 verifier binds original coordinate/root and every exact message extent before returning a private checked handle.
  let verified = verifyAvailabilityTransfer(packet.specifier, packet.request,
    packet.bundleShard, packet.segmentShards, packet.justification, proofLimits())
  assert verified.error == AvailabilityTransferError.None, "actual original CE138 Merkle authentication"
  verified.value

proc recoveryChecks*(fixture: AuditContextFixture) =
  ## Original and nonconsecutive parity coordinates recover genuine bytes, while foreign metadata, duplicate points, bad proofs, local quotas and cancellation expose no evidence prefix.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  for ordinal in 0..<origin.originInfo.value.reports:
    let target = origin.reportAt(ordinal).value
    let source = fixture.originalShards(target)
    assert source.len == 9, "genuine original availability population"
    for selection in [[0, 1, 2, 3], [8, 2, 4, 6], [6, 4, 8, 2]]:
      var packets: seq[VerifiedAvailabilityTransfer] = @[]
      for index in selection: packets.add(verifiedPacket(source[index]))
      let recovered = recoverAuditBundle(target, packets, recoveryLimits())
      if recovered.error != AuditRecoveryError.None:
        echo "audit recovery refusal ", recovered.error, " report ", ordinal, " first shard ",
            selection[0]
        if recovered.error == AuditRecoveryError.ReconstructionFailure:
          echo "audit arithmetic refusal ", recovered.reconstructionError
      assert recovered.error == AuditRecoveryError.None, "actual authenticated threshold recovery"
      let evidence = recovered.value
      assert evidence.valid and evidence.matchesOrigin(target) and not evidence.invalidPadding, "complete exact private target binding"
      assert evidence.recoveredBundle.value == fixture.originalWire(target), "systematic and parity recovery reproduce every original bundle byte"
      let evaluated = evaluateRecoveredAudit(target, evidence, evaluationLimits())
      assert evaluated.error == AuditEvaluationError.None and
          evaluated.value.evaluationInfo.value.positive, "genuine recovered inputs reproduce the complete original report"
      let other = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(),
          auditOriginLimits()).value.reportAt(ordinal).value
      assert evaluateRecoveredAudit(other, evidence, evaluationLimits()).error ==
          AuditEvaluationError.InvalidRecovery, "equal public roots cannot retag authenticated recovery to another private target"
      var limited = evaluationLimits()
      limited.bundle.workspaceBytes = ByteLimit(1)
      let unavailable = evaluateRecoveredAudit(target, evidence, limited)
      assert unavailable.error == AuditEvaluationError.BundleFailure and
          not unavailable.needsRecovery, "authenticated bytes do not turn local execution quotas into a negative capability"
      let stoppedEvaluation = evaluateRecoveredAudit(target, evidence, evaluationLimits(),
          assuranceScanControl(stopNow, nil))
      assert stoppedEvaluation.error == AuditEvaluationError.Cancelled, "cancelled actual recovered evidence grants no judgment"
      let duplicate = @[packets[0], packets[0], packets[2], packets[3]]
      assert recoverAuditBundle(target, duplicate, recoveryLimits()).error ==
          AuditRecoveryError.DuplicateShard, "repeated original coordinates grant no threshold"
      let short = @[packets[0], packets[1], packets[2]]
      assert recoverAuditBundle(target, short, recoveryLimits()).error ==
          AuditRecoveryError.InvalidCount, "fewer than R distinct shards grant no recovered prefix"
      var policy = recoveryLimits()
      policy.bytes = ByteLimit(1)
      assert recoverAuditBundle(target, packets, policy).error == AuditRecoveryError.LimitExceeded, "whole input/output/scratch reservation precedes shard copies"
      if selection[0] == 8:
        policy = recoveryLimits()
        policy.products = FieldProductLimit(1)
        let refused = recoverAuditBundle(target, packets, policy)
        assert refused.error == AuditRecoveryError.ReconstructionFailure and
            refused.reconstructionError == ErasureWordError.LimitExceeded, "local arithmetic work ceiling is unavailable recovery, never encoding evidence"
      let cancelled = recoverAuditBundle(target, packets, recoveryLimits(), assuranceScanControl(
          stopNow, nil))
      assert cancelled.error == AuditRecoveryError.Cancelled, "trusted cancellation yields no accepted shard prefix"
    let packet = source[0]
    var metadata = packet.specifier
    metadata.packageHash.bytes[0] = metadata.packageHash.bytes[0] xor 1
    let foreign = verifyAvailabilityTransfer(metadata, packet.request, packet.bundleShard,
      packet.segmentShards, packet.justification, proofLimits())
    assert foreign.error == AvailabilityTransferError.None, "CE138 proof authenticates root/shard; original report metadata must be selected independently"
    let mismatched = @[foreign.value, verifiedPacket(source[1]), verifiedPacket(source[2]),
        verifiedPacket(source[3])]
    assert recoverAuditBundle(target, mismatched, recoveryLimits()).error ==
        AuditRecoveryError.InvalidPacket, "all original report availability fields bind recovery, not only a root"
    var damaged = packet.bundleShard
    damaged[0] = damaged[0] xor 1
    let invalid = verifyAvailabilityTransfer(packet.specifier, packet.request, damaged,
      packet.segmentShards, packet.justification, proofLimits())
    assert invalid.error != AvailabilityTransferError.None, "corrupt original CE138 bytes cannot construct a checked packet"
    let defaults = @[default(VerifiedAvailabilityTransfer), verifiedPacket(source[1]),
        verifiedPacket(source[2]), verifiedPacket(source[3])]
    assert recoverAuditBundle(target, defaults, recoveryLimits()).error ==
        AuditRecoveryError.InvalidPacket, "default packet cannot replace a proof"
    let absent = evaluateRecoveredAudit(target, default(AuditRecoveryEvidence), evaluationLimits())
    assert absent.error == AuditEvaluationError.InvalidRecovery, "unproved direct bytes grant no recovery authority"
  let empty = default(AuditRecoveryEvidence)
  assert not empty.valid, "no default authentication capability"

proc recoveryCycle*(fixture: AuditContextFixture) =
  ## Authentication, parity arithmetic, temporary copies and full recovered evaluation retire before the ARC observation.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  let target = origin.reportAt(0).value
  let source = fixture.originalShards(target)
  let packets = @[verifiedPacket(source[8]), verifiedPacket(source[2]), verifiedPacket(source[4]),
      verifiedPacket(source[6])]
  let recovered = recoverAuditBundle(target, packets, recoveryLimits())
  assert recovered.error == AuditRecoveryError.None
  let evaluated = evaluateRecoveredAudit(target, recovered.value, evaluationLimits())
  assert evaluated.error == AuditEvaluationError.None and
      evaluated.value.evaluationInfo.value.positive
