# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual production acceptors negotiate both JAMNP-S roles while preserving chain/version isolation.
import std/[assertions, envvars, monotimes, times, syncio]
import ../../../src/quic/transport
import ../../../src/jamnp-s/[protocol, alpn, devnet]

type Client = object ## A stable callback owner outlives the native endpoint and its final callbacks.
  transport: Transport
  expected: array[32, byte]
proc `=copy`(destination: var Client, source: Client) {.error.}
  ## A copied engine would duplicate callback and descriptor ownership.
proc `=dup`(source: Client): Client {.error.}
  ## Last-use analysis must not hide duplicated engine ownership.

proc verify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## The dialer pins the same server key for every ALPN trial.
  let client = cast[ptr Client](user)
  cint(validPeer(cast[ptr byte](der), length, client.expected))
proc event(user: pointer, stream: NativeStream, kind: cint) {.cdecl, raises: [].} =
  ## Handshake tests open no application streams; unexpected remote streams receive no handler.
  if kind == 0: streamAbort(stream)
proc key(path: string): array[32, byte] {.raises.} =
  ## Native fixture metadata supplies independently generated raw keys.
  let bytes = readFile(path)
  assert bytes.len == 32
  result = default(array[32, byte])
  for index in 0..<32: result[index] = byte(bytes[index])

proc exchange(configured, offered: string, expected: bool) {.raises.} =
  ## Vary only the protocol offers; production server admission verifies identical certificate identities.
  var server = default(DevnetNetwork)
  var client = default(Client)
  var peers = default(array[6, array[32, byte]])
  peers[0] = key(getEnv("RAGNAROK_TEST_PEER_A"))
  peers[1] = key(getEnv("RAGNAROK_TEST_PEER_B"))
  client.expected = peers[0]
  defer:
    closeTransport(client.transport)
    server.close() # Both native engines retire while callback owners remain at their original addresses.
  assert server.open(0, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), configured, peers)
  assert openTransport(client.transport, false, false, 0, getEnv("RAGNAROK_TEST_CERT_B"),
    getEnv("RAGNAROK_TEST_KEY_B"), offered, addr client, verify, event)
  assert connectTransport(client.transport, server.localPort)
  let deadline = getMonoTime() + initDuration(seconds = 2)
  var accepted = false
  while getMonoTime() < deadline:
    assert server.poll()
    assert pollTransport(client.transport, 0)
    if transportStatus(client.transport) == 1:
      accepted = true
      break # A completed TLS handshake supplies the role/chain acceptance observation.
    if transportStatus(client.transport) < 0: break # An observed handshake rejection need not wait out the deadline.
  assert accepted == expected

proc main() {.raises.} =
  ## Exact version, eight lower-case genesis nibbles and the sole optional suffix define the protocol domain.
  for name in ["jamnp-s/1/1234abcd", "jamnp-s/1/1234abcd/builder"]:
    assert validAlpn(name)
    assert serverAlpns(name) == @["jamnp-s/1/1234abcd", "jamnp-s/1/1234abcd/builder"]
  for name in ["", "jamnp-s/2/1234abcd", "jamnp-s/1/1234ABCd", "jamnp-s/1/1234abc",
      "jamnp-s/1/1234abcde", "jamnp-s/1/1234abcd/other", "jamnp-s/1/1234abcd/builder/x",
      "jamnp-s/1/1234abcd\0"]:
    assert not validAlpn(name) and serverAlpns(name).len == 0
  exchange("jamnp-s/1/1234abcd", "jamnp-s/1/1234abcd", true)
  exchange("jamnp-s/1/1234abcd", "jamnp-s/1/1234abcd/builder", true)
  exchange("jamnp-s/1/1234abcd/builder", "jamnp-s/1/1234abcd", true)
  exchange("jamnp-s/1/1234abcd", "jamnp-s/1/87654321/builder", false)
  exchange("jamnp-s/1/1234abcd", "jamnp-s/2/1234abcd", false)

try:
  main()
except:
  quit 2 # Missing fixture/setup failures cannot be mistaken for a rejected protocol offer.
echo "JAMNP-S base/builder ALPN, exact identifiers and TLS isolation passed"
