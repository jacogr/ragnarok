# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared real TLS header and Services authorization/refinement/report setup keeps managed signing/exchange tests on the same production path.
import std/[assertions, monotimes, times]
import ../../src/app/services
import ../../src/app/proof/worker
import ../../src/jamnp-s/[node, connections, work_stream, work_duty, read_stream]
import ../../src/codec/state/safrole
import ./[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  pvm_input_refinement, jamnp_topology_fixture, jamnp_node_probe]
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield between synchronized scalar observations without inspecting a worker-owned graph.
proc waitDone*(services: var Services) =
  ## Done retains the exact canonical/private-key lease; no result alias is inspected before matching collection.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "managed signing deadline"
    discard pauseMicros(1000)
proc frame*(bytes: openArray[byte]): seq[byte] =
  ## Independent literal E4 framing feeds the real native header parser rather than constructing its private owner.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(bytes.len) shr (index*8)) and 255))
  for octet in bytes: result.add(octet)
proc networkHeader*(services: var Services, fixture: GuaranteeFixture, raw: WorkFixture,
    cert, key: string): UntrustedWorkHeader {.raises.} =
  ## Actual authenticated builder TLS and the bounded native CE146 reader produce detached source-free bytes.
  var server = default(NodeService)
  var probe = default(NodeProbe)
  defer:
    probe.close()
    server.close()
  let protocol = services.nodeProtocol
  let config = initConnectionConfig(cert, key, protocol, streams = 512)
  assert server.open(config, services.chainView, topologyLimits(2)) == NodeError.None
  assert server.enableWorkStreams()
  assert array[32, byte](server.localIdentity) == array[32, byte](fixture.local)
  probe.open(server.localPort, protocol & "/builder")
  var deadline = getMonoTime()+initDuration(seconds = 8)
  while not probe.authenticated or server.peerCount == 0:
    assert getMonoTime() < deadline, "signing builder TLS admission"
    assert server.poll(getMonoTime(), 0)
    probe.poll()
  var packet = @[146'u8]
  for octet in frame(raw.first): packet.add(octet)
  for octet in frame(fixture.package): packet.add(octet)
  discard probe.issue(packet, persistent = true)
  deadline = getMonoTime()+initDuration(seconds = 8)
  while true:
    let task = server.takeWorkHeader()
    if task.error == NodeError.None: return task.value.header
    assert getMonoTime() < deadline, "signing native header admission"
    assert server.poll(getMonoTime(), 0)
    probe.poll()
proc reportSession*(services: var Services, fixture: GuaranteeFixture,
    raw: WorkFixture, header: UntrustedWorkHeader): WorkSessionToken {.raises.} =
  ## Real Services captures its own canonical map, authenticates the body, refines and computes the exact report.
  let admitted = services.beginWorkSubmission(header, raw.limits, executionLimits(),
    workRecipient(fixture.local, StateTime(20)), guaranteeLimits().duty)
  assert admitted.error == StateProofAdmissionError.None, "signing session admission"
  let token = admitted.value
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Authorized
  let body = services.beginWorkBundle(token, raw.extrinsics, raw.segments, raw.proofs)
  assert body.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Complete
  let report = services.beginWorkReport(token, workReportLimits(), StateTime(20))
  assert report.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.ReportReady
  token
