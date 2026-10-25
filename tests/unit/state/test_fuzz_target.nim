# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit startup policies and real candidate failures distinguish consensus Error replies from local faults.
import std/[assertions, envvars, syncio]
import ../../support/[fuzz_backend_context, accumulation_current_chain_context, current_consecutive_context]
import ../../support/fuzz_fork_context
import ../../../src/app/[chain, fuzz_target, fuzz_backend, fuzz_rejection, candidate]
import ../../../src/codec/[bounded, header, report_owned, block_codec]
import ../../../src/state/[store, fuzz_protocol, fuzz_ancestry, report_admission,
  accumulation_queue,
  accumulation_round, accumulation_current_completion, accumulation_current_update, accumulation_current_chain]
import ../../../src/chain/[provider, genesis]
proc main() {.raises.} =
  ## Pure startup selection opens no listeners and cannot derive Parameters from seed bytes.
  let supplied = fuzzBackendTestConfig()
  let environment = FuzzEnvironment(enabled: true, spec: "tiny", dataPath: "/tmp/private-fuzz",
      socketPath: "/tmp/private-fuzz/target.sock")
  let absent = default(FuzzTargetResult)
  assert absent.error == FuzzTargetError.Uninitialized
  let prepared = prepareFuzzTarget(environment, supplied.parameters, supplied.candidate,
      ElementLimit(1000), ByteLimit(1000000))
  assert prepared.error == FuzzTargetError.None
  assert prepared.value.socket.peer.features == 3
  assert prepared.value.socket.peer.jam.minor == 8
  var changed = environment
  changed.enabled = false
  assert prepareFuzzTarget(changed, supplied.parameters, supplied.candidate, ElementLimit(1),
      ByteLimit(1)).error == FuzzTargetError.MissingEnvironment
  for which in 0..<3:
    changed = environment
    case which
    of 0: changed.spec = "" # All standard mandatory variables must be explicitly present.
    of 1: changed.dataPath = ""
    else: changed.socketPath = ""
    assert prepareFuzzTarget(changed, supplied.parameters, supplied.candidate, ElementLimit(1),
        ByteLimit(1)).error == FuzzTargetError.MissingEnvironment
  changed = environment
  changed.spec = "unknown"
  assert prepareFuzzTarget(changed, supplied.parameters, supplied.candidate, ElementLimit(1),
      ByteLimit(1)).error == FuzzTargetError.InvalidSpec
  changed.spec = "full"
  assert prepareFuzzTarget(changed, supplied.parameters, supplied.candidate, ElementLimit(1),
      ByteLimit(1)).error == FuzzTargetError.ProfileMismatch
  changed = environment
  changed.logLevel = "verbose"
  assert prepareFuzzTarget(changed, supplied.parameters, supplied.candidate, ElementLimit(1),
      ByteLimit(1)).error == FuzzTargetError.InvalidLogLevel
  for path in ["relative", "/tmp/hidden\0suffix", "/tmp/line\nnext"]:
    changed = environment
    changed.socketPath = path
    assert prepareFuzzTarget(changed, supplied.parameters, supplied.candidate, ElementLimit(1),
        ByteLimit(1)).error == FuzzTargetError.InvalidPath
  assert prepareFuzzTarget(environment, supplied.parameters, supplied.candidate, ElementLimit(
      1000001), ByteLimit(1)).error == FuzzTargetError.InvalidBudget
  assert prepareFuzzTarget(environment, supplied.parameters, supplied.candidate, ElementLimit(1),
      ByteLimit(67108865)).error == FuzzTargetError.InvalidBudget
  let noCandidate = default(CurrentCandidateResult)
  assert not consensusFuzzRejection(noCandidate)
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Unchanged frozen report seeds a genuinely authenticated test parent.
  let context = currentChainFixture(decodeOwnedReport(report, 2).value, ticket = true,
      completeState = true)
  let ordinary = genesisView(context.parent)
  let isolated = fuzzSeedView(context.parent)
  assert not ordinary.fuzzOnly and isolated.fuzzOnly
  assert not sameChainView(ordinary, isolated)
  assert isolated.finalizeView(context.parent.value.blockHash).value.fuzzOnly
  let policy = supplied.candidate.reporting.reports.ancestors
  let ancestry = captureFuzzAncestry(context.parent.value.header, [], FuzzAncestryLimits(
    header: policy.header, records: policy.headers, bytes: policy.maxBytes)).value
  let staged = context.source.currentChainAdmission.reportBlockStage.value
  let reports = completeFuzzBlockReports(prepareBlockReports(staged,
    supplied.candidate.reporting.reports).value, ancestry)
  assert reports.error == ReportAdmissionError.None and reports.value.requiresFuzzView
  let queue = planBlockAccumulationQueue(reports.value, supplied.candidate.queue).value
  let round = planBlockInitialAccumulation(queue, supplied.candidate.round).value
  let composed = runCurrentAccumulationCompletion(round, supplied.parameters,
      supplied.candidate.completion)
  assert composed.error == CurrentAccumulationCompletionError.None
  var state = forkStateStore(context.parent.value.stateSnapshot).value
  var view = ordinary
  let refused = applyCurrentAccumulationChain(state, view, composed.value,
      supplied.candidate.headerBytes)
  assert refused.error == CurrentAccumulationChainError.ProfileMismatch
  assert sameChainView(view, ordinary)
  var fuzzChain = initApplicationChain(isolated).value
  let fuzzUpdate = fuzzChain.prepareAccumulation(composed.value, supplied.candidate.headerBytes)
  assert fuzzUpdate.error == CurrentChainPreparationError.None
  let production = initApplicationChain(ordinary).value
  assert not production.canInstallPrepared(fuzzUpdate.value)
  fuzzChain.installPrepared(fuzzUpdate.value)
  assert fuzzChain.chainView.fuzzOnly
  let initialize = fuzzInitialize(context.parent.value.header, context.parent.value.stateSnapshot)
  let child = currentEmptyChild(context.parent.value)
  var wire = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(wire).error == FrameError.None
  for offset in [32, 296]:
    var changed = wire
    changed[offset] = changed[offset] xor 1 # Prior-state commitment and final seal byte are actual protocol-invalid mutations.
    let invalid = decodeBlock(changed, supplied.wire.frame)
    assert invalid.error == FrameError.None
    var backend = initFuzzBackend(supplied).value
    assert backend.executeFuzz(initialize).error == FuzzBackendError.None
    let failure = backend.executeFuzz(fuzzImport(invalid.value.owner))
    assert failure.error == FuzzBackendError.CandidateFailure
    assert consensusFuzzRejection(failure.candidateFailure)
  var linear = initFuzzBackend(supplied).value
  assert linear.executeFuzz(initialize).error == FuzzBackendError.None
  assert linear.executeFuzz(fuzzImport(child)).error == FuzzBackendError.None
  let sibling = fuzzSiblingChild(context.parent.value, AuthorIndex(1))
  let disabled = linear.executeFuzz(fuzzImport(sibling))
  assert disabled.error == FuzzBackendError.CandidateFailure
  assert consensusFuzzRejection(disabled.candidateFailure) # A zero fork window cannot admit siblings in a non-negotiated session.
  var limited = supplied
  limited.candidate.reporting.admission.maxParentHeaderBytes = ByteLimit(1)
  var backend = initFuzzBackend(limited).value
  assert backend.executeFuzz(initialize).error == FuzzBackendError.None
  let failure = backend.executeFuzz(fuzzImport(child))
  assert failure.error == FuzzBackendError.CandidateFailure
  assert not consensusFuzzRejection(failure.candidateFailure) # The exact same valid child exceeds caller policy; it must close locally.
  echo "PASS JAM fuzzer target: explicit startup and genuine consensus-versus-local failures"
try:
  main() # Missing fixtures or runtime/backend errors fail the complete native test.
except:
  quit(2)
