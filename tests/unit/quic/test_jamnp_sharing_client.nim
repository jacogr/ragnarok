# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_sharing_client_arc_release"}

## Actual TLS framing and six simultaneous three-node CE134 directions retain independent quotas, exact peer tickets and genuine signatures.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/jamnp-s/[node, connections, sharing_client, sharing_wire, work_sharing,
  work_guarantee, work_signer, work_eligibility, read_stream, network]
import ../../../src/app/startup
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/bounded
import ../../../src/codec/state/safrole
import ../../support/[jamnp_read_client_exchange, jamnp_guarantee_fixture, jamnp_topology_fixture, arc_evidence]
proc frame(bytes: openArray[byte]): seq[byte] =
  ## Independent literal E4 framing is intentionally separate from the production request serializer.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(bytes.len) shr (8*index)) and 255))
  for octet in bytes: result.add(octet)
proc packet(first, body: seq[byte]): seq[byte] =
  ## CE134 has exactly two E4 messages before request FIN.
  result = @[134'u8]
  for octet in frame(first): result.add(octet)
  for octet in frame(body): result.add(octet)
proc framing() {.raises.} =
  ## Every truncated response extent, wrong prefix, suffix, quota and withheld FIN uses the existing independent TLS harness.
  var route = default(SharingClientRoute)
  assert route.configureSharing(default(SharedWorkRequest)) == ReadError.InvalidRequest
  assert route.take().error == ReadError.Unavailable
  let first = @[0'u8, 0, 6, 0, 0]
  let body = @[11'u8, 12, 13]
  let request = captureSharedWork(first, body).value
  let expected = packet(first, body)
  var payload = newSeq[byte](96)
  for index in 0..<96: payload[index] = byte(index+1)
  let response = frame(payload)
  exchangeSharingClient(request, expected, response, holdFin = true)
  for length in 0..<response.len:
    var prefix = newSeq[byte](length)
    for index in 0..<length: prefix[index] = response[index]
    exchangeSharingClient(request, expected, prefix, failure = ReadError.InvalidRequest)
  for length in [0'u8, 95, 97, 255]:
    var wrong = response
    wrong[0] = length
    exchangeSharingClient(request, expected, wrong, failure = ReadError.InvalidRequest)
  var highPrefix = response
  highPrefix[3] = 128
  exchangeSharingClient(request, expected, highPrefix, failure = ReadError.InvalidRequest)
  var suffix = response
  suffix.add(0)
  exchangeSharingClient(request, expected, suffix, failure = ReadError.InvalidRequest)
  exchangeSharingClient(request, expected, response, budget = 99, failure = ReadError.LimitExceeded)
  exchangeSharingClient(request, expected, response, budget = 0, failure = ReadError.LimitExceeded)
  let largeBody = newSeq[byte](262144)
  let large = captureSharedWork(first, largeBody).value
  exchangeSharingClient(large, packet(first, largeBody), response, holdFin = true)
  assert route.configureSharing(request) == ReadError.None
  assert route.configureSharing(request) == ReadError.Busy
proc pump(a, b, c: var NodeService, milliseconds = 1) =
  ## Native owners contain only raw framing; canonical/signing aliases never enter their callbacks.
  let deadline = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < deadline:
    assert a.poll(getMonoTime(), 0) and b.poll(getMonoTime(), 0) and c.poll(getMonoTime(), 0)
proc startPair(owner: var NodeService, peers: array[2, NodePeer], request: SharedWorkRequest,
    tickets: var array[2, NodeSharingRequestTicket], started: var array[2, bool]) =
  ## UP0/open-intent backpressure spends no extra sharing reservation; each actual success is recorded once.
  for index in 0..<2:
    if started[index]: continue
    let admitted = owner.requestSharing(peers[index], request)
    if admitted.error == NodeError.Unavailable: continue
    assert admitted.error == NodeError.None
    tickets[index] = admitted.value
    started[index] = true
func complete(flags: array[2, bool]): bool =
  ## Two independent directions must both reach their exact milestone.
  flags[0] and flags[1]
proc takeIncoming(owner: var NodeService, tasks: var array[2, NodeSharingTask], count: var int) =
  ## Complete exact-FIN requests remain claimed while every node's two outgoing slots are still occupied.
  while count < 2:
    let taken = owner.takeSharingRequest()
    if taken.error == NodeError.Unavailable: break
    assert taken.error == NodeError.None
    tasks[count] = taken.value
    inc count
proc answer(owner: var NodeService, tasks: array[2, NodeSharingTask], request: SharedWorkRequest,
    response: array[96, byte]) =
  ## Only byte-identical original bundles receive the independently computed genuine recipient signature.
  for task in tasks:
    assert task.request.firstMessage == request.firstMessage
    assert task.request.bundleMessage == request.bundleMessage
    assert owner.respondSharing(task.ticket, response) == ReadError.None
proc takeResponses(owner: var NodeService, tickets: array[2, NodeSharingRequestTicket],
    replies: var array[2, UntrustedSharingReply], received: var array[2, bool]) =
  ## Exact host collection works even after native close; foreign or already consumed tickets expose no prefix.
  for index in 0..<2:
    if received[index]: continue
    let taken = owner.takeSharingReply(tickets[index])
    if taken.error == ReadError.Unavailable: continue
    assert taken.error == ReadError.None
    replies[index] = taken.value
    received[index] = true
    assert not owner.sharingRequestLive(tickets[index])
proc assembled(local: SignedWorkContribution, positions: array[2, int],
    tickets: array[2, NodeSharingRequestTicket], replies: array[2, UntrustedSharingReply]) =
  ## Actual reservation TLS identities, sealed source targets and genuine fixed responses produce a three-credential guarantee.
  var round = beginWorkGuarantee(local).value
  for index in 0..<2:
    let target = sharingTarget(local, positions[index])
    assert target.error == WorkGuaranteeError.None
    let accepted = addWorkResponse(round, target.value, tickets[index].peerIdentity, replies[index].bytes)
    assert accepted.error == WorkGuaranteeError.None
    round = accepted.value
  assert round.credentialCount == 3
  let collected = collectWorkGuarantee(round, ByteLimit(20000))
  assert collected.error == WorkGuaranteeError.None
proc signed(fixture: GuaranteeFixture, signer: WorkSigner): SignedWorkContribution =
  ## Genuine source-qualified computation precedes all native callbacks; no packet selects a private signing message.
  let key = signer.signerIdentity.value
  let qualified = qualifyWorkGuarantee(fixture.transcript, fixture.original, fixture.execution,
    fixture.view, key, StateTime(21), guaranteeLimits())
  assert qualified.error == WorkEligibilityError.None
  let contributed = signer.signWorkContribution(qualified.value)
  assert contributed.error == WorkSignerError.None
  contributed.value
proc simultaneous() {.raises.} =
  ## All three real authenticated nodes reserve two outgoing and two incoming routes at the same time, then verify one another's replies.
  let signerA = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")).value
  let signerB = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B")).value
  var diagnostic = ""
  assert ensureIdentity("sharing-client-c", diagnostic)
  let signerC = loadWorkSigner("sharing-client-c/cert.pem", "sharing-client-c/key.pem").value
  let keyA = signerA.signerIdentity.value
  let keyB = signerB.signerIdentity.value
  let keyC = signerC.signerIdentity.value
  let fixture = guaranteeFixture(keyA, keyB, keyC)
  let localA = signed(fixture, signerA)
  let localB = signed(fixture, signerB)
  let localC = signed(fixture, signerC)
  let request = prepareWorkSharing(localA, ByteLimit(20000)).value
  let responseA = localA.sharingResponse.value
  let responseB = localB.sharingResponse.value
  let responseC = localC.sharingResponse.value
  let head = fixture.view.bestBlock.value.blockHash
  let view = fixture.view.finalizeView(head).value
  var a, b, c = default(NodeService)
  defer:
    c.close()
    b.close()
    a.close()
  let configA = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      "jamnp-s/1/00000000", streams = 512)
  let configB = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"),
      "jamnp-s/1/00000000", streams = 512)
  let configC = initConnectionConfig("sharing-client-c/cert.pem", "sharing-client-c/key.pem",
      "jamnp-s/1/00000000", streams = 512)
  assert a.open(configA, view, topologyLimits(2)) == NodeError.None
  assert b.open(configB, view, topologyLimits(2)) == NodeError.None
  assert c.open(configC, view, topologyLimits(2)) == NodeError.None
  assert b.enableSharingStreams() and c.enableSharingStreams()
  assert a.beginPeerConnection(keyB, networkEndpoint(loopbackAddress(false), b.localPort)).error == DialError.None
  assert a.beginPeerConnection(keyC, networkEndpoint(loopbackAddress(false), c.localPort)).error == DialError.None
  assert b.beginPeerConnection(keyC, networkEndpoint(loopbackAddress(false), c.localPort)).error == DialError.None
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while a.peerCount < 2 or b.peerCount < 2 or c.peerCount < 2:
    assert getMonoTime() < deadline
    pump(a, b, c)
  let peersA = [a.peerForIdentity(keyB).value, a.peerForIdentity(keyC).value]
  let peersB = [b.peerForIdentity(keyA).value, b.peerForIdentity(keyC).value]
  let peersC = [c.peerForIdentity(keyA).value, c.peerForIdentity(keyB).value]
  let disabled = a.requestSharing(peersA[0], request)
  assert disabled.error == NodeError.Unavailable # A connected actual validator still needs explicit sharing activation.
  assert a.enableSharingStreams()
  let invalid = a.requestSharing(peersA[0], default(SharedWorkRequest))
  assert invalid.error == NodeError.InvalidConfig
  var cancelled = default(NodeResult[NodeSharingRequestTicket])
  while true:
    cancelled = a.requestSharing(peersA[0], request)
    if cancelled.error == NodeError.None: break
    assert cancelled.error == NodeError.Unavailable and getMonoTime() < deadline
    pump(a, b, c)
  assert a.sharingRequestCount == 1
  assert a.cancelSharingRequest(cancelled.value)
  assert a.sharingRequestCount == 0 and not a.sharingRequestLive(cancelled.value)
  assert not a.cancelSharingRequest(cancelled.value)
  var ticketsA, ticketsB, ticketsC = default(array[2, NodeSharingRequestTicket])
  var startedA, startedB, startedC = default(array[2, bool])
  while not (complete(startedA) and complete(startedB) and complete(startedC)):
    assert getMonoTime() < deadline
    startPair(a, peersA, request, ticketsA, startedA)
    startPair(b, peersB, request, ticketsB, startedB)
    startPair(c, peersC, request, ticketsC, startedC)
    pump(a, b, c)
  assert a.sharingRequestCount == 2 and b.sharingRequestCount == 2 and c.sharingRequestCount == 2
  let excess = a.requestSharing(peersA[0], request)
  assert excess.error == NodeError.LimitExceeded
  assert not b.cancelSharingRequest(ticketsA[0])
  let foreign = b.takeSharingReply(ticketsA[0])
  assert foreign.error == ReadError.InvalidStream
  var tasksA, tasksB, tasksC = default(array[2, NodeSharingTask])
  var countA, countB, countC = 0
  while countA < 2 or countB < 2 or countC < 2:
    assert getMonoTime() < deadline
    takeIncoming(a, tasksA, countA)
    takeIncoming(b, tasksB, countB)
    takeIncoming(c, tasksC, countC)
    pump(a, b, c)
  assert a.workStreamCount == 2 and b.workStreamCount == 2 and c.workStreamCount == 2
  answer(a, tasksA, request, responseA)
  answer(b, tasksB, request, responseB)
  answer(c, tasksC, request, responseC)
  pump(a, b, c, 60) # Native retirement may precede collection without losing complete fixed replies.
  var repliesA, repliesB, repliesC = default(array[2, UntrustedSharingReply])
  var receivedA, receivedB, receivedC = default(array[2, bool])
  while not (complete(receivedA) and complete(receivedB) and complete(receivedC)):
    assert getMonoTime() < deadline
    takeResponses(a, ticketsA, repliesA, receivedA)
    takeResponses(b, ticketsB, repliesB, receivedB)
    takeResponses(c, ticketsC, repliesC, receivedC)
    pump(a, b, c)
  assembled(localA, [1, 2], ticketsA, repliesA)
  assembled(localB, [0, 2], ticketsB, repliesB)
  assembled(localC, [0, 1], ticketsC, repliesC)
  while a.sharingRequestCount+b.sharingRequestCount+c.sharingRequestCount+a.workStreamCount+b.workStreamCount+c.workStreamCount > 0:
    assert getMonoTime() < deadline
    pump(a, b, c)
  assert a.takeSharingReply(ticketsA[0]).error == ReadError.InvalidStream
  assert b.takeSharingRequest().error == NodeError.Unavailable
  # Active cancellation revokes both exact directions without disconnecting the authenticated peer.
  let active = a.requestSharing(peersA[0], request)
  assert active.error == NodeError.None
  var pending = default(NodeResult[NodeSharingTask])
  while true:
    pending = b.takeSharingRequest()
    if pending.error == NodeError.None: break
    assert pending.error == NodeError.Unavailable and getMonoTime() < deadline
    pump(a, b, c)
  assert a.cancelSharingRequest(active.value)
  assert not a.sharingRequestLive(active.value)
  while a.sharingRequestCount != 0 or b.sharingLive(pending.value.ticket):
    assert getMonoTime() < deadline
    pump(a, b, c)
  assert b.respondSharing(pending.value.ticket, responseB) == ReadError.InvalidStream
  assert a.peerForIdentity(keyB).error == NodeError.None
  # A complete uncollected response survives the queued-open deadline, then expires at the ordinary read lifetime.
  let expiring = a.requestSharing(peersA[0], request)
  assert expiring.error == NodeError.None
  var finalTask = default(NodeResult[NodeSharingTask])
  while true:
    finalTask = b.takeSharingRequest()
    if finalTask.error == NodeError.None: break
    assert finalTask.error == NodeError.Unavailable and getMonoTime() < deadline
    pump(a, b, c)
  assert b.respondSharing(finalTask.value.ticket, responseB) == ReadError.None
  pump(a, b, c, 60)
  let current = getMonoTime()
  for sweep in 0..<16:
    assert a.poll(current+initDuration(seconds = 6, milliseconds = sweep), 0)
  assert a.sharingRequestLive(expiring.value)
  for sweep in 0..<16:
    assert a.poll(current+initDuration(seconds = 121, milliseconds = sweep), 0)
  assert not a.sharingRequestLive(expiring.value) and a.sharingRequestCount == 0
  assert a.peerForIdentity(keyB).error == NodeError.None
proc cycle(request: SharedWorkRequest) =
  ## Independent native-free output snapshots release full request storage without a fake successful reply.
  var route = default(SharingClientRoute)
  assert route.configureSharing(request) == ReadError.None
  assert route.take().error == ReadError.Unavailable
proc main() {.raises.} =
  ## Real callback lifetimes retire before allocator evidence, including complete, malformed and cancelled client paths.
  framing()
  simultaneous()
  let request = captureSharedWork([0'u8, 0, 6, 0, 0], newSeq[byte](262144)).value
  cycle(request)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(request)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_sharing_client", 1000, before, after)
  echo "JAMNP-S native sharing client passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Fixture/transport exceptions cannot stand in for actual framing and authenticated response verdicts.
