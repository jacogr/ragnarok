# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real TLS CE141 scheduled delivery is driven by ordinary application polling and genuine retained shard proofs; foreign leases and omitted clocks grant no signing or send authority.
import std/[assertions, monotimes, times, dirs, paths, posix/posix]
import ../../src/app/[services, options, node as application_node, assurance_broadcast, assurance_distribution]
import ../../src/app/proof/[worker, assurance_storage, assurance_acquisition]
import ../../src/jamnp-s/[node as node_streams, connections, assurance_schedule, assurance_duty,
  assurance_record, assurance_store, assurance_possession,
  assurance_distribution as distribution_rules,
  assurance_fetch, availability_proof, work_signer, topology]
import ../../src/codec/[bounded, assurances]
import ../../src/codec/state/[safrole, consensus]
import ../../src/codec/work/report
import ../../src/chain/[genesis, provider, parameters]
import ../../src/crypto/primitives
import ../../src/quic/address
import ./[jamnp_assurance_fixture, jamnp_topology_fixture, assurance_signer_context]
proc waitBroadcastJob(owner: var Services) =
  ## Synchronized phase polling touches no leased source/archive/private graph.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded assurance setup worker"
proc keyFor(marker: byte): StateEdKey =
  ## Only known test-owned private seeds identify potential real canonical author certificates.
  var seed = default(array[32, byte])
  seed[0] = marker
  StateEdKey(array[32, byte](importSeed(seed).value.publicKey.value))
proc assuranceBroadcastRuntime*(settings: Options, fixture: AssuranceAcquisitionFixture,
    suffix: string, acquisition: AssuranceAcquisitionLimits,
    storage: AssuranceStoreLimits) {.raises.} =
  ## Independent full-state Services own sender and receiving author; setup never fabricates canonical pending reports or peer identities.
  let folder = "assurance-broadcast-" & suffix
  try: removeDir(path(folder))
  except: assert false, "broadcast initial cleanup"
  defer:
    try: removeDir(path(folder))
    except: assert false, "broadcast joined cleanup"
  var sender = default(Services)
  var receiver = default(Services)
  defer:
    receiver.close()
    sender.close()
  assert sender.start(settings, "native assurance sender") and receiver.start(settings,
    "native assurance author"), "independent complete state"
  let geometry = topologyLimits(3, int(uint64(fixture.source.value.epochSlots)))
  let period = fixture.source.value.chainParameters.get(slotPeriodSec)
  let epoch = uint64(fixture.source.value.epochSlots)
  let slot = uint64(fixture.source.value.slot)
  let target = max(slot+1, slot div epoch*epoch+(6+period-1) div period)
  let prepare = AssuranceTime(target*period-min(4'u64, period))
  let window = assuranceWindow(prepare, period).value
  let planning = AssuranceScheduleLimits(duty: acquisition.duty, topology: geometry,
    plannedBytes: ByteLimit(1000000))
  let planned = captureAssuranceSchedule(fixture.source, fixture.local, window, planning).value
  var marker = 0'u8
  for ordinal in 0..<planned.scheduleInfo.value.authors:
    let key = planned.scheduleTarget(ordinal).value.identity
    if array[32, byte](key) != array[32, byte](fixture.local):
      for candidate in 11'u8..19'u8:
        if array[32, byte](key) == array[32, byte](keyFor(candidate)): marker = candidate
  assert marker != 0, "independent genuine eligible author seed"
  var senderKey = "broadcast-sender-key-" & suffix & ".pem"
  var senderCert = "broadcast-sender-cert-" & suffix & ".pem"
  var receiverKey = "broadcast-author-key-" & suffix & ".pem"
  var receiverCert = "broadcast-author-cert-" & suffix & ".pem"
  assuranceSignerFiles(senderKey, senderCert, 12)
  assuranceSignerFiles(receiverKey, receiverCert, marker)
  defer:
    discard posix.unlink(senderKey.toCString())
    discard posix.unlink(senderCert.toCString())
    discard posix.unlink(receiverKey.toCString())
    discard posix.unlink(receiverCert.toCString())
  assert sender.publishFinalized(sender.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None, "broadcast boundary 74"
  assert receiver.publishFinalized(receiver.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None, "broadcast boundary 76"
  var a = default(ApplicationNode)
  var b = default(ApplicationNode)
  defer:
    b.close()
    a.close() # Both exact native/worker borrowers retire before Services and test-owned paths.
  let now = StateTime(uint32(target-1))
  assert a.open(sender, initConnectionConfig(senderCert, senderKey, sender.nodeProtocol,
    streams = 512), geometry, now) == NodeError.None, "broadcast boundary 84"
  assert b.open(receiver, initConnectionConfig(receiverCert, receiverKey, receiver.nodeProtocol,
    streams = 512), geometry, now) == NodeError.None, "broadcast boundary 86"
  let signing = AssurancePossessionLimits(duty: acquisition.duty, shards: ElementLimit(1023),
    hashes: ElementLimit(1000000), ioBytes: ByteLimit(256000000), hashBytes: ByteLimit(256000000),
    workspaceBytes: ByteLimit(128000000))
  let policy = assuranceBroadcastPolicy(planning, signing, period, ElementLimit(1023),
    ElementLimit(0), ByteLimit(147312), parallel = 4)
  assert policy.valid and not default(AssuranceBroadcastPolicy).valid, "explicit policy: period=" &
      $period & " planning=" & $planning.valid & " signing=" & $signing.valid
  assert not a.configureAssuranceBroadcast(policy), "archive and private signer never implicitly created"
  let opening = sender.beginAssuranceStorage(folder, storage, AssuranceStorageMode.Create).value
  sender.waitBroadcastJob()
  assert sender.collectStateProof(opening).assuranceStorageValue.error == AssuranceStoreError.None, "broadcast boundary 97"
  assert not a.configureAssuranceBroadcast(policy), "installed archive alone grants no signing authority"
  assert sender.configureAssuranceSigner(senderCert, senderKey, fixture.local).error ==
      WorkSigningSetupError.None, "broadcast boundary 99"
  let duty = captureAssuranceDuty(fixture.source, fixture.local, acquisition.duty).value
  for ordinal in 0..<duty.dutyInfo.value.localIndices:
    let request = duty.shardRequest(CoreIndex(0), ordinal).value
    let transfer = prepareAvailabilityTransfer(fixture.availability, request,
        acquisition.verification).value
    var wire: seq[byte] = @[]
    for payload in [transfer.bundleShard, transfer.segmentShards, transfer.justification]:
      for byteIndex in 0..<4: wire.add(byte((uint32(payload.len) shr (8*byteIndex)) and 255))
      for octet in payload: wire.add(octet) # Independent literal E4 framing preserves original erasure provenance.
    let admitted = sender.beginAssuranceAcquisition(fixture.local, CoreIndex(0), ordinal, wire,
      prepare, acquisition).value
    sender.waitBroadcastJob()
    assert sender.collectStateProof(admitted).assuranceAcquisitionValue.error ==
        AssuranceAcquisitionError.None, "broadcast boundary 113"
  assert a.configureAssuranceBroadcast(policy) and not a.configureAssuranceBroadcast(policy), "explicit once-only outgoing activation"
  assert b.configureAssuranceReceipt(assuranceReceiptPolicy(AssuranceDistributionLimits(
    duty: acquisition.duty, wireBytes: ByteLimit(139)), 8, 9)), "independent bounded author receipt"
  assert b.beginPeerConnection(fixture.local, networkEndpoint(loopbackAddress(false),
      a.localPort)).error == DialError.None, "broadcast boundary 118"
  let deadline = getMonoTime()+initDuration(seconds = 15)
  while a.peerCount == 0 or b.peerCount == 0:
    assert getMonoTime() < deadline, "broadcast native handshake"
    assert a.poll(getMonoTime(), now, 0) and b.poll(getMonoTime(), now, 0), "broadcast boundary 123"
  for turn in 0..<10:
    assert a.poll(getMonoTime(), now, 0), "slot-only caller cannot start scheduled private work"
  assert a.assuranceBroadcastPhase == AssuranceBroadcastPhase.Idle and sender.stateProofAvailable, "broadcast boundary 126"
  let foreign = sender.beginAssurancePlanning(fixture.local, AssuranceFetchLimits(
    duty: acquisition.duty, plannedBytes: ByteLimit(1000000))).value
  sender.waitBroadcastJob()
  for turn in 0..<10:
    assert a.poll(getMonoTime(), now, prepare, 0), "foreign completed lease remains exclusive"
  assert sender.stateProofActive(foreign) and a.assuranceBroadcastPhase ==
      AssuranceBroadcastPhase.Idle, "broadcast boundary 132"
  discard sender.collectStateProof(foreign)
  while a.assuranceBroadcastPhase != AssuranceBroadcastPhase.Waiting:
    assert getMonoTime() < deadline, "bounded actual plan/private signing: " &
        $a.assuranceBroadcastPhase
    assert a.poll(getMonoTime(), now, prepare, 0) and b.poll(getMonoTime(), now, 0), "broadcast boundary 138"
  if uint64(prepare) < uint64(window.sendAt):
    for turn in 0..<10:
      assert a.poll(getMonoTime(), now, prepare, 0) and b.poll(getMonoTime(), now, 0), "broadcast boundary 141"
    assert a.attemptedAssuranceBroadcasts == 0, "private preparation never transmits before due time"
  while a.acknowledgedAssuranceBroadcasts == 0 or b.receivedAssurances == 0:
    assert getMonoTime() < deadline, "actual CE141 signature/receipt/both FINs: " &
        $a.assuranceBroadcastPhase
    assert a.poll(getMonoTime(), now, window.sendAt, 0) and b.poll(getMonoTime(), now, 0), "broadcast boundary 146"
  assert a.attemptedAssuranceBroadcasts == 1 and a.acknowledgedAssuranceBroadcasts == 1,
    "duplicate author positions produce one upload to the actual connected identity"
  assert b.pendingAssurances > 0, "actual retained author candidate"
  let candidate = b.pendingAssurance(0)
  assert candidate.bits.bytes[0] == 1,
    "managed recipient verifies only the genuinely retained core-zero assurance"
  assert not receiver.assuranceSigningConfigured and not receiver.assuranceStorageInfo.opened,
    "author receipt imports neither archive nor private signer"
  while a.assuranceBroadcastPhase != AssuranceBroadcastPhase.Idle:
    assert getMonoTime() < deadline, "bounded exact outgoing retirement"
    assert a.poll(getMonoTime(), now, window.sendAt, 0) and b.poll(getMonoTime(), now, 0), "broadcast boundary 157"
  assert a.peerCount == 1 and b.peerCount == 1, "round retirement preserves pre-existing transport"
  a.close()
  assert sender.stateProofAvailable, "outgoing teardown retires its own exact worker"
  assert a.open(sender, initConnectionConfig(senderCert, senderKey, sender.nodeProtocol,
    streams = 512), geometry, now) == NodeError.None, "reopened native sender"
  assert a.configureAssuranceBroadcast(policy), "reopened controller needs explicit policy"
  let closing = sender.beginAssurancePlanning(fixture.local, AssuranceFetchLimits(
    duty: acquisition.duty, plannedBytes: ByteLimit(1000000))).value
  sender.waitBroadcastJob()
  a.close()
  assert sender.stateProofActive(closing), "inactive broadcaster teardown preserves foreign Done lease"
  discard sender.collectStateProof(closing)
  assert a.open(sender, initConnectionConfig(senderCert, senderKey, sender.nodeProtocol,
    streams = 512), geometry, now) == NodeError.None, "broadcast boundary 170"
  assert a.configureAssuranceBroadcast(policy), "broadcast boundary 172"
  assert a.poll(getMonoTime(), now, prepare, 0), "admit exact owned planning job"
  assert a.assuranceBroadcastPhase == AssuranceBroadcastPhase.Planning, "broadcast boundary 174"
  sender.waitBroadcastJob()
  let attempts = a.attemptedAssuranceBroadcasts
  assert a.poll(getMonoTime(), StateTime(uint32(target)), window.closeAt, 0), "expiry cancels owned Done plan"
  assert sender.stateProofAvailable and a.assuranceBroadcastPhase == AssuranceBroadcastPhase.Idle,
    "expired plan is collected without signing or a partial send"
  assert a.attemptedAssuranceBroadcasts == attempts, "broadcast boundary 180"
