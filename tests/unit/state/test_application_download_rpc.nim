# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent RPC and TLS processes observe each real canonical adoption while a later response remains explicitly gated.
import std/[assertions, syncio, envvars, monotimes, times, os, strutils, base64]
import std/posix/posix
import ../../../src/app/[download_command, download_policy, options]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, header]
import ../../support/[application_download_chain, application_download_command_context,
  block_download_transport, rpc_socket]

const
  ChainPath = "download-rpc-chain.json"
  PolicyPath = "download-rpc-policy.conf"
  StartPath = "download-rpc-start"
  ReadyPath = "download-rpc-ready"
  DonePath = "download-rpc-done"
  StopPath = "download-rpc-stop"
  CountPath = "download-rpc-count"

proc waitFile(path: string) =
  ## Bound cross-process coordination without touching another process's canonical or native owner.
  let started = getMonoTime()
  while not fileExists(path):
    assert (getMonoTime() - started).inMilliseconds < 12000, "RPC synchronization file"
    pauseDownload()

proc request(rpc: var Server, peer: cint, pending: var string, text: string): string =
  ## Default local Server ticks do no IO; the real parent command pumps the remote listener independently.
  sendText(peer, text)
  readPacket(rpc, peer, pending)

proc observeRpc(context: DownloadChainFixture, port: uint16) {.raises.} =
  ## Subscribe before releasing the first child, then read/query the complete retained prefix before releasing a final empty reply.
  waitFile(StartPath)
  var rpc = default(Server)
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  upgrade(rpc, peer, pending)
  let subscribed = request(rpc, peer, pending,
    """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":1}""")
  assert "\"result\":1" in subscribed
  for index in 0..3:
    let notification = readPacket(rpc, peer, pending)
    assert base64.encode(array[32, byte](context.heads[index].blockHash)) in notification
    assert "\"slot\":" & $uint32(context.heads[index].slot) in notification
    if index == 0: writeFile(ReadyPath, "ready") # Only an actual initial notification releases response one.
  let best = request(rpc, peer, pending, """{"jsonrpc":"2.0","method":"bestBlock","id":2}""")
  assert "\"id\":2" in best and base64.encode(array[32, byte](context.heads[3].blockHash)) in best
  for index in 0..3:
    let hash = base64.encode(array[32, byte](context.heads[index].blockHash))
    let root = request(rpc, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" &
        hash & "\"],\"id\":" & $(10 + index) & "}")
    assert "\"id\":" & $(10 + index) in root
    assert base64.encode(array[32, byte](context.heads[index].stateRoot)) in root
    var wire = newSeq[byte](context.heads[index].header.headerInfo.value.consumed)
    assert encodeOwnedHeader(context.heads[index].header, wire).error == HeaderError.None
    let sealed = request(rpc, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_header\",\"params\":[\"" &
        hash & "\"],\"id\":" & $(20 + index) & "}")
    assert base64.encode(wire) in sealed
    if index > 0:
      let parent = request(rpc, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"parent\",\"params\":[\"" &
          hash & "\"],\"id\":" & $(30 + index) & "}")
      assert base64.encode(array[32, byte](context.heads[index - 1].blockHash)) in parent
  let finality = request(rpc, peer, pending, """{"jsonrpc":"2.0","method":"finalizedBlock","id":40}""")
  assert "Finalized chain view unavailable" in finality
  writeFile(DonePath, "done") # Every ordered notification/root/header/parent query completed against the actual command listener.

proc main() {.raises.} =
  ## Prepare genuine expected maps before forks, with no native worker or canonical lease alive across process creation.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(wire, 2).value)
  defer:
    for name in [ChainPath, PolicyPath, StartPath, ReadyPath, DonePath, StopPath, CountPath]:
      var path = name
      discard posix.unlink(path.toCString()) # All coordination files remain owned by this isolated native suite.
  writeFile(ChainPath, context.seed.text)
  writeFile(PolicyPath, encodeDownloadPolicy(downloadLimits()))
  let reserved = reservation()
  discard posix.close(reserved.fd)
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  for index in 0..3:
    requests.add(expectedRequest(context.heads[index]))
    responses.add(if index == 3: @[0'u8, 0, 0, 0] else: responseFrame(context.children[index]))
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses,
    @[Gated, DownloadTransferMode.Healthy, DownloadTransferMode.Healthy, Gated])
  let port = servers.port(true)
  let responder = posix.fork()
  assert int(responder) >= 0
  if int(responder) == 0:
    let started = getMonoTime()
    while not fileExists(StopPath) and (getMonoTime() - started).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3)
      let count = servers.requestCount(true)
      if count >= 1 and not fileExists(StartPath): writeFile(StartPath,
          "start") # TLS request receipt proves the RPC listener has already started.
      if count == 1 and fileExists(ReadyPath): servers.resumeResponses()
      if count == 4 and fileExists(DonePath): servers.resumeResponses()
      pauseDownload()
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
      discard posix.waitpid(observer, state, 0) # Neither responder nor RPC observer may survive a failed parent verdict.
  observer = posix.fork()
  assert int(observer) >= 0
  if int(observer) == 0:
    observeRpc(context, reserved.port)
    posix.exitnow(0)
  var selected = default(Options)
  assert parseOptions(downloadArguments(port, 4, ChainPath, PolicyPath,
    @["--with-rpc", "--rpc-port", $reserved.port]), selected)
  let outcome = runDownloads(selected)
  assert outcome.error == DownloadCommandResult.Exhausted and outcome.adoptedBlocks == 3
  writeFile(StopPath, "stop")
  var state = 0.cint
  assert posix.waitpid(responder, state, 0) == responder
  responderReaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0
  state = 0
  assert posix.waitpid(observer, state, 0) == observer
  observerReaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0
  assert readFile(CountPath) == "4" and fileExists(DonePath)
  assertPortReleased(reserved.port)
  echo "PASS application download RPC: ordered real notifications, exact retained roots and headers across confirmed progress"
try:
  main() # RPC/native/process failures cannot count as success.
except:
  quit(2)
