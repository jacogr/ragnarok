# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An ordinary authenticated host probes genuinely retained canonical coordinates through production CPU arbitration; absent clocks, foreign Done leases and exact shutdown cannot manufacture possession or steal work.

import std/[assertions, monotimes, times, dirs, paths, posix/posix]
import ../../src/app/[services, options, node as application_node, assurance_acquirer]
import ../../src/app/proof/[worker, assurance_storage, assurance_acquisition, network_read]
import ../../src/jamnp-s/[node as node_streams, connections, assurance_fetch, assurance_duty,
  assurance_record, assurance_store, availability_proof, availability_read, read_stream, endpoints]
import ../../src/crypto/primitives
import ../../src/quic/address
import ../../src/codec/[bounded, assurances]
import ../../src/codec/work/report
import ../../src/codec/state/[safrole, consensus]
import ../../src/chain/[genesis, provider]
import ./[jamnp_assurance_fixture, jamnp_topology_fixture, assurance_signer_context]

proc waitDone(owner: var Services) =
  ## Poll only synchronized worker state while all canonical and archive graphs remain leased.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "acquirer managed completion deadline"

proc assuranceAcquirerRuntime*(settings: Options, fixture: AssuranceAcquisitionFixture,
    certificate, privateKey, folder: string, acquisition: AssuranceAcquisitionLimits,
    storage: AssuranceStoreLimits) {.raises.} =
  ## Services independently decodes the explicit complete trusted seed; this witness proves host integration rather than network bootstrap or implicit archive activation.
  try: removeDir(path(folder))
  except: assert false, "acquirer initial cleanup"
  defer:
    try: removeDir(path(folder))
    except: assert false, "acquirer joined cleanup"
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "canonical assurance acquirer"), "independent acquirer source"
  let finalized = services.publishFinalized(services.chainView.bestBlock.value.blockHash)
  assert finalized == ViewFinalizeError.None, "acquirer explicit trusted finality"
  var host = default(ApplicationNode)
  defer: host.close()
  let duty = captureAssuranceDuty(fixture.source, fixture.local, acquisition.duty).value
  let now = duty.dutyInfo.value.slot
  let geometry = topologyLimits(3, int(uint64(fixture.source.value.epochSlots)))
  assert host.open(services, initConnectionConfig(certificate, privateKey,
    services.nodeProtocol, streams = 512), geometry, now) == NodeError.None, "actual validator host"
  let planning = AssuranceFetchLimits(duty: acquisition.duty, plannedBytes: ByteLimit(1000000))
  let policy = assuranceAcquisitionPolicy(planning, acquisition, ElementLimit(3),
    ElementLimit(3), ByteLimit(48000000), peerTimeoutMs = 100, retryMs = 100)
  assert policy.valid, "explicit bounded acquisition policy"
  assert not host.configureAssuranceAcquisition(default(AssuranceAcquisitionPolicy)), "default acquisition disabled"
  assert not host.configureAssuranceAcquisition(policy), "archive never opens implicitly"
  let opening = services.beginAssuranceStorage(folder, storage, AssuranceStorageMode.Create).value
  services.waitDone()
  assert services.collectStateProof(opening).assuranceStorageValue.error ==
      AssuranceStoreError.None, "explicit installed archive"
  assert host.configureAssuranceAcquisition(policy), "optional acquisition activation"
  assert not host.configureAssuranceAcquisition(policy), "live controller cannot be reconfigured"
  for index in 0..<10:
    # Slot-only callers must not accidentally promise retention using a slot as a second count.
    assert host.poll(getMonoTime(), now, 0), "ordinary clock-free foreground progress"
  assert services.stateProofAvailable and host.attemptedAssuranceRequests == 0 and
    services.assuranceStorageInfo.records == 0, "no new acquisition without Common Era seconds"
  for ordinal in 0..<duty.dutyInfo.value.localIndices:
    # Each repeated original local validator position receives its own genuinely proven shard before the production actor probes it.
    let request = duty.shardRequest(CoreIndex(0), ordinal).value
    let transfer = prepareAvailabilityTransfer(fixture.availability, request,
      acquisition.verification).value
    var wire: seq[byte] = @[]
    for message in [transfer.bundleShard, transfer.segmentShards, transfer.justification]:
      # Independent literal E4 framing supplies real bundle, segment and justification payloads.
      for index in 0..<4: wire.add(byte((uint32(message.len) shr (8*index)) and 255))
      for octet in message: wire.add(octet)
    let started = services.beginAssuranceAcquisition(fixture.local, CoreIndex(0), ordinal,
      wire, AssuranceTime(1000), acquisition).value
    services.waitDone()
    assert services.collectStateProof(started).assuranceAcquisitionValue.error ==
      AssuranceAcquisitionError.None, "actual retained original coordinate"
  let foreign = services.beginAssurancePlanning(fixture.local, planning).value
  services.waitDone()
  for index in 0..<10:
    # Completed foreign jobs still own their lease and must not be collected or treated as stale canonical state.
    assert host.poll(getMonoTime(), now, AssuranceTime(9000), 0), "foreign Done host progress"
  assert services.stateProofActive(foreign) and not services.stateProofAvailable and
    host.assuranceAcquisitionPhase == AssuranceAcquirerPhase.Idle, "foreign exact Done lease preserved"
  discard services.collectStateProof(foreign)
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while host.probedAssuranceShards < uint64(duty.dutyInfo.value.localIndices):
    assert getMonoTime() < deadline, "all retained core-zero coordinates verified by production actor: " &
        $host.assuranceAcquisitionPhase & " worker " & $services.stateProofPhase
    let previous = host.assuranceAcquisitionPhase
    assert host.poll(getMonoTime(), now, AssuranceTime(9000), 0), "actual plan/probe arbitration"
    assert host.assuranceAcquisitionPhase != AssuranceAcquirerPhase.Backoff,
      "retained core-zero actor unexpectedly backed off after " & $previous
  assert host.attemptedAssuranceRequests == 0 and host.acquiredAssuranceShards == 0 and
    host.assuranceDemandConnections == 0, "existing durable proofs skip every network request and do not pretend to be new retention"
  assert services.assuranceStorageInfo.records == uint64(duty.dutyInfo.value.localIndices), "all original positions retained without eviction"
  host.close() # A subsequent core probe may already own the next lease; only the host may join it.
  assert services.stateProofAvailable and services.assuranceStorageInfo.opened,
    "owned acquisition teardown joins its next probe and preserves durable storage"
  for ordinal in 0..<duty.dutyInfo.value.localIndices:
    # A later observation time must not silently renew promises merely because existing files passed proof and durability checks.
    let probe = services.beginAssuranceProbe(fixture.local, CoreIndex(0), ordinal,
      AssuranceTime(9000), acquisition).value
    services.waitDone()
    let checked = services.collectStateProof(probe).assuranceAcquisitionValue
    assert checked.error == AssuranceAcquisitionError.None and
      uint64(checked.value.record.promisedAt) == 1000, "actor probe never renews stored promises"
  assert host.open(services, initConnectionConfig(certificate, privateKey,
    services.nodeProtocol, streams = 512), geometry, now) == NodeError.None, "reopen actual host after joined close"
  assert host.configureAssuranceAcquisition(policy), "reactivate explicitly after closed lifetime"
  let closing = services.beginAssurancePlanning(fixture.local, planning).value
  services.waitDone()
  host.close()
  assert services.stateProofActive(closing), "closing inactive acquirer preserves foreign Done ownership"
  discard services.collectStateProof(closing)
  assert services.stateProofAvailable and not services.assuranceSigningConfigured, "probe-only activation has no private signer"

proc fixtureIdentity(marker: byte): StateEdKey =
  ## Match only known test-owned seed material against actual canonical public roster records.
  var seed = default(array[32, byte])
  seed[0] = marker
  StateEdKey(array[32, byte](importSeed(seed).value.publicKey.value))

proc openGuarantor(owner: var NodeService, services: Services,
    certificate, privateKey: string, geometry: SafroleStateConfig): NodeError =
  ## Temporary complete-view aliases retire before either native worker can start.
  owner.open(initConnectionConfig(certificate, privateKey, services.nodeProtocol,
    streams = 512), services.chainView, geometry)

proc stagedAvailability(fixture: AssuranceAcquisitionFixture, request: ReadRequest,
    limits: AvailabilityReadLimits): NetworkReadJob =
  ## A closed production read job owns the real original erasure graph; no peer-provided root can select a substitute fixture.
  let captured = captureAvailabilityRead(fixture.availability, request, limits)
  assert captured.error == ReadError.None, "actual original guarantor source capture"
  captured.value

proc assuranceAcquirerNetworkRuntime*(settings: Options, fixture: AssuranceAcquisitionFixture,
    folder: string, acquisition: AssuranceAcquisitionLimits,
    storage: AssuranceStoreLimits) {.raises.} =
  ## Three real authenticated endpoints share one serialized closed read worker; canonical clients own an independently decoded complete source. First-target corrupt evidence must never reach durable possession.
  try: removeDir(path(folder))
  except: assert false, "network acquisition initial cleanup"
  defer:
    try: removeDir(path(folder))
    except: assert false, "network acquisition joined cleanup"
  let planning = AssuranceFetchLimits(duty: acquisition.duty, plannedBytes: ByteLimit(1000000))
  let original = captureAssuranceFetch(fixture.source, fixture.local, planning).value
  let targets = original.coreAt(0).value.targets
  assert targets >= 2 and targets <= 3, "genuine original guarantor quorum targets"
  var marker = 0'u8
  for candidate in 11'u8..19'u8:
    # Select an actual local parent-roster identity distinct from every target for this genuinely admitted pending core.
    let identity = fixtureIdentity(candidate)
    var remote = true
    for ordinal in 0..<targets:
      if array[32, byte](identity) == array[32, byte](original.targetAt(0,
        ordinal).value.validator.ed25519): remote = false
    if remote and captureAssuranceDuty(fixture.source, identity, acquisition.duty).error ==
        AssuranceDutyError.None:
      marker = candidate
      break
  assert marker != 0, "known real local seed outside original guarantor target set"
  var clientKey = folder & "-client-key.pem"
  var clientCert = folder & "-client-cert.pem"
  assuranceSignerFiles(clientKey, clientCert, marker)
  var keys = default(array[3, string])
  var certificates = default(array[3, string])
  defer:
    discard posix.unlink(clientKey.toCString())
    discard posix.unlink(clientCert.toCString())
    for ordinal in 0..<targets:
      discard posix.unlink(keys[ordinal].toCString())
      discard posix.unlink(certificates[ordinal].toCString())
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "TLS assurance acquisition"), "independent network client source"
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
    ViewFinalizeError.None, "explicit independent trusted finality"
  let geometry = topologyLimits(3, int(uint64(fixture.source.value.epochSlots)))
  let now = captureAssuranceDuty(fixture.source, fixtureIdentity(marker),
    acquisition.duty).value.dutyInfo.value.slot
  var servers = default(array[3, NodeService])
  defer:
    for ordinal in 0..<targets: servers[ordinal].close()
  for ordinal in 0..<targets:
    # Each exact canonical credential identity receives a genuine bundled-TLS certificate; no certificate-acceptance callback is substituted.
    var found = false
    for candidate in 11'u8..19'u8:
      if array[32, byte](fixtureIdentity(candidate)) == array[32, byte](
          original.targetAt(0, ordinal).value.validator.ed25519):
        keys[ordinal] = folder & "-server-" & $ordinal & "-key.pem"
        certificates[ordinal] = folder & "-server-" & $ordinal & "-cert.pem"
        assuranceSignerFiles(keys[ordinal], certificates[ordinal], candidate)
        found = true
        break
    assert found, "actual guarantor known test key"
    assert openGuarantor(servers[ordinal], services, certificates[ordinal], keys[ordinal],
      geometry) == NodeError.None, "actual canonical guarantor native endpoint"
  var worker = default(StateProofWorker)
  defer: worker.close() # Join the one original-availability reader before any alias, native context or certificate retires.
  assert worker.start(), "one bounded guarantor read worker"
  var host = default(ApplicationNode)
  defer: host.close()
  assert host.open(services, initConnectionConfig(clientCert, clientKey,
    services.nodeProtocol, streams = 512), geometry, now) == NodeError.None, "ordinary native acquiring application"
  for ordinal in 0..<targets:
    # Explicit pre-existing authenticated peers exercise canonical-key selection without changing the source's original routing metadata.
    assert host.beginPeerConnection(original.targetAt(0, ordinal).value.validator.ed25519,
      networkEndpoint(loopbackAddress(false), servers[ordinal].localPort)).error ==
      DialError.None, "test host owns pre-existing real guarantor connection"
  let connected = getMonoTime()+initDuration(seconds = 10)
  while host.peerCount < targets:
    assert getMonoTime() < connected, "real guarantor TLS handshakes"
    assert host.poll(getMonoTime(), now, 0), "clock-free client handshake progress"
    for ordinal in 0..<targets:
      assert servers[ordinal].poll(getMonoTime(), 0), "guarantor handshake progress"
  let opening = services.beginAssuranceStorage(folder, storage, AssuranceStorageMode.Create).value
  services.waitDone()
  assert services.collectStateProof(opening).assuranceStorageValue.error ==
      AssuranceStoreError.None, "explicit empty acquiring archive"
  let policy = assuranceAcquisitionPolicy(planning, acquisition, ElementLimit(1),
    ElementLimit(3), ByteLimit(16000000), peerTimeoutMs = 3000, retryMs = 100)
  assert host.configureAssuranceAcquisition(policy), "explicit network acquisition activation"
  let serving = AvailabilityReadLimits(computation: acquisition.verification,
    wireBytes: acquisition.wireBytes)
  var active = false
  var ticket = default(ProofWorkerTicket)
  var read = default(NodeReadTicket)
  var request = default(ReadRequest)
  var selected = 0
  var corrupted = false
  var backedOff = false
  var badServer = -1
  var good = 0
  let deadline = getMonoTime()+initDuration(seconds = 15)
  while host.acquiredAssuranceShards == 0:
    assert getMonoTime() < deadline, "corrupt-first real CE137 acquisition deadline"
    assert host.poll(getMonoTime(), now, AssuranceTime(1000), 0), "ordinary acquiring actor progress"
    if host.assuranceAcquisitionPhase == AssuranceAcquirerPhase.Backoff: backedOff = true
    for ordinal in 0..<targets:
      assert servers[ordinal].poll(getMonoTime(), 0), "actual guarantor stream progress"
    if active:
      # All aliases of the real original erasure graph stay untouched until this exact closed worker result retires.
      let completed = worker.collect(ticket)
      if completed.kind == ProofWorkerCompletionKind.Uninitialized: continue
      assert completed.kind == ProofWorkerCompletionKind.ReadCompleted and
        completed.readValue.error == ReadError.None, "real guarantor proof construction"
      var wire = completed.readValue.value.bytes
      if not corrupted:
        assert wire.len > 12, "nonempty genuine proof transcript"
        wire[wire.len-1] = wire[wire.len-1] xor 1
        badServer = selected
        corrupted = true # Framing remains valid; the client's actual Merkle verifier must refuse this data.
      else:
        assert badServer >= 0 and selected != badServer, "retry advances to a different original guarantor"
        assert array[32, byte](original.targetAt(0, selected).value.validator.ed25519) !=
          array[32, byte](original.targetAt(0, badServer).value.validator.ed25519),
          "different actual authenticated canonical guarantor identity"
        inc good
      let reply = captureReadReply(request, wire)
      assert reply.error == ReadError.None, "wire framing alone cannot grant Merkle authority"
      assert servers[selected].respond(read, reply.value) == ReadError.None, "actual server response and FIN"
      active = false
    if not active:
      for ordinal in 0..<targets:
        # Only one native reader ever touches original fixture ARC graphs, even when several authenticated servers are polled.
        let task = servers[ordinal].takeRead()
        if task.error != NodeError.None: continue
        if task.value.request.kind != ReadKind.Availability:
          discard servers[ordinal].reject(task.value.ticket)
          continue
        request = task.value.request
        read = task.value.ticket
        selected = ordinal
        var job = stagedAvailability(fixture, request, serving)
        let admitted = worker.submit(job)
        assert admitted.error == ProofWorkerError.None and not job.valid, "moved actual closed guarantor job"
        ticket = admitted.value
        active = true
        break
  assert corrupted and backedOff and good > 0 and host.attemptedAssuranceRequests == 2,
    "corrupt evidence rejected before another actual guarantor reply was durably acquired"
  assert services.assuranceStorageInfo.records == 1 and not services.assuranceStorageInfo.faulted,
    "only genuine proof-complete CE137 data acquired durable possession"
  assert host.assuranceDemandConnections == 0 and host.peerCount >= targets,
    "acquirer preserves independently owned pre-existing connections"
  host.close()
  assert services.stateProofAvailable and not services.assuranceSigningConfigured,
    "network acquisition alone grants no private signing authority"
