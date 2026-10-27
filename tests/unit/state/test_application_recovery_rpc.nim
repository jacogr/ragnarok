# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real RPC exposes exactly the recovered head/map/header while absent ancestors and finality remain unavailable.
import std/[assertions, syncio, envvars, strutils, base64]
import std/posix/posix
import ../../../src/app/[services, options, chain, checkpoint_identity, checkpoint_codec, checkpoint_recovery]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header]
import ../../../src/state/store
import ../../support/[application_checkpoint_context, rpc_socket]
proc request(owner: var Services, peer: cint, pending: var string, text: string): string =
  ## One real masked request receives exactly one bounded response.
  sendText(peer, text)
  readPacket(owner.rpc, peer, pending)
proc main() {.raises.} =
  ## A different independently trusted sealed head rules out accidentally reseeding RPC from configured genesis.
  let source = checkpointFixture(CheckpointFixtureVariant.Header)
  let expected = captureApplicationCheckpointIdentity(source).value
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  let restored = decodeRecoveryCheckpoint(envelope, wire, expected, genesisStoreLimits(), ByteLimit(
      high(uint64)))
  var owner = default(Services)
  defer: owner.close()
  var port = 0'u16
  for attempt in 0..<8:
    let selected = reservation()
    discard posix.close(selected.fd)
    var options = default(Options)
    assert parseCanonicalOptions(@["server", "--with-state", "--with-rpc", "--rpc-port",
      $selected.port,
      "--chain", getEnv("RAGNAROK_APPLICATION_CHECKPOINT"), "--state-writes", "0",
          "--state-write-bytes", "0"], options)
    if owner.startRecovered(options, "recovered RPC", restored):
      port = selected.port
      break # Only the successfully bound listener port reaches a client.
  assert port != 0
  let state = owner.stateSnapshot.value
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  upgrade(owner.rpc, peer, pending)
  let hash = base64.encode(array[32, byte](expected.blockHash))
  let root = base64.encode(array[32, byte](expected.stateRoot))
  let best = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
  assert ("\"header_hash\":\"" & hash & "\"") in best
  assert ("\"slot\":" & $uint32(expected.slot)) in best
  let finality = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"finalizedBlock","id":2}""")
  assert "Finalized chain view unavailable" in finality
  let parent = request(owner, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"parent\",\"params\":[\"" &
      hash & "\"],\"id\":3}")
  assert "Block unavailable" in parent
  let commitment = request(owner, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" &
      hash & "\"],\"id\":4}")
  assert ("\"result\":\"" & root & "\"") in commitment
  let sealed = request(owner, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_header\",\"params\":[\"" &
      hash & "\"],\"id\":5}")
  assert base64.encode(wire) in sealed
  let info = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"ragnarok_clientInfo","id":6}""")
  assert "\"finalizedBlock\":null" in info and hash in info
  let subscription = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":7}""")
  assert "\"result\":1" in subscription
  assert hash in readPacket(owner.rpc, peer, pending)
  let refused = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"subscribeFinalizedBlock","params":[],"id":8}""")
  assert "Finalized chain view unavailable" in refused
  assert sameStateSnapshot(state, owner.stateSnapshot.value)
  assert owner.chainView.retainedCount == 1 and owner.chainView.finalizedBlock.error !=
      GenesisError.None
  echo "PASS application recovery RPC: exact selected head, map and sealed bytes with unavailable ancestors and finality"
try:
  main() # Transport/fixture failures cannot turn an unavailable view into success.
except:
  quit(2)
