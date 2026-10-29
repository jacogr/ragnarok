# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real RPC admission inside a dispatcher turn preserves the current input through exact deadline and joined proof retirement.
import std/[assertions, syncio, envvars, base64, strutils, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/download/schedule as download_schedule
import ../../../src/app/proof/worker as proof_worker
import "../../../src/quic/current/block/download/loop" as current_block_download_loop
import ../../../src/codec/report_owned
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/rpc/server
import ../../support/[accumulation_current_chain_context,
  current_application_context,
  current_download_command_context, current_services_disk_samples, rpc_socket]

proc lease(owner: Services) =
  ## Pointer-owned dispatcher mutation is observed anew rather than reused as a stale compiler fact.
  assert owner.stateProofActive and owner.rpc.chainPaused

proc check(context: CurrentChainFixture, done: bool) {.raises.} =
  ## The real WebSocket reserves intent without host admission; one dispatcher turn then starts the native borrower.
  var path = "pvm-current-download-rpc-lease-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  defer:
    dispatcher.close()
    owner.close()
  let reserved = reservation()
  discard posix.close(reserved.fd)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path, "--with-rpc",
      "--rpc-port", $reserved.port], options)
  assert owner.start(options, "current RPC proof lease")
  let parent = owner.stateSnapshot.value
  let selected = owner.chainView.bestBlock.value.blockHash
  let key = parent.keyAt(StateEntryIndex(0)).value
  var limits = currentCommandLimits()
  limits.attemptTimeout = CurrentDownloadAttemptTimeout(1)
  assert dispatcher.configure(owner, [DownloadPeerId(2)], [], limits,
      CurrentDownloadLoopTick(0)) == CurrentDownloadLoopError.None
  assert dispatcher.tick(CurrentDownloadLoopTick(0)) ==
      CurrentDownloadLoopError.None
  assert dispatcher.stage == CurrentDownloadLoopStage.Receiving # The original-parent input exists before a proof borrows that graph.
  let peer = client(reserved.port)
  defer: discard posix.close(peer)
  var pending = ""
  owner.rpc.upgrade(peer, pending)
  let request = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_requestStateProof\",\"id\":17,\"params\":[\"" &
      base64.encode(array[32, byte](selected)) & "\",[\"" & base64.encode(array[
      31, byte](key)) & "\"]]}"
  sendText(peer, request)
  let acknowledged = readPacket(owner.rpc, peer, pending)
  assert "\"id\":17" in acknowledged and "\"result\":1" in acknowledged
  assert not owner.stateProofActive # Only the actual Services turn can dispatch the queued RPC proof intent.
  assert dispatcher.tick(CurrentDownloadLoopTick(1)) ==
      CurrentDownloadLoopError.None
  lease(owner)
  assert dispatcher.stage == CurrentDownloadLoopStage.Receiving # Exact attempt expiry cannot retire aliases after same-turn proof admission.
  if done:
    let start = getMonoTime()
    while owner.stateProofPhase != ProofWorkerPhase.Done:
      assert (getMonoTime()-start).inSeconds < 20
      yieldCurrentDiskThread() # Poll scalar phase only; Done retains the lease until actual collection or join.
    lease(owner)
  dispatcher.close()
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  let stopped = readPacket(owner.rpc, peer, pending)
  assert "State proof stopped" in stopped and "\"request\":1" in stopped
  assert "\"proof\"" notin stopped, "joined cancellation cannot publish unwanted proof bytes"
  equalCurrentDiskMap(owner.stateSnapshot.value, parent)
  assert owner.chainView.retainedCount == 1
  assert dispatcher.stage == CurrentDownloadLoopStage.Closed

proc main() {.raises.} =
  ## Independently authored complete current state supports both immediate and observed-Done joined shutdown.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let context = currentChainFixture(decodeOwnedReport(report, 2).value,
      available = true)
  check(context, false)
  check(context, true)
try:
  main()
except:
  quit(2) # A native lease, RPC identity or canonical-map failure cannot count as successful cancellation.
echo "PVM current download RPC lease passed"
