# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent RPC and TLS processes observe confirmed current adoption before a later gated refusal.
import std/[assertions, syncio, envvars, monotimes, times, os, strutils, base64]
import std/posix/posix
import ../../../src/app/current/download/[command as current_download_command,
    policy as current_download_policy]
import ../../../src/app/[options, services]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, header]
import ../../../src/crypto/primitives
import ../../../src/state/store
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/report/admission as report_admission
import ../../../src/state/accumulation/current/consensus as accumulation_current_consensus
import ../../../src/storage/managed/manifest as managed_manifest
import ../../support/[accumulation_current_chain_context,
  current_download_command_context,
  current_application_context, current_services_disk_samples,
  managed_storage_samples,
  block_download_transport, rpc_socket]

const
  ChainPath = "pvm-current-download-rpc-chain.json"
  PolicyPath = "pvm-current-download-rpc-policy.conf"
  StartPath = "pvm-current-download-rpc-start"
  ReadyPath = "pvm-current-download-rpc-ready"
  DonePath = "pvm-current-download-rpc-done"
  StopPath = "pvm-current-download-rpc-stop"
  CountPath = "pvm-current-download-rpc-count"

proc waitFile(path: string) =
  ## Bound cross-process coordination without touching another process's canonical or native owner.
  let started = getMonoTime()
  while not fileExists(path):
    assert (getMonoTime() - started).inMilliseconds < 12000, "RPC synchronization file"
    yieldCurrentDiskThread()

proc request(rpc: var Server, peer: cint, pending: var string,
    text: string): string =
  ## Default local Server ticks do no IO; the real parent command pumps the remote listener independently.
  sendText(peer, text)
  readPacket(rpc, peer, pending, description = text)

proc observeRpc(context: CurrentChainFixture, port: uint16) {.raises.} =
  ## Subscribe before the first response; exact roots/headers and proof-method refusal must finish before response two is released.
  waitFile(StartPath)
  var rpc = default(Server)
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  upgrade(rpc, peer, pending)
  let binding = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
  let childWire = currentChainBytes(binding.admittedHeader)
  let digest = blake2b256(childWire)
  assert digest.error == CryptoError.None
  let hashes = [array[32, byte](context.parent.value.blockHash), array[32,
      byte](digest.value)]
  let roots = [array[32, byte](context.parent.value.stateRoot), array[32, byte](
      context.source.currentConsensusState.value.commitment.root)]
  let slots = [uint32(context.parent.value.slot), uint32(
      binding.admittedHeader.headerInfo.value.unsigned.slot)]
  let subscribed = request(rpc, peer, pending,
    """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":1}""")
  assert "\"result\":1" in subscribed
  for index in 0..1:
    let notification = readPacket(rpc, peer, pending,
        description = "best-block notification " & $index)
    assert base64.encode(hashes[index]) in notification
    assert "\"slot\":" & $slots[index] in notification
    if index == 0: writeFile(ReadyPath, "ready") # Only the actual original-parent notification releases the signed current child.
  let best = request(rpc, peer, pending, """{"jsonrpc":"2.0","method":"bestBlock","id":2}""")
  assert "\"id\":2" in best and base64.encode(hashes[1]) in best
  for index in 0..1:
    let hash = base64.encode(hashes[index])
    let root = request(rpc, peer, pending,
        "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" & hash &
        "\"],\"id\":" & $(10+index) & "}")
    assert "\"id\":" & $(10+index) in root and base64.encode(roots[index]) in root
    let wire = if index == 0: currentChainBytes(
        context.parent.value.header) else: childWire
    let sealed = request(rpc, peer, pending,
        "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_header\",\"params\":[\"" &
        hash & "\"],\"id\":" & $(20+index) & "}")
    assert "\"id\":" & $(20+index) in sealed and base64.encode(wire) in sealed
  let parent = request(rpc, peer, pending,
      "{\"jsonrpc\":\"2.0\",\"method\":\"parent\",\"params\":[\"" &
      base64.encode(hashes[1]) & "\"],\"id\":30}")
  assert "\"id\":30" in parent and base64.encode(hashes[0]) in parent
  let finality = request(rpc, peer, pending, """{"jsonrpc":"2.0","method":"finalizedBlock","id":40}""")
  assert "Finalized chain view unavailable" in finality
  let key = context.parent.value.stateSnapshot.keyAt(StateEntryIndex(0)).value
  let proof = request(rpc, peer, pending,
      "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_requestStateProof\",\"params\":[\"" &
      base64.encode(hashes[1]) & "\",[\"" & base64.encode(array[31, byte](
      key)) & "\"]],\"id\":41}")
  assert "\"id\":41" in proof and "-32601" in
      proof # Download orchestration deliberately admits no autonomous proof borrower.
  writeFile(DonePath, "done") # Ordered notifications and exact retained metadata completed against the actual command listener.

proc check(context: CurrentChainFixture, managed: bool) {.raises.} =
  ## Prepare genuine expected maps before forks, with no native worker or canonical lease alive across process creation.
  defer:
    for name in [ChainPath, PolicyPath, StartPath, ReadyPath, DonePath,
        StopPath, CountPath]:
      var path = name
      discard posix.unlink(path.toCString()) # All coordination files remain owned by this isolated native suite.
  writeFile(ChainPath, context.currentApplicationText)
  writeFile(PolicyPath, encodeCurrentDownloadPolicy(currentCommandLimits()))
  let reserved = reservation()
  discard posix.close(reserved.fd)
  let binding = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
  let digest = blake2b256(currentChainBytes(binding.admittedHeader))
  assert digest.error == CryptoError.None
  let requests = @[currentExpectedRequest(array[32, byte](
      context.parent.value.blockHash)), currentExpectedRequest(array[32, byte](digest.value))]
  let responses = @[context.currentResponseFrame, @[0'u8, 0, 0, 0]]
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses,
    @[Gated, Gated])
  let port = servers.port(true)
  let responder = posix.fork()
  assert int(responder) >= 0
  if int(responder) == 0:
    let started = getMonoTime()
    while not fileExists(StopPath) and (getMonoTime() -
        started).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3)
      let count = servers.requestCount(true)
      if count >= 1 and not fileExists(StartPath): writeFile(StartPath,
          "start") # TLS request receipt proves the RPC listener has already started.
      if count == 1 and fileExists(ReadyPath): servers.resumeResponses()
      if count == 2 and fileExists(DonePath): servers.resumeResponses()
      yieldCurrentDiskThread()
    let count = servers.requestCount(true)
    servers.close()
    writeFile(CountPath, $count)
    posix.exitnow(0)
  servers.close()
  var responderReaped = false
  var observerReaped = false
  var observer = posix.Pid(-1)
  defer:
    if not responderReaped:
      discard posix.kill(responder, SIGTERM)
      var state = 0.cint
      discard posix.waitpid(responder, state, 0)
    if int(observer) > 0 and not observerReaped:
      discard posix.kill(observer, SIGTERM)
      var state = 0.cint
      discard posix.waitpid(observer, state,
          0) # Neither responder nor RPC observer may survive a failed parent verdict.
  observer = posix.fork()
  assert int(observer) >= 0
  if int(observer) == 0:
    observeRpc(context, reserved.port)
    posix.exitnow(0)
  var extra = @["--with-rpc", "--rpc-port", $reserved.port]
  var database = "pvm-current-download-rpc-state"
  defer:
    if managed: removeManagedSample(database, [ManagedEpoch(
        1)]) # Every command/observer/responder lifetime ends before durable retirement.
  if managed:
    extra.add("--state-storage")
    extra.add("disk")
    extra.add("--state-db")
    extra.add(database)
    extra.add("--state-layout")
    extra.add("managed")
    extra.add("--state-compact-bytes")
    extra.add("0")
  var selected = default(Options)
  assert parseCanonicalOptions(currentCommandArguments(port, 2, ChainPath, PolicyPath,
      extra), selected)
  let outcome = runCurrentDownloads(selected)
  assert outcome.error == CurrentDownloadCommandResult.Exhausted and
      outcome.adoptedBlocks == 1 and outcome.requestedBlocks == 2
  writeFile(StopPath, "stop")
  var state = 0.cint
  assert posix.waitpid(responder, state, 0) == responder
  responderReaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0
  state = 0
  assert posix.waitpid(observer, state, 0) == observer
  observerReaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0
  assert readFile(CountPath) == "2" and fileExists(DonePath)
  assertPortReleased(reserved.port)
  if managed:
    var reopened = default(Services)
    defer: reopened.close()
    assert reopened.start(currentDiskOptions(ChainPath, database, true, 0), "observed current RPC strict restart")
    equalCurrentDiskMap(reopened.stateSnapshot.value,
        context.source.currentConsensusState.value)
    assert reopened.chainView.retainedCount == 2
    reopened.close()

proc main() {.raises.} =
  ## Genuine current composition defines expected identities without borrowing the live command's canonical owner.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = currentChainFixture(decodeOwnedReport(wire, 2).value,
      available = true)
  check(context, false)
  check(context, true)

try:
  main() # RPC/native/process failures cannot count as success.
except:
  quit(2)

echo "PVM current download RPC passed"
