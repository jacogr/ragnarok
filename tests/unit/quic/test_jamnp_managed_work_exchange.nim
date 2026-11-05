# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_managed_work_exchange_arc_release"}

## Actual managed preparation/peer verification/collection preserves original sessions and independent native bytes through Done, cancellation and joined shutdown.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/[services, options, startup, work_guarantee_pool]
import ../../../src/app/proof/[worker, work_submission as jobs]
import ../../../src/jamnp-s/[work_signer, work_eligibility, work_guarantee, work_sharing,
  sharing_wire, work_stream, availability_read, availability_merkle, read_stream, work_distribution,
  report_cache, read_validation]
import ../../../src/codec/[bounded, guarantees, assurances]
import ../../../src/codec/state/safrole
import ../../../src/codec/state/trie as state_trie
import ../../../src/codec/work/package
import ../../../src/state/guarantee_credentials
import ../../../src/chain/[provider, genesis]
import ../../support/[jamnp_guarantee_fixture, jamnp_managed_work_context, jamnp_work_fixture,
  jamnp_work_report_fixture, jamnp_read_validation_context, pvm_input_refinement, arc_evidence]
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield while observing only synchronized worker phase or independent raw bytes.
proc policy(raw: WorkFixture): WorkSharingLimits =
  ## Resource budgets remain explicit and cannot replace consensus parameters obtained from the real canonical source.
  WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes), bundleBytes: ByteLimit(MaxBundleBytes),
    submission: raw.limits, execution: executionLimits(), report: workReportLimits(),
        eligibility: guaranteeLimits(), retention: guarantorLimits())
proc session(services: var Services, fixture: GuaranteeFixture, raw: WorkFixture,
    header: UntrustedWorkHeader): WorkSessionToken {.raises.} =
  ## The existing real TLS header feeds actual Services authorization, refinement, report computation and private-key signing.
  let token = services.reportSession(fixture, raw, header)
  let admitted = services.beginWorkContribution(token, fixture.local, StateTime(20),
      guaranteeLimits(), guarantorLimits())
  assert admitted.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Contributed
  token
proc peerFailure(services: Services, token: WorkSessionToken, reason: WorkGuaranteeError) =
  ## All extracted failure aliases retire inside this helper before any next worker admission.
  let outcome = services.workExchangeOutcome(token)
  assert outcome.kind == WorkJobResultKind.PeerResponseFailure
  assert outcome.peerResponseError.error == reason
proc verifyPayload(bytes: seq[byte], expectedCount: int) =
  ## Exact standalone GP decoding independently verifies slot, canonical order and committed threshold.
  let config = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      maxBytes: ByteLimit(20000))
  let parsed = decodeGuarantee(bytes, config)
  assert parsed.error == GuaranteeError.None and parsed.value.consumed == bytes.len
  let value = parsed.value.value
  assert uint32(value.slot) == 20 and value.credentialCount == expectedCount
  assert uint16(value.credentials[0].validator) == 1
  assert uint16(value.credentials[1].validator) == 2
  if expectedCount == 3: assert uint16(value.credentials[2].validator) == 5
proc prepared(services: var Services, token: WorkSessionToken) =
  ## Done reserves the exact source lease until matching primary collection commits the independently prepared caches.
  let admitted = services.beginWorkExchange(token, ByteLimit(20000))
  assert admitted.error == StateProofAdmissionError.None
  services.waitDone()
  assert not services.stateProofAvailable
  assert services.collectWorkSubmission(default(WorkSessionToken)) == WorkSessionPhase.Empty
  assert services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions
  let info = services.workExchangeInfo(token)
  assert info.targets == 2 and info.credentials == 1
proc accept(services: var Services, token: WorkSessionToken, position: int,
    identity: StateEdKey, response: array[96, byte]) =
  ## Detached byte/target caches remain usable during queued/running/Done verification without touching its private round graph.
  let admitted = services.beginWorkPeerResponse(token, position, identity, response)
  assert admitted.error == StateProofAdmissionError.None
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    assert services.workSharingRequest(token).sharingInfo.value.bundleBytes > 0
    assert services.workShareTarget(token, position).valid
    discard pauseMicros(100)
  assert not services.stateProofAvailable
  assert services.workSharingRequest(token).sharingInfo.value.bundleBytes > 0
  assert services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions
proc distributionPolicy(): WorkDistributionLimits =
  ## CPU report/source limits and recipient capacity are independent from native framing reservations.
  WorkDistributionLimits(eligibility: guaranteeLimits(), wireBytes: ByteLimit(20000),
      targets: ElementLimit(12))
proc candidate(bytes: seq[byte], count: int, slot: uint32): seq[byte] =
  ## Derive canonical credential subsets/current-rotation slots from genuine signatures without fabricating credential authority.
  let config = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      maxBytes: ByteLimit(20000))
  var value = decodeGuarantee(bytes, config).value.value
  value.credentialCount = count
  value.slot = GuaranteeSlot(slot)
  encodeGuaranteeValue(value, config).value
proc qualifyCandidate(services: var Services, bytes: seq[
    byte], now = StateTime(20)): WorkDistributionCompletion {.raises.} =
  ## Raw/source staging aliases retire before returning only a source-free matching completion.
  let request = decodeReadRequest(ReadKind.Guarantee, bytes).value
  let admitted = services.beginWorkDistribution(request, now, distributionPolicy())
  assert admitted.error == StateProofAdmissionError.None
  services.waitDone()
  let completed = services.collectWorkDistribution(admitted.value)
  assert completed.kind == WorkDistributionCompletionKind.Completed, "fresh candidate must qualify at its observed slot"
  completed
proc distributions(services: var Services, primary: WorkSessionToken, bytes: seq[byte]) {.raises.} =
  ## Distinct incoming verification never consumes a waiting primary guarantee or an unrelated proof ticket.
  let hash = services.chainView.bestBlock.value.blockHash
  let request = decodeReadRequest(ReadKind.Guarantee, bytes).value
  let admitted = services.beginWorkDistribution(request, StateTime(20), distributionPolicy())
  assert admitted.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.rpc.chainPaused and services.workDistributionActive(admitted.value)
  assert services.collectWorkDistribution(default(WorkDistributionToken)).kind ==
      WorkDistributionCompletionKind.Uninitialized
  assert services.collectWorkSubmission(primary) == WorkSessionPhase.Guaranteed
  assert services.workExchangeInfo(primary).credentials == 3
  let completed = services.collectWorkDistribution(admitted.value)
  assert completed.kind == WorkDistributionCompletionKind.Completed
  assert services.stateProofAvailable and not services.rpc.chainPaused
  assert completed.distributionInfo.targets == 12
  let facts = completed.distributionInfo
  assert uint32(facts.lastSlot) == 27 and facts.credentials == 3 and facts.wireBytes == bytes.len
  assert services.workDistributionCurrent(facts, StateTime(20))
  assert not services.workDistributionCurrent(facts, StateTime(21))
  var changed = facts
  var root = array[32, byte](facts.root)
  root[0] = root[0] xor 1
  changed.root = state_trie.StateRoot(root)
  assert not services.workDistributionCurrent(changed, StateTime(20)), "same header cannot authenticate a substituted complete root"
  changed = facts
  var head = array[32, byte](facts.head)
  head[0] = head[0] xor 1
  changed.head = genesis.BlockHash(head)
  assert not services.workDistributionCurrent(changed, StateTime(20)), "same root cannot substitute another complete head"
  assert sameWorkSession(primary, primary)
  assert not sameWorkSession(primary, default(WorkSessionToken))
  var pool = default(WorkGuaranteePool)
  assert not pool.remember(completed) # Default-disabled retention cannot justify an acknowledgment.
  assert pool.configure(1, ByteLimit(bytes.len))
  assert not pool.configure(2, ByteLimit(20000))
  assert pool.remember(completed) and pool.remember(completed)
  assert pool.len == 1 and pool.byteLength == bytes.len
  var retainedCopy = pool.payloadAt(0)
  retainedCopy[0] = retainedCopy[0] xor 1
  assert pool.payloadAt(0) == bytes
  var small = default(WorkGuaranteePool)
  assert small.configure(1, ByteLimit(bytes.len-1))
  assert not small.remember(completed) and small.len == 0 and small.byteLength == 0
  assert completed.distributionPayload == bytes
  var altered = completed.distributionPayload
  altered[0] = altered[0] xor 1
  assert completed.distributionPayload == bytes
  var cache = default(ReportCache)
  assert cache.remember(completed.distributionReport) == ReportCacheError.None
  let query = decodeReadRequest(ReadKind.Report, completed.distributionInfo.reportHash).value
  let pairBytes = candidate(bytes, 2, 20)
  let pair = qualifyCandidate(services, pairBytes)
  assert pool.remember(pair) and pool.payloadAt(0) ==
      bytes # Fewer credentials cannot replace a stronger equally fresh candidate.
  var upgraded = default(WorkGuaranteePool)
  assert upgraded.configure(1, ByteLimit(bytes.len))
  assert upgraded.remember(pair) and upgraded.payloadAt(0) == pairBytes
  assert upgraded.remember(completed) and upgraded.payloadAt(0) == bytes
  assert upgraded.len == 1 and upgraded.byteLength == bytes.len
  var tight = default(WorkGuaranteePool)
  assert tight.configure(1, ByteLimit(pairBytes.len)) and tight.remember(pair)
  assert not tight.remember(completed) and tight.payloadAt(0) == pairBytes
  let other = qualifyCandidate(services, candidate(bytes, 3, 21), StateTime(21))
  assert not pool.canRemember(other.distributionInfo) and not pool.remember(other)
  assert pool.len == 1 and pool.payloadAt(0) == bytes
  let foreign = services.beginNetworkRead(readStateRequest(hash))
  assert foreign.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkDistribution(admitted.value).kind ==
      WorkDistributionCompletionKind.Uninitialized
  assert not services.cancelWorkDistribution(admitted.value)
  let retained = cache.find(query)
  assert retained.error == ReportCacheError.None and retained.value.byteLength > 4
  assert not services.workDistributionCurrent(facts, StateTime(20))
  assert pool.payloadAt(0) == bytes
  pool.expire(StateTime(27))
  assert pool.len == 1
  pool.expire(StateTime(28))
  assert pool.len == 0 and pool.byteLength == 0
  assert completed.distributionPayload == bytes # Detached completion/cache ownership has no canonical alias through the foreign Done lease.
  assert services.stateProofPhase == ProofWorkerPhase.Done and services.rpc.chainPaused
  assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
  var broken = bytes
  broken[broken.high] = broken[broken.high] xor 1
  let invalid = services.beginWorkDistribution(decodeReadRequest(ReadKind.Guarantee, broken).value,
      StateTime(20), distributionPolicy())
  assert invalid.error == StateProofAdmissionError.None
  services.waitDone()
  let refused = services.collectWorkDistribution(invalid.value)
  assert refused.kind == WorkDistributionCompletionKind.Refused
  assert refused.distributionError.error == WorkDistributionError.CredentialFailure
  assert refused.distributionError.credentialError.error ==
      GuaranteeCredentialError.InvalidSignature
  let cancelled = services.beginWorkDistribution(request, StateTime(20), distributionPolicy())
  assert cancelled.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.cancelWorkDistribution(cancelled.value)
  assert services.rpc.chainPaused
  assert services.collectWorkDistribution(cancelled.value).kind ==
      WorkDistributionCompletionKind.Cancelled
  let stopped = services.beginWorkDistribution(request, StateTime(20), distributionPolicy())
  assert stopped.error == StateProofAdmissionError.None
  services.waitDone()
  services.stopStateProofs()
  assert not services.workDistributionActive(stopped.value)
  assert services.collectWorkDistribution(stopped.value).kind ==
      WorkDistributionCompletionKind.Uninitialized
  let restarted = services.beginWorkDistribution(request, StateTime(20), distributionPolicy())
  assert restarted.error == StateProofAdmissionError.None
  assert not services.cancelWorkDistribution(stopped.value)
  services.waitDone()
  assert services.collectWorkDistribution(restarted.value).kind ==
      WorkDistributionCompletionKind.Completed
  assert services.workSessionPhase(primary) == WorkSessionPhase.Guaranteed
proc unsignedReceiver(settings: Options, bytes: seq[byte]) {.raises.} =
  ## A validator receiving CE135 needs no private report-signing key; only its actual complete source is captured.
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "distribution receiver")
  assert not services.workSigningConfigured
  let request = decodeReadRequest(ReadKind.Guarantee, bytes).value
  let admitted = services.beginWorkDistribution(request, StateTime(20), distributionPolicy())
  assert admitted.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkDistribution(admitted.value).kind ==
      WorkDistributionCompletionKind.Completed
  assert not services.workSigningConfigured
proc managed(fixture: GuaranteeFixture, b, c: WorkSigner) {.raises.} =
  ## Private Services signing ownership never comes from an external signer alias; only actual certificate/key paths configure it.
  let raw = workFixture()
  let current = fixture.view.bestBlock.value
  let parent = fixture.view.parentOf(current.blockHash)
  assert parent.error == GenesisError.None
  writeFile("managed-exchange-chain.json", workChainText(parent.value))
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "managed-exchange-chain.json"], settings)
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "managed exchange")
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  let configured = services.configureWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv(
      "RAGNAROK_TEST_KEY"), fixture.local, guarantorStorageLimits())
  assert configured.error == WorkSigningSetupError.None
  let header = services.networkHeader(fixture, raw, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  let token = session(services, fixture, raw, header)
  let small = services.beginWorkExchange(token, ByteLimit(1))
  assert small.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Contributed
  block:
    # A byte-limit refusal preserves original signing authority without creating any prepared prefix.
    let rejected = services.workExchangeOutcome(token)
    assert rejected.kind == WorkJobResultKind.ExchangePreparationFailure
    assert rejected.exchangePreparationError.error == WorkSharingError.LimitExceeded
  prepared(services, token)
  let request = services.workSharingRequest(token)
  let keyB = b.signerIdentity.value
  let keyC = c.signerIdentity.value
  let peerView = genesisView(parent)
  let receivedB = receiveSharedWork(request, peerView, keyB, fixture.local, StateTime(20), b,
      policy(raw))
  let receivedC = receiveSharedWork(request, peerView, keyC, fixture.local, StateTime(20), c,
      policy(raw))
  assert receivedB.error == WorkSharingError.None and receivedC.error == WorkSharingError.None
  let responseB = receivedB.value.sharingResponse.value
  let responseC = receivedC.value.sharingResponse.value
  let incoming = services.beginWorkSharing(request, fixture.local, keyB, StateTime(20), policy(raw))
  assert incoming.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions
  assert not services.stateProofAvailable and services.workExchangeInfo(token).credentials == 1
  assert services.workSharingRequest(token).sharingInfo.value.bundleBytes > 0
  let shared = services.collectWorkSharing(incoming.value)
  assert shared.kind == WorkSharingCompletionKind.Completed
  assert services.workSessionPhase(token) == WorkSessionPhase.AwaitingContributions
  block:
    # Joined external stop revokes the incoming namespace, preserves the waiting primary round and permits a fresh generation to run.
    let stopped = services.beginWorkSharing(request, fixture.local, keyB, StateTime(20), policy(raw))
    assert stopped.error == StateProofAdmissionError.None
    services.waitDone()
    assert services.workSharingActive(stopped.value)
    services.stopStateProofs()
    assert services.stateProofAvailable and not services.workSharingActive(stopped.value)
    assert services.collectWorkSharing(stopped.value).kind ==
        WorkSharingCompletionKind.Uninitialized
    assert services.workSessionPhase(token) == WorkSessionPhase.AwaitingContributions
    let resumed = services.beginWorkSharing(request, fixture.local, keyB, StateTime(20), policy(raw))
    assert resumed.error == StateProofAdmissionError.None
    assert not services.cancelWorkSharing(stopped.value)
    services.waitDone()
    assert services.collectWorkSharing(resumed.value).kind == WorkSharingCompletionKind.Completed
  let premature = services.beginWorkGuaranteeCollection(token, ByteLimit(20000))
  assert premature.error == StateProofAdmissionError.QueryFailure
  let absent = services.beginWorkPeerResponse(token, 2, keyB, responseB)
  assert absent.error == StateProofAdmissionError.QueryFailure
  var altered = responseB
  altered[0] = altered[0] xor 1
  accept(services, token, 0, keyB, altered)
  peerFailure(services, token, WorkGuaranteeError.WrongReport)
  assert services.workExchangeInfo(token).credentials == 1
  accept(services, token, 0, keyB, responseB)
  assert services.workExchangeInfo(token).credentials == 2
  accept(services, token, 0, keyB, responseB)
  peerFailure(services, token, WorkGuaranteeError.Duplicate)
  accept(services, token, 1, keyB, responseC)
  peerFailure(services, token, WorkGuaranteeError.InvalidPeer)
  assert services.workExchangeInfo(token).credentials == 2
  let tiny = services.beginWorkGuaranteeCollection(token, ByteLimit(1))
  assert tiny.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.AwaitingContributions
  block:
    # A late codec/byte refusal cannot discard either previously verified credential.
    let rejected = services.workExchangeOutcome(token)
    assert rejected.kind == WorkJobResultKind.GuaranteeCollectionFailure
    assert rejected.guaranteeCollectionError.error == WorkGuaranteeError.CodecFailure
  accept(services, token, 1, keyC, responseC)
  assert services.workExchangeInfo(token).credentials == 3
  let collected = services.beginWorkGuaranteeCollection(token, ByteLimit(20000))
  assert collected.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.workExchangeInfo(token).guaranteeBytes == 0
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Guaranteed
  let bytes = services.workGuaranteePayload(token)
  verifyPayload(bytes, 3)
  distributions(services, token, bytes)
  unsignedReceiver(settings, bytes)
  var copy = bytes
  copy[0] = copy[0] xor 1
  assert services.workGuaranteePayload(token) == bytes
  let readLimits = AvailabilityReadLimits(computation: AvailabilityMerkleLimits(bytes: ByteLimit(
      64000000),
    hashBytes: ByteLimit(16000000), hashes: ElementLimit(10000)), wireBytes: ByteLimit(16000000))
  assert services.configureAvailabilityReads(readLimits)
  let info = services.workSubmissionReportInfo(token)
  let bundleRead = decodeReadRequest(ReadKind.Bundle, info.header.erasureRoot.bytes).value
  let reading = services.beginNetworkRead(bundleRead)
  assert reading.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.workGuaranteePayload(token) == bytes # The raw cache has no reference to the foreign reader's graph.
  let reply = services.collectStateProof(reading.value)
  assert reply.kind == ProofWorkerCompletionKind.ReadCompleted and reply.readValue.error == ReadError.None
  assert reply.readValue.value.bytes == frame(request.bundleMessage)
  assert services.retireWorkSubmission(token)
  assert services.workExchangeInfo(token).credentials == 0
  for stage in 0..<3:
    # Each new phase can be cancelled after Done without installing its prepared/accepted/encoded result.
    let cancelled = session(services, fixture, raw, header)
    if stage == 0:
      assert services.beginWorkExchange(cancelled, ByteLimit(20000)).error ==
          StateProofAdmissionError.None
    else:
      prepared(services, cancelled)
      if stage == 1:
        assert services.beginWorkPeerResponse(cancelled, 0, keyB, responseB).error ==
            StateProofAdmissionError.None
      else:
        accept(services, cancelled, 0, keyB, responseB)
        assert services.beginWorkGuaranteeCollection(cancelled, ByteLimit(20000)).error ==
            StateProofAdmissionError.None
    services.waitDone()
    assert services.retireWorkSubmission(cancelled)
    assert not services.stateProofAvailable
    assert services.collectWorkSubmission(cancelled) == WorkSessionPhase.Retired
    assert services.reapWorkSubmission()
    assert services.workExchangeInfo(cancelled).credentials == 0
  let foreign = session(services, fixture, raw, header)
  prepared(services, foreign)
  let foreignRead = services.beginNetworkRead(bundleRead)
  assert foreignRead.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.retireWorkSubmission(foreign)
  assert not services.reapWorkSubmission()
  assert services.collectStateProof(foreignRead.value).kind ==
      ProofWorkerCompletionKind.ReadCompleted
  assert services.reapWorkSubmission()
  let closing = session(services, fixture, raw, header)
  prepared(services, closing)
  assert services.beginWorkPeerResponse(closing, 0, keyB, responseB).error ==
      StateProofAdmissionError.None
  services.close() # Joined shutdown owns all private round/input aliases before any enclosing fixture owner retires.
  assert services.workSessionPhase(closing) == WorkSessionPhase.Empty
  assert services.workExchangeInfo(closing).credentials == 0
proc run(worker: var StateProofWorker, input: var WorkSubmissionJob,
    cancelDone = false): WorkJobResult =
  ## Only synchronized scalar polling occurs while any prepared/round/signer alias belongs to the fixed-address CPU.
  let admitted = worker.submit(input)
  assert admitted.error == ProofWorkerError.None and not input.valid
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    discard pauseMicros(100)
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized
  var extra = default(WorkSubmissionJob)
  assert worker.submit(extra).error == ProofWorkerError.Busy
  if cancelDone: assert worker.cancel(admitted.value)
  let completed = worker.collect(admitted.value)
  if cancelDone:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled
    return default(WorkJobResult)
  assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted
  completed.workSubmissionValue
proc cycle(worker: var StateProofWorker, local: SignedWorkContribution, targetB,
    targetC: WorkShareTarget, keyB, keyC: StateEdKey, responseB, responseC: array[96, byte], mode: int) =
  ## Real managed factories release successful, rejected, threshold-failed and Done-cancelled owners in every terminal path.
  var round = default(WorkGuaranteeRound)
  block:
    var input = captureWorkExchange(local, ByteLimit(20000)).value
    let completed = run(worker, input, cancelDone = mode == 1)
    if mode == 1: return
    assert completed.kind == WorkJobResultKind.ExchangePrepared
    round = completed.exchangeRound
  block:
    var input = captureWorkResponse(round, targetB, keyB, responseB).value
    let completed = run(worker, input, cancelDone = mode == 2)
    if mode != 2:
      assert completed.kind == WorkJobResultKind.PeerAccepted
      round = completed.exchangeRound
  if mode == 2:
    var input = captureWorkGuarantee(round, ByteLimit(20000)).value
    let completed = run(worker, input)
    assert completed.kind == WorkJobResultKind.GuaranteeCollectionFailure
    assert completed.guaranteeCollectionError.error == WorkGuaranteeError.InsufficientCredentials
    return
  block:
    var bad = responseC
    bad[32] = bad[32] xor 1
    var input = captureWorkResponse(round, targetC, keyC, bad).value
    let completed = run(worker, input)
    assert completed.kind == WorkJobResultKind.PeerResponseFailure
  block:
    var input = captureWorkResponse(round, targetC, keyC, responseC).value
    let completed = run(worker, input)
    assert completed.kind == WorkJobResultKind.PeerAccepted
    round = completed.exchangeRound
  block:
    var input = captureWorkGuarantee(round, ByteLimit(20000)).value
    let completed = run(worker, input)
    assert completed.kind == WorkJobResultKind.GuaranteeCollected
proc distributionCycle(worker: var StateProofWorker, bytes: seq[byte], view: ChainView, mode: int) =
  ## Native raw input may retire immediately after capture; every selected canonical/result alias remains untouched until matching collection.
  var payload = bytes
  if mode == 1: payload[payload.high] = payload[payload.high] xor 1
  var request = decodeReadRequest(ReadKind.Guarantee, payload).value
  var input = captureWorkDistribution(request, view, StateTime(21), distributionPolicy()).value
  let admitted = worker.submit(input)
  assert admitted.error == ProofWorkerError.None and not input.valid
  request = default(ReadRequest) # Retire native-side bytes while the independent input is queued/running/Done, before any collection.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    discard pauseMicros(100)
  if mode == 2: assert worker.cancel(admitted.value)
  let collected = worker.collect(admitted.value)
  if mode == 2:
    assert collected.kind == ProofWorkerCompletionKind.Cancelled
    return
  assert collected.kind == ProofWorkerCompletionKind.WorkSubmitted
  let completed = collected.workSubmissionValue
  if mode == 1:
    assert completed.kind == WorkJobResultKind.DistributionFailure
    assert completed.distributionError.error == WorkDistributionError.CredentialFailure
  else:
    assert completed.kind == WorkJobResultKind.DistributionQualified
    assert completed.qualifiedDistribution.distributionInfo.value.targets == 12
    assert completed.distributionReport.valid and completed.distributionReport.kind ==
        ReadKind.Report
proc distributionWorkers(local: SignedWorkContribution, b: WorkShareTarget, keyB: StateEdKey,
    responseB: array[96, byte], view: ChainView) {.raises.} =
  ## A genuine two-credential guarantee drives repeated managed qualification, refusal and Done cancellation without retaining prior graphs.
  let round = addWorkResponse(beginWorkGuarantee(local).value, b, keyB, responseB).value
  let bytes = collectWorkGuarantee(round, ByteLimit(20000)).value.guaranteePayload.value
  var worker = default(StateProofWorker)
  defer: worker.close()
  assert worker.start()
  for mode in 0..<3: distributionCycle(worker, bytes, view, mode)
  let before = getOccupiedMem()
  for iteration in 0..<1000: distributionCycle(worker, bytes, view, iteration mod 3)
  let after = getOccupiedMem()
  assert before == after
proc main() {.raises.} =
  ## Real independent fixture keys and sources remain untouched through every exact worker lease and joined close.
  let a = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")).value
  let b = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B")).value
  var diagnostic = ""
  assert ensureIdentity("managed-exchange-c", diagnostic)
  let c = loadWorkSigner("managed-exchange-c/cert.pem", "managed-exchange-c/key.pem").value
  let keyB = b.signerIdentity.value
  let keyC = c.signerIdentity.value
  let fixture = guaranteeFixture(a.signerIdentity.value, keyB, keyC)
  managed(fixture, b, c)
  let qualified = fixture.qualify(guaranteeLimits()).value
  let local = a.signWorkContribution(qualified, guarantorLimits()).value
  let request = prepareWorkSharing(local, ByteLimit(20000)).value
  let raw = workFixture()
  let responseB = receiveSharedWork(request, fixture.view, keyB, fixture.local, StateTime(21), b,
      policy(raw)).value.sharingResponse.value
  let responseC = receiveSharedWork(request, fixture.view, keyC, fixture.local, StateTime(21), c,
      policy(raw)).value.sharingResponse.value
  let targetB = sharingTarget(local, 1).value
  let targetC = sharingTarget(local, 2).value
  assert captureWorkExchange(default(SignedWorkContribution), ByteLimit(20000)).error ==
      WorkJobError.InvalidInput
  assert captureWorkGuarantee(default(WorkGuaranteeRound), ByteLimit(20000)).error ==
      WorkJobError.InvalidInput
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash)
  assert parent.error == GenesisError.None
  distributionWorkers(local, targetB, keyB, responseB, genesisView(parent))
  var worker = default(StateProofWorker)
  defer: worker.close()
  assert worker.start()
  for mode in 0..<3: cycle(worker, local, targetB, targetC, keyB, keyC, responseB, responseC, mode)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker, local, targetB, targetC, keyB, keyC, responseB, responseC, iteration mod 3)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_managed_work_exchange", 1000, before, after)
  echo "JAMNP-S managed work exchange passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Fixture/setup exceptions cannot replace actual managed credential collection and lease-lifetime verdicts.
