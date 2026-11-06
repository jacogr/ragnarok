# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual available reports and their original computed bundles reproduce through private complete-state origins; damaged direct bytes and local resource/cancellation failures never become negative evidence.
import std/[assertions, syncio]
import ../../src/jamnp-s/[audit_origin, audit_context, audit_evaluation, audit_registry, work_report]
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
  registry.clear()
  assert registry.configure(registryLimits())
  let renewed = registry.retain(captured).value
  assert renewed != id and registry.origin(id).error == AuditRegistryError.InvalidId, "cleared lifetime cannot accept an old source selector"
  registry.clear()
  other.clear()
  limited.clear() # All complete-map/evaluation aliases retire only while no native borrower exists.
