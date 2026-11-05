# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Three ordinary ApplicationNode loops drive CE146 through managed report/signing and independent CE134 receivers to canonical credential collection.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/[node as application_node, services, options, startup, work_dispatch, work_exchange]
import ../../../src/app/proof/worker
import ../../../src/jamnp-s/[node as node_streams, connections, endpoints, work_signer,
  work_sharing, work_duty, work_guarantee, sharing_wire, read_stream]
import ../../../src/quic/address
import ../../../src/codec/[bounded, guarantees, assurances]
import ../../../src/codec/work/package
import ../../../src/codec/state/safrole
import ../../../src/chain/[provider, genesis]
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  jamnp_managed_work_context, jamnp_read_validation_context, jamnp_topology_fixture,
  jamnp_node_probe, pvm_input_refinement]

type Variant {.pure.} = enum ## The same real builder source proves optional activation, three credentials, bounded third-peer grace and joined cancellation.
  Three, Two, Foreign, CloseDone, ReceiverClose, Refused
proc policy(raw: WorkFixture): WorkExchangePolicy =
  ## Every cryptographic/execution/copy ceiling is explicit; only peer response timing differs from the production default.
  let limits = WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes),
    bundleBytes: ByteLimit(MaxBundleBytes), submission: raw.limits, execution: executionLimits(),
    report: workReportLimits(), eligibility: guaranteeLimits())
  workExchangePolicy(limits, ByteLimit(20000))
proc start(services: var Services, host: var ApplicationNode, certificate,
    privateKey: string) {.raises.} =
  ## Each Services instance decodes independent complete canonical ownership before this host borrows its stable address.
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "work-exchange-chain.json"], settings)
  assert services.start(settings, "exchange runtime")
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  let config = initConnectionConfig(certificate, privateKey, services.nodeProtocol, streams = 512)
  assert host.open(services, config, topologyLimits(2), StateTime(20)) == NodeError.None
proc pump(a, b, c: var ApplicationNode, sa, sb, sc: var Services, probe: var NodeProbe,
    clock: MonoTime) {.raises.} =
  ## The production poll entry owns all admission and collection; the test never calls a worker stage or computes a remote response itself.
  assert a.poll(clock, StateTime(20), 0), "exchange origin poll"
  assert b.poll(clock, StateTime(20), 0), "exchange peer B poll"
  assert c.poll(clock, StateTime(20), 0), "exchange peer C poll"
  probe.poll()
  sa.tick(uint32(a.peerCount))
  sb.tick(uint32(b.peerCount))
  sc.tick(uint32(c.peerCount))
proc packet(fixture: GuaranteeFixture, raw: WorkFixture): seq[byte] =
  ## Literal two-header CE146 plus original bodies uses independent E4 bytes and the genuine anchored package.
  result = @[146'u8]
  for message in [raw.first, fixture.package, raw.extrinsics, raw.segments, raw.proofs]:
    for octet in frame(message): result.add(octet)
proc verify(bytes: seq[byte], count: int) =
  ## Decode the actual runtime output with the independent canonical GP codec and inspect original sorted validator positions.
  let decoded = decodeGuarantee(bytes, GuaranteeConfig(cores: CoreCount(2),
      validators: ValidatorCount(6), maxBytes: ByteLimit(20000)))
  assert decoded.error == GuaranteeError.None and decoded.value.consumed == bytes.len
  let value = decoded.value.value
  assert value.credentialCount == count and uint32(value.slot) == 20
  assert uint16(value.credentials[0].validator) == 1
  assert uint16(value.credentials[1].validator) == 2
  if count == 3: assert uint16(value.credentials[2].validator) == 5
proc scenario(variant: Variant, fixture: GuaranteeFixture, keyB, keyC: StateEdKey) {.raises.} =
  ## A fresh trio gives every case independent native sockets, worker namespaces and private signing owners.
  let raw = workFixture()
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash)
  assert parent.error == GenesisError.None
  writeFile("work-exchange-chain.json", workChainText(parent.value))
  var sa, sb, sc = default(Services)
  var a, b, c = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    a.close()
    b.close()
    c.close()
    sa.close()
    sb.close()
    sc.close()
  start(sa, a, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  start(sb, b, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  start(sc, c, "work-exchange-c/cert.pem", "work-exchange-c/key.pem")
  let sourceHash = sa.chainView.bestBlock.value.blockHash
  let selected = policy(raw)
  assert selected.valid
  assert not a.configureWorkExchange(default(WorkExchangePolicy), "missing", "missing")
  assert not sa.workSigningConfigured
  assert a.configureWork(workDispatchPolicy(raw.limits, executionLimits(), guaranteeLimits().duty))
  assert a.configureWorkExchange(selected, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  assert not a.configureWorkExchange(selected, "missing", "missing")
  if variant != Variant.Refused:
    assert b.configureWorkExchange(selected, getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  if variant notin [Variant.Two, Variant.Refused]:
    assert c.configureWorkExchange(selected, "work-exchange-c/cert.pem", "work-exchange-c/key.pem")
  assert a.beginPeerConnection(keyB, networkEndpoint(loopbackAddress(false), b.localPort)).error == DialError.None
  assert a.beginPeerConnection(keyC, networkEndpoint(loopbackAddress(false), c.localPort)).error == DialError.None
  probe.open(a.localPort, sa.nodeProtocol & "/builder", "work-exchange-builder/cert.pem", "work-exchange-builder/key.pem")
  let deadline = getMonoTime()+initDuration(seconds = 25)
  while not probe.authenticated or a.peerCount < 3:
    assert getMonoTime() < deadline, "runtime TLS setup"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  let flow = probe.issue(packet(fixture, raw))
  var held = default(ProofWorkerTicket)
  var foreignStarted = false
  var secondAt = default(MonoTime)
  var secondSeen = false
  var retried = false
  var previousPoll = getMonoTime()
  while a.workExchangePhase != WorkExchangePhase.Ready:
    assert getMonoTime() < deadline, "runtime exchange phase " & $a.workExchangePhase
    let clock = getMonoTime()
    if variant == Variant.Refused and a.workExchangePhase == WorkExchangePhase.Idle and
        a.workPhase == WorkDispatchPhase.Idle and a.acceptedWork > 0 and
        (not retried or a.acceptedWork == 2):
      assert sa.stateProofAvailable and not sa.rpc.chainPaused
      if retried:
        assert a.acceptedWork == 2
        return
      assert probe.flows[flow].receivedFin
      discard probe.issue(packet(fixture, raw))
      retried = true
    if variant == Variant.ReceiverClose and sb.stateProofActive:
      sb.waitDone()
      assert sb.rpc.chainPaused
      b.close()
      assert sb.stateProofAvailable
      let reopened = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT_B"), getEnv(
          "RAGNAROK_TEST_KEY_B"), sb.nodeProtocol, streams = 512)
      assert b.open(sb, reopened, topologyLimits(2), StateTime(20)) == NodeError.None
      assert b.configureWorkExchange(selected, "unused", "unused")
      assert b.workExchangePhase == WorkExchangePhase.Idle
      return
    if variant == Variant.CloseDone and a.workExchangePhase == WorkExchangePhase.Checking:
      let closedToken = a.completedWork
      sa.waitDone()
      assert sa.rpc.chainPaused
      a.close()
      assert sa.stateProofAvailable
      assert sa.workSessionPhase(closedToken) == WorkSessionPhase.Empty
      return
    if a.workPhase == WorkDispatchPhase.Ready:
      let token = a.completedWork
      let info = sa.workExchangeInfo(token)
      if info.credentials == 2 and not secondSeen:
        secondSeen = true
        secondAt = previousPoll # This is the host clock that collected the second credential and started its grace, before observation overhead.
      if variant == Variant.Foreign and not foreignStarted and a.workExchangePhase ==
          WorkExchangePhase.Exchanging and sa.stateProofAvailable:
        let job = sa.beginNetworkRead(readStateRequest(sourceHash))
        assert job.error == StateProofAdmissionError.None
        held = job.value
        foreignStarted = true
        sa.waitDone()
        let peersDone = getMonoTime()+initDuration(seconds = 8)
        while b.receivedWorkContributions == 0 or c.receivedWorkContributions == 0:
          # Both remote computations and native responses finish while this unrelated completed lease remains uncollected.
          assert getMonoTime() < peersDone, "sharing peers progress through foreign lease"
          pump(a, b, c, sa, sb, sc, probe, getMonoTime())
          assert sa.stateProofPhase == ProofWorkerPhase.Done and sa.rpc.chainPaused
        assert sa.workExchangeInfo(token).credentials == 1
        assert sa.collectStateProof(held).kind == ProofWorkerCompletionKind.ReadCompleted
    previousPoll = getMonoTime()
    pump(a, b, c, sa, sb, sc, probe, previousPoll)
  assert probe.flows[flow].receivedFin and not probe.flows[flow].reset
  assert a.collectedWorkGuarantees == 1 and b.receivedWorkContributions == 1
  let token = a.completedWork
  assert sa.workSessionPhase(token) == WorkSessionPhase.Guaranteed
  let count = if variant == Variant.Two: 2 else: 3
  verify(sa.workGuaranteePayload(token), count)
  if variant == Variant.Two:
    assert secondSeen and (getMonoTime()-secondAt).inMilliseconds >= 2000
    assert c.receivedWorkContributions == 0 and not sc.workSigningConfigured
  else:
    assert c.receivedWorkContributions == 1
  if variant == Variant.Foreign: assert foreignStarted
  assert a.releaseWork()
  while a.workExchangePhase != WorkExchangePhase.Idle:
    assert getMonoTime() < deadline, "runtime retirement"
    pump(a, b, c, sa, sb, sc, probe, getMonoTime())
  assert sa.workSessionPhase(token) == WorkSessionPhase.Empty
  a.close()
  let reopened = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      sa.nodeProtocol, streams = 512)
  assert a.open(sa, reopened, topologyLimits(2), StateTime(20)) == NodeError.None
  assert a.configureWorkExchange(selected, "unused", "unused")
  assert a.workExchangePhase == WorkExchangePhase.Idle
proc main() {.raises.} =
  ## Only public identity leaves the temporary signer scopes; private production setup subsequently imports its own independent owner from paths.
  var diagnostic = ""
  assert ensureIdentity("work-exchange-c", diagnostic)
  assert ensureIdentity("work-exchange-builder", diagnostic)
  var keyA, keyB, keyC = default(StateEdKey)
  block:
    let a = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")).value
    let b = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B")).value
    let c = loadWorkSigner("work-exchange-c/cert.pem", "work-exchange-c/key.pem").value
    keyA = a.signerIdentity.value
    keyB = b.signerIdentity.value
    keyC = c.signerIdentity.value
  let fixture = guaranteeFixture(keyA, keyB, keyC)
  for variant in Variant.Three..Variant.Refused:
    scenario(variant, fixture, keyB, keyC)
    echo "runtime ", variant, " passed"
  echo "jamnp work exchange runtime tests passed"
try:
  main()
except:
  quit 2 # Fixture/setup failures cannot substitute for actual peer execution and credential collection.
