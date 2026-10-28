# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent real RPC and TLS processes observe two consecutive current adoptions before a later gated refusal.
import std/[assertions, syncio, envvars, monotimes, times, os, strutils, base64]
import std/posix/posix
import ../../../src/app/[current_download_command, current_download_policy,
    options, services]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, header]
import ../../../src/crypto/primitives
import ../../../src/state/[store, block_admission, report_admission, accumulation_current_consensus]
import ../../../src/storage/managed_manifest
import ../../support/[current_consecutive_context, current_rotated_sequence_context,
  current_consecutive_download_context,
  accumulation_current_chain_context,
  current_download_command_context,
  current_application_context, current_services_disk_samples,
  managed_storage_samples,
  block_download_transport, rpc_socket]

const
  ChainPath = "pvm-current-consecutive-rpc-chain.json"
  PolicyPath = "pvm-current-consecutive-rpc-policy.conf"
  StartPath = "pvm-current-consecutive-rpc-start"
  ReadyPath = "pvm-current-consecutive-rpc-ready"
  DonePath = "pvm-current-consecutive-rpc-done"
  StopPath = "pvm-current-consecutive-rpc-stop"
  CountPath = "pvm-current-consecutive-rpc-count"

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
  readPacket(rpc, peer, pending, description = text, attempts = 2000)

proc observeRpc(context: CurrentConsecutiveFixture, port: uint16) {.raises.} =
  ## Subscribe before the first response; exact roots/headers and proof-method refusal must finish before the final empty response is released.
  waitFile(StartPath)
  var rpc = default(Server)
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  upgrade(rpc, peer, pending)
  let hashes = [array[32, byte](context.heads[0].blockHash), array[32, byte](context.heads[
      1].blockHash), array[32, byte](context.heads[2].blockHash)]
  let roots = [array[32, byte](context.heads[0].stateRoot), array[32, byte](context.heads[
      1].stateRoot), array[32, byte](context.heads[2].stateRoot)]
  let slots = [uint32(context.heads[0].slot), uint32(context.heads[1].slot), uint32(context.heads[2].slot)]
  let subscribed = request(rpc, peer, pending,
    """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":1}""")
  assert "\"result\":1" in subscribed
  for index in 0..2:
    let notification = readPacket(rpc, peer, pending, description = "notification " & $index &
        " slot " & $slots[index], attempts = 2000)
    assert base64.encode(hashes[index]) in notification
    assert "\"slot\":" & $slots[index] in notification
    if index == 0: writeFile(ReadyPath, "ready") # Only the actual original-parent notification releases the signed current child.
  let best = request(rpc, peer, pending, """{"jsonrpc":"2.0","method":"bestBlock","id":2}""")
  assert "\"id\":2" in best and base64.encode(hashes[2]) in best
  for index in 0..2:
    let hash = base64.encode(hashes[index])
    let root = request(rpc, peer, pending,
        "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" & hash &
        "\"],\"id\":" & $(10+index) & "}")
    assert "\"id\":" & $(10+index) in root and base64.encode(roots[index]) in root
    let wire = currentChainBytes(context.heads[index].header)
    let sealed = request(rpc, peer, pending,
        "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_header\",\"params\":[\"" &
        hash & "\"],\"id\":" & $(20+index) & "}")
    assert "\"id\":" & $(20+index) in sealed and base64.encode(wire) in sealed
  for index in 1..2:
    let parent = request(rpc, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"parent\",\"params\":[\"" &
        base64.encode(hashes[index]) & "\"],\"id\":" & $(30+index) & "}")
    assert "\"id\":" & $(30+index) in parent and base64.encode(hashes[index-1]) in parent
  let finality = request(rpc, peer, pending, """{"jsonrpc":"2.0","method":"finalizedBlock","id":40}""")
  assert "Finalized chain view unavailable" in finality
  let key = context.heads[0].stateSnapshot.keyAt(StateEntryIndex(0)).value
  let proof = request(rpc, peer, pending,
      "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_requestStateProof\",\"params\":[\"" &
      base64.encode(hashes[2]) & "\",[\"" & base64.encode(array[31, byte](
      key)) & "\"]],\"id\":41}")
  assert "\"id\":41" in proof and "-32601" in
      proof # Download orchestration deliberately admits no autonomous proof borrower.
  writeFile(DonePath, "done") # Ordered notifications and exact retained metadata completed against the actual command listener.

proc check(context: CurrentConsecutiveFixture, disk, managed: bool) {.raises.} =
  ## Prepare genuine expected maps before forks, with no native worker or canonical lease alive across process creation.
  defer:
    for name in [ChainPath, PolicyPath, StartPath, ReadyPath, DonePath,
        StopPath, CountPath]:
      var path = name
      discard posix.unlink(path.toCString()) # All coordination files remain owned by this isolated native suite.
  for name in [StartPath, ReadyPath, DonePath, StopPath, CountPath]:
    var control = name
    discard posix.unlink(control.toCString()) # A failed previous observer cannot stop or release this invocation's independent responder.
  writeFile(ChainPath, context.seed.currentApplicationText)
  writeFile(PolicyPath, encodeCurrentDownloadPolicy(currentConsecutivePolicy()))
  let reserved = reservation()
  discard posix.close(reserved.fd)
  let requests = @[currentExpectedRequest(array[32, byte](context.heads[0].blockHash)),
      currentExpectedRequest(array[32, byte](context.heads[1].blockHash)), currentExpectedRequest(
      array[32, byte](context.heads[2].blockHash))]
  let responses = @[currentConsecutiveResponse(context.children[0]), currentConsecutiveResponse(
      context.children[1]), @[0'u8, 0, 0, 0]]
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses,
    @[Gated, Healthy, Gated])
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
      if count == 3 and fileExists(DonePath): servers.resumeResponses()
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
  var database = "pvm-current-consecutive-rpc-state-" & $getMonoTime().ticks
  defer:
    if disk:
      if managed: removeManagedSample(database, [ManagedEpoch(1)])
      else: discard posix.unlink(database.toCString()) # runCurrentDownloads joins its IO owners before any return.
  if disk:
    extra.add("--state-storage")
    extra.add("disk")
    extra.add("--state-db")
    extra.add(database)
  if managed:
    extra.add("--state-layout")
    extra.add("managed")
    extra.add("--state-compact-bytes")
    extra.add("0")
  var selected = default(Options)
  assert parseCanonicalOptions(currentCommandArguments(port, 3, ChainPath, PolicyPath,
      extra), selected)
  let outcome = runCurrentDownloads(selected)
  assert outcome.error == CurrentDownloadCommandResult.Exhausted and
      outcome.adoptedBlocks == 2 and outcome.requestedBlocks == 3, "RPC command " & $outcome.error &
          " adopted " & $outcome.adoptedBlocks & " first slot " & $uint32(context.heads[1].slot)
  writeFile(StopPath, "stop")
  var state = 0.cint
  assert posix.waitpid(responder, state, 0) == responder
  responderReaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0, "TLS responder joined"
  state = 0
  assert posix.waitpid(observer, state, 0) == observer
  observerReaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0, "RPC observer joined"
  assert readFile(CountPath) == "3" and fileExists(DonePath)
  assertPortReleased(reserved.port)
  if disk:
    var reopened = default(Services)
    defer: reopened.close()
    assert reopened.start(currentDiskOptions(ChainPath, database, managed, 0), "consecutive RPC strict restart")
    assert reopened.chainView.retainedCount == 3
    for index in 0..2:
      let actual = reopened.chainView.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
      assert array[32, byte](actual.blockHash) == array[32, byte](context.heads[index].blockHash)
      equalCurrentDiskMap(actual.stateSnapshot, context.heads[index].stateSnapshot)
    reopened.close()

proc main() {.raises.} =
  ## Genuine current composition defines expected identities without borrowing the live command's canonical owner.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  # Exercise the same real transport/lifecycle assertions before and after the signed slot12 rotation.
  for context in [currentConsecutiveFixture(decodeOwnedReport(wire, 2).value, 2),
      currentRotatedSequenceFixture(decodeOwnedReport(wire, 2).value, 2)]:
    check(context, false, false)
    check(context, true, false)
    check(context, true, true)

try:
  main() # RPC/native/process failures cannot count as success.
except:
  quit(2)

echo "PVM current consecutive RPC passed"
