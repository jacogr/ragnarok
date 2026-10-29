# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed retained logical proof submission preserves typed admission failures and actual cancelled-Done collection/join ownership.
import std/[assertions, syncio, cmdline, monotimes, times, envvars]
import std/posix/posix
import ../../src/app/services
import ../../src/app/logical/proof as logical_proof
import ../../src/app/proof/[query as proof_query, worker as proof_worker]
import "../../src/app/current/block/input" as current_block_input
import ../../src/app/preparation_worker
import ../../src/state/current/logical as current_logical
import ../../src/state/proof/plan as proof_plan
import ../../src/state/planned/proof as planned_proof
import ../../src/state/proof/view as proof_view
import ../../src/state/store
import ../../src/chain/[genesis, provider]
import ../../src/codec/bounded
import ../support/[collected_native_context, collected_logical_services_context,
    managed_supplied_context, current_logical_proof_context, accumulation_current_candidate_context]
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Poll only scalar native phase under a bounded monotonic deadline.
proc waitProof(owner: var Services) =
  ## Done keeps the managed graph lease closed until exact collection or joined shutdown.
  let start = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000)
proc main() {.raises.} =
  ## Default result probes fail only at exact guards; positive controls use actual collected uninstalled successor provenance.
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalProofAdmission)
  case mode
  of "value": discard empty.value
  of "capture": discard empty.captureFailure
  of "admission": discard empty.admissionFailure
  else:
    if getEnv("RAGNAROK_STATE_REPORT").len == 0:
      putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Strict controls run at repository root; unit runs retain the explicit absolute fixture binding.
    let fixture = collectedNativeFixture()
    var owner = default(Services)
    var input = default(CurrentBlockInput)
    var path = "application-managed-logical-proofs-chain.json"
    let missing = default(CurrentLogicalState)
    let selection = logicalProofPlan()
    let limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
        query: logicalProofLimits())
    assert owner.beginLogicalProof(missing, selection, limits).error ==
        LogicalProofAdmissionError.Closed
    discard startLogicalServices(owner, fixture.fixture, path)
    defer:
      owner.close()
      discard posix.unlink(path.toCString())
    let originalHead = array[32, byte](owner.chainView.bestBlock.value.blockHash)
    let logical = collectManagedSupplied(owner, input, fixture.fixture)
    let root = logical.currentLogicalContext.value.state.commitment.root
    assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == originalHead
    let refused = owner.beginLogicalProof(missing, selection, limits)
    assert refused.error == LogicalProofAdmissionError.CaptureFailure
    assert refused.captureFailure.error == LogicalProofError.InvalidLogical
    assert not owner.stateProofActive
    var short = limits
    short.blocks = ElementLimit(0)
    assert owner.beginLogicalProof(logical, selection, short).captureFailure.error ==
        LogicalProofError.LimitExceeded
    short = limits
    short.query.hashes = ProofHashLimit(0)
    let queryRefused = owner.beginLogicalProof(logical, selection, short)
    assert queryRefused.captureFailure.error == LogicalProofError.QueryFailure
    assert not owner.stateProofActive
    let preparation = beginManagedCurrent(owner, input, [255'u8], [], currentCandidateLimits())
    owner.waitManagedPreparation()
    assert owner.cancelPreparation(preparation) and owner.preparationActive
    assert owner.beginLogicalProof(missing, selection, limits).error ==
        LogicalProofAdmissionError.Busy
    assert owner.collectPreparation(default(PreparationTicket)).kind ==
        PreparationCompletionKind.Uninitialized
    assert owner.preparationActive
    assert owner.collectPreparation(preparation).kind == PreparationCompletionKind.Cancelled
    assert not owner.preparationActive
    let ticket = owner.beginLogicalProof(logical, selection, limits).value
    owner.waitProof()
    assert owner.stateProofActive
    assert owner.beginLogicalProof(missing, selection, limits).error ==
        LogicalProofAdmissionError.Busy
    assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
        ProofWorkerCompletionKind.Uninitialized
    assert owner.stateProofActive
    let completion = owner.collectStateProof(ticket)
    assert completion.kind == ProofWorkerCompletionKind.Completed
    let response = completion.value.value
    assert not owner.stateProofActive and array[32, byte](response.stateRoot) == array[32, byte](root)
    let wire = response.bytes(limits.query.wireBytes).value
    let view = decodePlannedProofs(wire, selection, root, limits.query.view, limits.query.proof,
      limits.query.aggregate, limits.query.wireBytes).value
    checkLogicalProof(logical, view, 2)
    assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == originalHead
    let cancelled = owner.beginLogicalProof(logical, selection, limits).value
    owner.waitProof()
    assert owner.cancelStateProof(cancelled) and owner.stateProofActive
    assert owner.collectStateProof(ticket).kind == ProofWorkerCompletionKind.Uninitialized
    assert owner.stateProofActive
    assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Cancelled
    assert not owner.stateProofActive
    discard owner.beginLogicalProof(logical, selection, limits).value
    owner.close() # Joined close ends the actual queued/running/Done borrow before any source alias is observed or retired.
    assert owner.beginLogicalProof(logical, selection, limits).error ==
        LogicalProofAdmissionError.Closed
    assert captureLogicalProofQuery(logical, selection, limits).error == LogicalProofError.None
    let detached = decodePlannedProofs(wire, selection, root, limits.query.view, limits.query.proof,
      limits.query.aggregate, limits.query.wireBytes).value
    checkLogicalProof(logical, detached, 2)
    echo "application-managed-logical-proofs: ok"
try:
  main()
except:
  quit(2) # Setup/ordinary execution failures cannot impersonate a registered guard rejection.
