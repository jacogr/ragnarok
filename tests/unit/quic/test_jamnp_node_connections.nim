# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_node_connections_arc_release"}

## Real validator connection ownership, source-derived routing and duplicate arbitration witnesses.

import std/[assertions, syncio, envvars, monotimes, times, strutils]
import std/posix/posix
import ../../support/[jamnp_topology_fixture, jamnp_connection_pair, arc_evidence]
import ../../../src/jamnp-s/[connections, identity]
import ../../../src/quic/address
import ../../../src/codec/state/safrole
import ../../../src/chain/genesis

proc key(path: string): StateEdKey {.raises.} =
  ## Independent raw public fixture files validate the selected certificate identity.
  let raw = readFile(path)
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index])
  StateEdKey(bytes)

proc records(left, right: StateEdKey): array[3, seq[StateValidator]] =
  ## Aliases preserve real population/grid ordinals without synthetic unreachable peer targets.
  result = [newSeq[StateValidator](6), newSeq[StateValidator](9), newSeq[StateValidator](12)]
  for epoch in 0..<3:
    for index in 0..<result[epoch].len:
      result[epoch][index] = StateValidator(ed25519: (if index mod 2 == 0: left else: right))

proc startup() {.raises.} =
  ## Defaults/invalid startup grant no endpoint; actual public identity is copied from the leaf certificate.
  let left = key(getEnv("RAGNAROK_TEST_PEER_A"))
  let right = key(getEnv("RAGNAROK_TEST_PEER_B"))
  let decoded = certificateIdentity(getEnv("RAGNAROK_TEST_CERT"))
  assert decoded.error == CertificateIdentityError.None
  assert array[32, byte](decoded.value) == array[32, byte](left)
  assert preferredInitiator(left, right) != preferredInitiator(right, left)
  let source = topologyCaptured(records(left, right))
  assert source.error == GenesisError.None
  var node = default(NodeConnections)
  defer: node.close()
  assert not node.isOpen and node.peerCount == 0
  assert node.open(default(ConnectionConfig), source, topologyLimits()) ==
      ConnectionError.InvalidConfig
  var binding = default(NetworkAddress)
  assert parseNetworkAddress("::1", binding)
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    "jamnp-s/1/00000000", binding = binding, others = 0, streams = 32)
  assert node.open(config, source, topologyLimits()) == ConnectionError.None, "valid node startup"
  assert node.isOpen and node.localPort > 0 and node.peerCount == 0
  assert node.open(config, source, topologyLimits()) == ConnectionError.InvalidConfig
  assert node.poll(getMonoTime(), 0)
  node.close()
  assert not node.isOpen and node.peerCount == 0

proc identityBoundaries() {.raises.} =
  ## Malformed and oversized public inputs never grant a key; chain files select their actual first leaf.
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  assert directory.len > 0, "supported native launcher supplies an owned evidence directory"
  var path = directory & "/node-identity-invalid.pem"
  defer: discard posix.unlink(path.toCString())
  writeFile(path, "-----BEGIN CERTIFICATE-----\n!!!!\n-----END CERTIFICATE-----")
  assert certificateIdentity(path).error == CertificateIdentityError.InvalidPem
  writeFile(path, "-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----")
  assert certificateIdentity(path).error == CertificateIdentityError.InvalidCertificate
  writeFile(path, "-----BEGIN CERTIFICATE-----\n" & repeat("A", 17000) & "\n-----END CERTIFICATE-----")
  assert certificateIdentity(path).error == CertificateIdentityError.InvalidPem
  writeFile(path, repeat("A", 128*1024+1))
  assert certificateIdentity(path).error == CertificateIdentityError.ReadFailed
  writeFile(path, readFile(getEnv("RAGNAROK_TEST_CERT")) & readFile(getEnv("RAGNAROK_TEST_CERT_B")))
  let first = certificateIdentity(path)
  assert first.error == CertificateIdentityError.None
  assert array[32, byte](first.value) == array[32, byte](key(getEnv("RAGNAROK_TEST_PEER_A")))
  assert certificateIdentity("").error == CertificateIdentityError.ReadFailed
  assert certificateIdentity("bad\0path").error == CertificateIdentityError.ReadFailed
  var left, right = default(array[32, byte])
  left[0] = 1
  right[0] = 2
  assert preferredInitiator(StateEdKey(left), StateEdKey(right)), "literal lexicographic preferred initiator"
  left[31] = 128
  assert not preferredInitiator(StateEdKey(left), StateEdKey(right)), "last-byte high bit reverses the literal preference"

proc lifetime(source: BlockSnapshotResult, config: ConnectionConfig, refuse: bool) =
  ## Scope destruction retires every copied path/topology/dispatcher allocation after explicit native close.
  var node = default(NodeConnections)
  var selected = config
  if refuse: selected.privateKey.add(".missing") # Failure happens after listener resources begin setup.
  let opened = node.open(selected, source, topologyLimits())
  if refuse: assert opened == ConnectionError.BackendFailure and not node.isOpen
  else: assert opened == ConnectionError.None
  node.close()

proc released() {.raises.} =
  ## Warm both successful and partial-failure paths before measuring complete owner destruction.
  let left = key(getEnv("RAGNAROK_TEST_PEER_A"))
  let right = key(getEnv("RAGNAROK_TEST_PEER_B"))
  let source = topologyCaptured(records(left, right))
  let config = initConnectionConfig(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
      "jamnp-s/1/00000000", streams = 32)
  lifetime(source, config, false)
  lifetime(source, config, true)
  let before = getOccupiedMem()
  for cycle in 0..<1000: lifetime(source, config, cycle mod 2 == 0)
  let after = getOccupiedMem()
  assert before == after, "complete node ownership must release every final Nim allocation"
  recordArcRelease("jamnp_node_connections", 1000, before, after)

try:
  startup()
  identityBoundaries()
  released()
  connectionPair(false, idle = true)
  connectionPair(true)
  connectionPair(false, stopReady = true)
  connectionPair(true, holdOpened = true)
  headUpdateFairness()
except:
  quit 2 # Fixture/public-file/native setup exceptions are never passing network evidence.
echo "jamnp node connections: lifecycle and authenticated peer routing passed"
