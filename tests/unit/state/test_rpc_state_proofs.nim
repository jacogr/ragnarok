# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "rpc_state_proofs_arc_release"}

## Real WebSocket proof admission, native offload, exact receive verification, refusal, cancellation and joined retirement.
import std/[assertions, syncio, strutils, base64, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/chain/genesis
import ../../../src/rpc/[server, protocol]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    safrole as state_safrole]
from ../../../src/codec/composite import ServiceIndex
import ../../../src/state/proof/plan as proof_plan
import ../../../src/state/planned/proof as planned_proof
import ../../../src/state/proof/[view as proof_view, service as proof_service,
    global as proof_global]
import ../../support/[proof_query_context, rpc_socket, arc_evidence, management_socket]
from ../../support/application_candidate_context import SeedFixture

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only between bounded synchronized worker polls.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Inject maintained native hash refusal before submission, never concurrently with host flag mutation.
proc selection(context: SeedFixture): tuple[hash: BlockHash, root: StateRoot,
    service: ServiceIndex] {.raises.} =
  ## Retire independent fixture/canonical aliases before returning only fixed expected identities.
  let selected = querySelection(context).value
  (selected.blockHash, selected.stateRoot, selected.serviceAt(ServiceListIndex(0)))
proc listener(owner: var Services, path: string, command = "server",
    management = ""): uint16 {.raises.} =
  ## Bind a real ephemeral RPC listener; bounded retries cover only the reservation/rebind race.
  for attempt in 0..<8:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    var options = default(Options)
    var arguments = @[command, "--chain", path, "--with-state", "--with-rpc", "--rpc-port",
      $reserved.port, "--state-writes", "1000", "--state-write-bytes", "1000000"]
    if management.len > 0:
      arguments.add("--with-management"); arguments.add("--management-socket"); arguments.add(management)
    assert parseCanonicalOptions(arguments, options)
    if owner.start(options, command): return reserved.port
  assert false, "proof RPC listener startup"
  0'u16
proc settle(owner: var Services) =
  ## RPC-owned jobs auto-collect; direct RPC polling is forbidden while its canonical lease is active.
  let start = getMonoTime()
  while owner.stateProofActive:
    assert owner.rpc.chainPaused
    assert (getMonoTime()-start).inSeconds < 20, "bounded proof worker collection"
    owner.tick(0)
    discard pauseMicros(1000)
  assert not owner.rpc.chainPaused
proc proofBytes(message: string): seq[byte] =
  ## Read only the Base64 alphabet inside the already schema-checked server notification.
  const prefix = "\"proof\":\""
  let start = message.find(prefix)
  assert start >= 0
  let finish = message.find('"', start + prefix.len)
  assert finish > start + prefix.len
  let encoded = message[start + prefix.len..<finish]
  let decoded = base64.decode(encoded)
  assert base64.encode(decoded) == encoded
  result = newSeq[byte](decoded.len)
  for index in 0..<decoded.len: result[index] = byte(decoded[index]) # Copy only fully decoded initialized bytes.
proc roundtrip(owner: var Services, peer: cint, pending: var string, call: string,
    management = ""): string =
  ## Admit after parsing, observe the exclusive lease, collect, then consume acknowledgement before terminal output.
  sendText(peer, call)
  var claimed = false
  for attempt in 0..<200:
    owner.tick(0)
    if owner.stateProofActive:
      claimed = true
      break # A fast worker still retains its host lease until the next collection tick.
    discard pauseMicros(1000) # Local socket delivery need not coincide with the first dispatcher turn.
  assert claimed and owner.rpc.chainPaused
  if management.len > 0:
    let admin = managementInfo(owner.management, management)
    assert "\"residentBytes\":" in admin and "\"freeBytes\":" in admin
    assert owner.stateProofActive and owner.rpc.chainPaused # Management cannot collect or release the worker lease.
  owner.settle()
  let acknowledged = readPacket(owner.rpc, peer, pending)
  assert "\"id\":7" in acknowledged and "\"error\"" notin acknowledged
  result = readPacket(owner.rpc, peer, pending)
  assert "\"method\":\"ragnarok_stateProof\"" in result
proc cycle(owner: var Services, peer: cint, pending: var string, call: string) =
  ## All response/decoder temporaries retire before the next ownership observation.
  let message = owner.roundtrip(peer, pending, call)
  assert "\"format\":\"RPV1\"" in message and "\"error\"" notin message
proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Private management fixture names do not collide across test processes.
proc main() {.raises.} =
  ## Freeze root authority independently; no externally retained canonical owner enters native execution.
  failHash(0)
  let context = queryContext()
  var path = "rpc-state-proofs-chain.json"
  writeFile(path, context.text)
  defer: discard posix.unlink(path.toCString())
  let fixed = selection(context)
  let timeKey = chapterKey(StateChapter(11))
  let accountKey = chapterServiceKey(StateChapter(255), fixed.service)
  let absentKey = default(StateKey)
  let plan = captureStateProofPlan([timeKey, accountKey, absentKey], ElementLimit(3)).value
  let hashText = base64.encode(array[32, byte](fixed.hash))
  let rootText = base64.encode(array[32, byte](fixed.root))
  let keyText = "[" & quote(base64.encode(array[31, byte](timeKey))) & "," &
    quote(base64.encode(array[31, byte](accountKey))) & "," & quote(base64.encode(array[31, byte](
        absentKey))) & "]"
  let call = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_requestStateProof\",\"id\":7,\"params\":[" &
      quote(hashText) & "," & keyText & "]}"
  var owner = default(Services)
  defer: owner.close()
  var adminDirectory = "/tmp/ragnarok-proof-admin-" & $processId()
  assert mkdir(adminDirectory.toCString(), Mode(0o700)) == 0
  defer:
    owner.close() # End the socket lifetime before removing its enclosing private directory.
    assert rmdir(adminDirectory.toCString()) == 0
  var adminPath = adminDirectory & "/admin.sock"
  let port = owner.listener(path, management = adminPath)
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  owner.rpc.upgrade(peer, pending)
  let message = owner.roundtrip(peer, pending, call, adminPath)
  assert "\"header_hash\":" & quote(hashText) in message
  assert "\"state_root\":" & quote(rootText) in message
  let packet = proofBytes(message)
  let receive = queryLimits() # Independent caller policy is supplied again on receipt.
  let verified = decodePlannedProofs(packet, plan, fixed.root, receive.view, receive.proof,
    receive.aggregate, ByteLimit(MaxRpcProofBytes))
  assert verified.error == ProofViewError.None
  assert uint32(verified.value.readGlobalTime.value) == 1
  assert verified.value.readProofAccount(fixed.service).error == ServiceProofError.None
  assert not verified.value.lookup(absentKey).value.present # Missing evidence would refuse; this is authenticated absence.
  var wrong = array[32, byte](fixed.root)
  wrong[0] = wrong[0] xor 1
  assert decodePlannedProofs(packet, plan, StateRoot(wrong), receive.view, receive.proof,
    receive.aggregate, ByteLimit(MaxRpcProofBytes)).error != ProofViewError.None
  var corrupt = packet
  corrupt[corrupt.len - 1] = corrupt[corrupt.len - 1] xor 1
  assert decodePlannedProofs(corrupt, plan, fixed.root, receive.view, receive.proof,
    receive.aggregate, ByteLimit(MaxRpcProofBytes)).error != ProofViewError.None
  let wrongPlan = captureStateProofPlan([timeKey], ElementLimit(1)).value
  assert decodePlannedProofs(packet, wrongPlan, fixed.root, receive.view, receive.proof,
    receive.aggregate, ByteLimit(MaxRpcProofBytes)).error != ProofViewError.None
  # Unknown selected blocks acknowledge only intent, then emit a terminal failure without proof bytes.
  sendText(peer, call.replace(hashText, base64.encode(default(array[32, byte]))))
  assert "\"result\":2" in readPacket(owner.rpc, peer, pending)
  owner.tick(0)
  assert not owner.stateProofActive
  let unknown = readPacket(owner.rpc, peer, pending)
  assert "InvalidSelection" in unknown and "\"proof\"" notin unknown
  let cancel = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_cancelStateProof\",\"id\":8,\"params\":[3]}"
  sendText(peer, "[" & call & "," & cancel & "]")
  let cancelled = readPacket(owner.rpc, peer, pending)
  owner.tick(0)
  assert not owner.stateProofActive
  assert "\"result\":3" in cancelled and "\"result\":true" in cancelled
  # A queued batch cannot reserve two connection jobs before host dispatch.
  sendText(peer, "[" & call & "," & call & "]")
  let batched = readPacket(owner.rpc, peer, pending)
  owner.tick(0)
  assert owner.stateProofActive
  owner.settle()
  assert "\"result\":4" in batched and "\"code\":0" in batched
  assert "\"request\":4" in readPacket(owner.rpc, peer, pending)
  # Joined stop retires native borrowing before returning a terminal error and reopening RPC.
  sendText(peer, call)
  assert "\"result\":5" in readPacket(owner.rpc, peer, pending)
  owner.tick(0)
  assert owner.stateProofActive
  owner.stopStateProofs()
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  assert "State proof stopped" in readPacket(owner.rpc, peer, pending)
  failHash(1)
  let backendFailure = owner.roundtrip(peer, pending, call)
  failHash(0) # Mutation follows collection/join, never native cryptographic work.
  assert "\"error\"" in backendFailure and "\"proof\"" notin backendFailure
  # Repeated jobs reuse the worker and release per-request selectors, proof scratch and terminal bytes.
  owner.cycle(peer, pending, call)
  let before = getOccupiedMem()
  for iteration in 0..<1000: owner.cycle(peer, pending, call)
  let after = getOccupiedMem()
  assert after == before, "proof RPC ownership is stable across repeated native jobs"
  recordArcRelease("rpc_state_proofs", 1000, before, after)
  sendText(peer, call)
  discard readPacket(owner.rpc, peer, pending) # Ensure the queued selector reached the host before testing joined close.
  owner.tick(0)
  assert owner.stateProofActive
  owner.close() # Join wins even if generation is still queued/running; no detached reply outlives its listener.
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  # Download orchestration deliberately keeps autonomous proof admission unavailable.
  var download = default(Services)
  defer: download.close()
  let downloadPort = download.listener(path, "download")
  let observer = client(downloadPort)
  defer: discard posix.close(observer)
  var observing = ""
  download.rpc.upgrade(observer, observing)
  sendText(observer, call)
  assert "-32601" in readPacket(download.rpc, observer, observing)
  assert not download.stateProofActive
  echo "RPC state proof Services checks passed"
try:
  main()
except:
  quit(2) # Fixture/file/native startup failure must fail the suite rather than disappear.
