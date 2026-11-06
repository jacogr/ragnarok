# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_report_retrieval_arc_release"}

## Canonical CE136 framing and complete hash-bound report ownership over real authenticated TLS and Services leases.
import std/[assertions, syncio, envvars, strutils, monotimes, times]
import ../../../src/app/[node as application_node, services, options]
import ../../../src/app/proof/worker
import ../../../src/chain/[genesis, provider, parameters, reports]
import ../../../src/codec/[bounded, header, composite]
import ../../../src/codec/work/report as report_codec
import ../../../src/codec/state/[safrole, layout, trie]
import ../../../src/state/store
import ../../../src/jamnp-s/[read_stream, read_client, read_validation, canonical_read,
    node as node_streams, connections]
import ../../../src/crypto/primitives
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
proc requestFor(hash: WorkReportHash): ReadRequest =
  ## Complete fixed query bytes remain distinct from state/block identities.
  decodeReadRequest(ReadKind.Report, array[32, byte](hash)).value
proc framed(body: seq[byte]): seq[byte] =
  ## One independently framed E4 message contains bare report bytes only.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(body.len) shr (8*index)) and 255))
  for octet in body: result.add(octet)
proc bytes(report: OwnedReport): seq[byte] =
  ## Mutable extraction copies cannot change the report's private immutable wire owner.
  result = newSeq[byte](ownedReportInfo(report).value.consumed)
  assert encodeOwnedReport(report, result).error == OwnershipError.None
proc cycle(request: ReadRequest, wire: seq[byte], source: ReadSource) =
  ## Every complete verification activation retires all report/result owners before ARC observation.
  let checked = verifyReadReply(request, wire, source, readVerificationLimits())
  assert checked.error == ReadVerificationError.None
  assert ownedReportInfo(checked.value.workReport).value.consumed == 393
proc pump(host: var ApplicationNode, services: var Services, probe: var NodeProbe,
    milliseconds: int) {.raises.} =
  ## Host polling owns CPU admission outside callbacks; Services keeps exact graph/RPC gates.
  let deadline = getMonoTime()+initDuration(milliseconds = milliseconds)
  while getMonoTime() < deadline:
    assert host.poll(getMonoTime(), StateTime(7), 0)
    probe.poll()
    services.tick(uint32(host.peerCount))
proc live(saved: BlockSnapshotResult, body: seq[byte]) {.raises.} =
  ## Both C10 and C14 canonical sources are exercised through actual application/native ownership.
  writeFile("report-retrieval-chain.json", chainText(saved.value))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state",
    "--chain", "report-retrieval-chain.json"], options)
  var services = default(Services)
  var host = default(ApplicationNode)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    host.close()
    services.close()
  assert services.start(options, "report retrieval")
  let hash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(hash) == ViewFinalizeError.None
  let selectedAlpn = services.nodeProtocol
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      selectedAlpn, streams = 512)
  assert host.open(services, config, topologyLimits(), StateTime(7)) == NodeError.None
  probe.open(host.localPort, selectedAlpn)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline
    pump(host, services, probe, 1)
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0)
  discard probe.issue(hello, persistent = true)
  while host.peerCount == 0 or host.source(host.peerAt(0).value).error != NodeError.None:
    assert getMonoTime() < deadline
    pump(host, services, probe, 1)
  let request = requestFor(reportIdentity())
  var wire = @[136'u8, 32, 0, 0, 0]
  for octet in array[32, byte](reportIdentity()): wire.add(octet)
  let inbound = probe.issue(wire, persistent = true)
  pump(host, services, probe, 20)
  assert probe.bytes(inbound).len == 0 and not services.stateProofActive, "report request awaits its exact FIN"
  probe.enable(inbound, finish = true)
  while not probe.flows[inbound].receivedFin:
    assert getMonoTime() < deadline
    pump(host, services, probe, 1)
  assert not probe.flows[inbound].reset and probe.bytes(inbound) == framed(body)
  pump(host, services, probe, 20) # Retire the completed physical slot before filling both peer read reservations.
  var unknown = @[136'u8, 32, 0, 0, 0]
  for index in 0..<32: unknown.add(0)
  let absent = probe.issue(unknown)
  while not services.stateProofActive:
    assert getMonoTime() < deadline
    assert host.poll(getMonoTime(), StateTime(7), 0)
    probe.poll()
    services.tick(uint32(host.peerCount))
  let healthy = probe.issue(wire) # The first stream has left selector admission and owns an exact worker lease.

  while not probe.flows[healthy].receivedFin or not probe.flows[absent].reset:
    assert getMonoTime() < deadline
    pump(host, services, probe, 1)
  assert not probe.flows[absent].receivedFin and probe.bytes(healthy) == framed(body)
  pump(host, services, probe, 20) # Closing sibling reservations remain charged until actual native retirement.
  probe.expectRead(wire, framed(body))
  let checked = host.requestChecked(host.peerAt(0).value, request, readVerificationLimits())
  assert checked.error == NodeError.None
  while host.checkedPhase(checked.value) != CheckedRequestPhase.Done:
    assert getMonoTime() < deadline
    pump(host, services, probe, 1)
  let completed = host.takeChecked(checked.value)
  assert completed.kind == CheckedCompletionKind.Completed and completed.value.error ==
      ReadVerificationError.None
  assert completed.value.value.kind == ReadKind.Report
  assert bytes(completed.value.value.workReport) == body
  assert not services.stateProofActive
  pump(host, services, probe, 20)
  var corrupted: seq[byte] = @[]
  for octet in body: corrupted.add(octet)
  corrupted[0] = corrupted[0] xor 1
  probe.expectRead(wire, framed(corrupted))
  let invalid = host.requestChecked(host.peerAt(0).value, request, readVerificationLimits())
  assert invalid.error == NodeError.None
  while host.checkedPhase(invalid.value) != CheckedRequestPhase.Done:
    assert getMonoTime() < deadline
    pump(host, services, probe, 1)
  let refused = host.takeChecked(invalid.value)
  assert refused.kind == CheckedCompletionKind.Completed
  assert refused.value.error == ReadVerificationError.HashMismatch
  assert not services.stateProofActive, "complete framing cannot bypass full report hash checks or retain the worker lease"
  let foreign = services.beginNetworkRead(request)
  assert foreign.error == StateProofAdmissionError.None
  host.close()
  assert services.stateProofActive, "closing idle network ownership cannot release a foreign report worker lease"
  services.stopStateProofs()
  assert not services.stateProofActive
  assert bytes(completed.value.value.workReport) == body, "complete report evidence survives joined host/worker retirement"
proc main() {.raises.} =
  ## Exact source, wire and owner checks precede both independently authenticated runtime exchanges.
  let body = reportBody()
  let available = reportAvailability(body)
  let ready = reportReady(body)
  let first = reportSnapshot([available])
  let second = reportSnapshot([ready])
  assert first.error == GenesisError.None and second.error == GenesisError.None
  let request = requestFor(reportIdentity())
  let source = captureReadSource(first).value
  let wire = framed(body)
  assert serveCanonicalRead(genesisView(first), request).value.bytes == wire
  assert serveCanonicalRead(genesisView(second), request).value.bytes == wire
  let missing = requestFor(default(WorkReportHash))
  assert serveCanonicalRead(genesisView(first), missing).error == ReadError.Unavailable
  let corruptState = StateEntry(key: chapterKey(StateChapter(10)), value: @[2'u8])
  assert serveCanonicalRead(genesisView(reportSnapshot([corruptState, ready])), request).error ==
      ReadError.BackendFailure,
    "a valid ready report cannot mask malformed canonical availability"
  var badReady = ready
  badReady.value.add(0)
  assert serveCanonicalRead(genesisView(reportSnapshot([badReady])), request).error ==
      ReadError.BackendFailure
  let tooLarge = StateEntry(key: chapterKey(StateChapter(10)), value: newSeq[byte](1048577))
  assert serveCanonicalRead(genesisView(reportSnapshot([tooLarge])), request).error ==
      ReadError.LimitExceeded
  let noSource = default(ReadSource)
  assert verifyReadReply(request, wire, noSource, readVerificationLimits()).error ==
      ReadVerificationError.NoSource
  var narrow = readVerificationLimits()
  narrow.wireBytes = ByteLimit(uint64(wire.len-1))
  assert verifyReadReply(request, wire, source, narrow).error == ReadVerificationError.LimitExceeded
  var report = report_codec.decodeReportBorrowed(body, 4).value
  report.core = report_codec.CoreIndex(4)
  var foreignCore = newSeq[byte](body.len+16)
  let encoded = report_codec.encodeReportBorrowed(report, body, 341, foreignCore)
  assert encoded.error == CompositeError.None
  foreignCore.setLen(encoded.written)
  let foreignHash = blake2b256(foreignCore).value
  let wrongProfile = verifyReadReply(requestFor(WorkReportHash(array[32, byte](foreignHash))),
      framed(foreignCore), source, readVerificationLimits())
  assert wrongProfile.error == ReadVerificationError.ReportFailure,
    "a valid report hash cannot widen the independently selected core profile"
  assert wrongProfile.reportError != OwnershipError.None
  let checked = verifyReadReply(request, wire, source, readVerificationLimits())
  assert checked.error == ReadVerificationError.None and checked.value.kind == ReadKind.Report
  assert bytes(checked.value.workReport) == body
  var copied = bytes(checked.value.workReport)
  copied[0] = copied[0] xor 1
  assert bytes(checked.value.workReport) == body
  assert verifyReadReply(missing, wire, source, readVerificationLimits()).error ==
      ReadVerificationError.HashMismatch
  for size in 0..<body.len:
    var prefix = newSeq[byte](size)
    for index in 0..<size: prefix[index] = body[index]
    let hashed = blake2b256(prefix)
    assert hashed.error == CryptoError.None
    let matching = requestFor(WorkReportHash(array[32, byte](hashed.value)))
    assert verifyReadReply(matching, framed(prefix), source, readVerificationLimits()).error !=
        ReadVerificationError.None,
      "matching content hashes never authorize an incomplete report prefix"
  var suffix: seq[byte] = @[]
  for octet in body: suffix.add(octet)
  suffix.add(0)
  let suffixedHash = blake2b256(suffix).value
  assert verifyReadReply(requestFor(WorkReportHash(array[32, byte](suffixedHash))), framed(suffix),
      source, readVerificationLimits()).error == ReadVerificationError.InvalidFormat
  cycle(request, wire, source)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(request, wire, source)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_report_retrieval", 1000, before, after)
  live(first, body)
  live(second, body)
  echo "jamnp report retrieval: canonical sources and complete hash-bound TLS reports passed"
try: main()
except: quit 2 # Setup exceptions cannot replace successful protocol/ownership evidence.
