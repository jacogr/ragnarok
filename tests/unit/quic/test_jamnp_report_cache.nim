# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_report_cache_arc_release"}

## Checked reports remain bounded and independently serviceable during foreign canonical graph leases.

import std/[assertions, syncio, envvars, strutils, monotimes, times]
import ../../../src/app/[node as application_node, services, options]
import ../../../src/app/proof/worker
import ../../../src/chain/[genesis, provider, parameters, reports]
import ../../../src/codec/[header, bounded, composite]
import ../../../src/codec/work/report as report_codec
import ../../../src/codec/state/safrole
import ../../../src/state/store
import ../../../src/crypto/primitives
import ../../../src/jamnp-s/[node as node_streams, connections, read_stream, read_validation,
    canonical_read, report_cache]
import ../../../src/lib/json/writer as json_writer
import ../../support/[jamnp_report_fixture, jamnp_topology_fixture, jamnp_node_probe,
    jamnp_read_validation_context, arc_evidence]

proc hex(input: openArray[byte]): string =
  ## Independent canonical chainspec encoding does not use a production configuration serializer.
  result = ""
  for octet in input: result.add(toHex(int(octet), 2).toLowerAscii())

proc chainText(saved: BlockSnapshot): string =
  ## Retain the complete fixture's original opaque chapters and exact header/profile.
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(saved.header, wire).error == HeaderError.None
  var entries = JsonObject()
  for index in 0..<saved.keyCount:
    let key = saved.keyAt(StateKeyIndex(index))
    entries.add(hex(array[31, byte](key)), json(hex(saved.lookup(key).value.bytes)))
  $jsonObject([("protocol_parameters", json(hex(topologySettings().encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(entries))])

proc frame(body: seq[byte]): seq[byte] =
  ## Independent one-message E4 framing excludes any guarantee wrapper.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(body.len) shr (8*index)) and 255))
  for octet in body: result.add(octet)

proc reportRequest(hash: WorkReportHash): ReadRequest =
  ## Exact32-byte content identity is separate from source block/state identities.
  decodeReadRequest(ReadKind.Report, array[32, byte](hash)).value

proc wireRequest(request: ReadRequest): seq[byte] =
  ## Every report request uses the pinned selector and fixed E4 extent.
  result = @[136'u8, 32, 0, 0, 0]
  for octet in request.payload: result.add(octet)

proc checked(body: seq[byte], source: ReadSource): CheckedReadReply =
  ## Only the actual full-hash/profile verifier creates the opaque cache input type.
  let hash = blake2b256(body).value
  let request = reportRequest(WorkReportHash(array[32, byte](hash)))
  let verified = verifyReadReply(request, frame(body), source, readVerificationLimits())
  assert verified.error == ReadVerificationError.None
  verified.value

proc variant(body: seq[byte], id: int, large = false): seq[byte] =
  ## Different complete reports retain valid encoding; large authorization traces exercise byte rather than count capacity.
  var report = report_codec.decodeReportBorrowed(body, 4).value
  report.header.packageHash.bytes[0] = byte(id)
  var pool: seq[byte] = @[]
  for octet in body: pool.add(octet)
  if large:
    report.authOutput = BlobSpan(offset: pool.len, length: 48000)
    for index in 0..<48000: pool.add(0)
  result = newSeq[byte](pool.len+1024)
  let encoded = report_codec.encodeReportBorrowed(report, pool, 4, result)
  assert encoded.error == CompositeError.None
  result.setLen(encoded.written)

proc cycle(report: CheckedReadReply) =
  ## One isolated cache activation retires all copied wire owners before ARC sampling.
  var cache = default(ReportCache)
  assert cache.remember(report) == ReportCacheError.None
  assert cache.find(report.request).error == ReportCacheError.None
  cache.clear()
  assert cache.len == 0 and cache.byteLength == 0

proc pure(body: seq[byte], source: ReadSource) =
  ## Both independent capacities and replacement recency are observable through actual report lookups.
  var cache = default(ReportCache)
  let empty = default(CheckedReadReply)
  assert cache.remember(empty) == ReportCacheError.InvalidReport
  var reports: seq[CheckedReadReply] = @[]
  for index in 0..<MaxCachedReports+1: reports.add(checked(variant(body, index), source))
  for index in 0..<MaxCachedReports: assert cache.remember(reports[index]) == ReportCacheError.None
  let bytes = cache.byteLength
  assert cache.remember(reports[0]) == ReportCacheError.None and cache.byteLength == bytes
  assert cache.find(reports[0].request).error == ReportCacheError.None
  assert cache.remember(reports[MaxCachedReports]) == ReportCacheError.None
  assert cache.len == MaxCachedReports and cache.byteLength == bytes
  assert cache.find(reports[1].request).error == ReportCacheError.Missing
  let retained = cache.find(reports[0].request)
  assert retained.error == ReportCacheError.None
  var copied = retained.value.bytes
  copied[4] = copied[4] xor 1
  assert cache.find(reports[0].request).value.bytes == retained.value.bytes
  cache.clear()
  for index in 0..<50:
    let large = checked(variant(body, index, true), source)
    assert cache.remember(large) == ReportCacheError.None
    assert cache.len <= MaxCachedReports and cache.byteLength <= MaxReportCacheBytes
  assert cache.len < MaxCachedReports, "the retained-byte bound evicts before count capacity is exhausted"
  assert cache.find(reports[0].request).error == ReportCacheError.Missing
  cache.clear()

proc poll(host: var ApplicationNode, services: var Services, probe: var NodeProbe) {.raises.} =
  ## One host turn performs no canonical graph inspection in this test while a foreign worker owns its lease.
  assert host.poll(getMonoTime(), StateTime(7), 0)
  probe.poll()
  services.tick(uint32(host.peerCount))

proc connect(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    protocol: string, hash: genesis.BlockHash) {.raises.} =
  ## Ready means both authenticated transport and admitted host-side UP0, not first response bytes alone.
  probe.open(host.localPort, protocol)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0)
  discard probe.issue(hello, persistent = true)
  while host.peerCount == 0 or host.source(host.peerAt(0).value).error != NodeError.None:
    assert getMonoTime() < deadline
    poll(host, services, probe)

proc claim(saved: BlockSnapshotResult, body: seq[byte]) {.raises.} =
  ## Deferral revokes the old serial before re-admission and cannot reset a route already responding.
  var service = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    service.close()
  let view = genesisView(saved).finalizeView(saved.value.blockHash).value
  let selectedAlpn = "jamnp-s/1/00000000"
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert service.open(config, view, topologyLimits()) == NodeError.None
  probe.open(service.localPort, selectedAlpn)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    assert service.poll(getMonoTime(), 0)
    probe.poll()
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](saved.value.blockHash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0)
  discard probe.issue(hello, persistent = true)
  while service.peerCount == 0 or service.source(service.peerAt(0).value).error != NodeError.None:
    assert getMonoTime() < deadline
    assert service.poll(getMonoTime(), 0)
    probe.poll()
  let request = reportRequest(reportIdentity())
  let reading = probe.issue(wireRequest(request))
  var task = service.takeRead(ReadKind.Report)
  while task.error != NodeError.None:
    assert getMonoTime() < deadline
    assert service.poll(getMonoTime(), 0)
    probe.poll()
    task = service.takeRead(ReadKind.Report)
  assert service.readLive(task.value.ticket)
  assert service.deferRead(task.value.ticket)
  assert not service.readLive(task.value.ticket)
  assert not service.deferRead(task.value.ticket)
  assert service.takeRead(ReadKind.State).error == NodeError.Unavailable
  let again = service.takeRead(ReadKind.Report)
  assert again.error == NodeError.None and service.readLive(again.value.ticket)
  let reply = captureReadReply(request, frame(body)).value
  assert service.respond(task.value.ticket, reply) == ReadError.InvalidStream
  assert service.respond(again.value.ticket, reply) == ReadError.None
  assert not service.deferRead(again.value.ticket)
  while not probe.flows[reading].receivedFin:
    assert getMonoTime() < deadline
    assert service.poll(getMonoTime(), 0)
    probe.poll()
  assert probe.bytes(reading) == frame(body) and not probe.flows[reading].reset

proc live(saved: BlockSnapshotResult, body: seq[byte]) {.raises.} =
  ## Fetched report retention serves peers even when canonical report lookup has no such content and its graph is leased.
  writeFile("report-cache-chain.json", chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "report-cache-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close()
  assert services.start(options, "report cache")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  connect(host, services, probe, selectedAlpn, hash)
  let request = reportRequest(reportIdentity())
  let wire = wireRequest(request)
  assert serveCanonicalRead(services.chainView, request).error == ReadError.Unavailable
  probe.expectRead(wire, frame(body))
  let fetch = host.requestChecked(host.peerAt(0).value, request, readVerificationLimits())
  assert fetch.error == NodeError.None
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while host.checkedPhase(fetch.value) != CheckedRequestPhase.Done:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert host.takeChecked(fetch.value).value.error == ReadVerificationError.None
  assert host.cachedReportCount == 1 and host.cachedReportBytes == frame(body).len
  let foreign = services.beginNetworkRead(readStateRequest(hash))
  assert foreign.error == StateProofAdmissionError.None
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
    probe.poll()
  let reading = probe.issue(wire)
  while not probe.flows[reading].receivedFin:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert probe.bytes(reading) == frame(body) and not probe.flows[reading].reset
  assert services.stateProofActive and services.stateProofPhase == ProofWorkerPhase.Done
  let drain = getMonoTime()+initDuration(milliseconds = 20)
  while getMonoTime() < drain: poll(host, services, probe)
  let unknown = reportRequest(default(WorkReportHash))
  let missing = probe.issue(wireRequest(unknown))
  let selectFirst = getMonoTime()+initDuration(milliseconds = 20)
  while getMonoTime() < selectFirst: poll(host, services, probe)
  let sibling = probe.issue(wire)
  while not probe.flows[sibling].receivedFin:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert probe.bytes(sibling) == frame(body)
  assert not probe.flows[missing].receivedFin and not probe.flows[missing].reset
  assert services.stateProofActive, "cached service and a deferred miss cannot collect a foreign Done lease"
  let base = getMonoTime()
  assert host.poll(base+initDuration(seconds = 29), StateTime(7), 0)
  for iteration in 0..<100:
    assert host.poll(base+initDuration(seconds = 31, milliseconds = iteration), StateTime(7), 0)
    probe.poll()
    if probe.flows[missing].reset: break
  assert probe.flows[missing].reset and not probe.flows[missing].receivedFin,
    "cache probes at29s cannot extend an original30s native inactivity deadline"
  assert services.stateProofActive
  host.close()
  assert services.stateProofActive and host.cachedReportCount == 0 and host.cachedReportBytes == 0
  assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
  probe.close()
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  connect(host, services, probe, selectedAlpn, hash)
  let fresh = probe.issue(wire)
  while not probe.flows[fresh].reset:
    assert getMonoTime() < deadline
    poll(host, services, probe)
  assert not probe.flows[fresh].receivedFin and host.cachedReportCount == 0

proc main() {.raises.} =
  ## Pool math, claim ownership and actual graph-excluded service each have independent runtime witnesses.
  let body = reportBody()
  let saved = reportSnapshot([])
  let source = captureReadSource(saved).value
  pure(body, source)
  let report = checked(body, source)
  cycle(report)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(report)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_report_cache", 1000, before, after)
  claim(saved, body)
  live(saved, body)
  echo "jamnp report cache: bounded content and detached TLS service passed"
try: main()
except: quit 2 # Native/setup exceptions cannot stand in for exact cache/lease protocol evidence.
