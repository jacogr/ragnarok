# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete independent service/request maps bind announced content to exact canonical zero-slot histories.
import std/[assertions, envvars, syncio]
import ./jamnp_topology_fixture
import ../../src/chain/genesis
import ../../src/codec/[bounded, header]
import ../../src/codec/state/[safrole, accounts, requests, service_values, trie]
import ../../src/state/store

proc preimageSnapshot*(hash: ServicePreimageHash, length: RequestLength,
    validator = true, recipient = false, malformed = false, history = requestedHistory(),
        account = true,
    extra: seq[StateEntry] = @[]): BlockSnapshotResult {.raises.} =
  ## TLS fixture A is an actual current validator only when requested; no peer-derived root is trusted.
  var current = topologyRecords(1, 9)
  if validator:
    let key = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
    assert key.len == 32
    var raw = default(array[32, byte])
    for index in 0..<32: raw[index] = byte(key[index])
    current[0].ed25519 = StateEdKey(raw)
  if recipient:
    let key = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
    assert key.len == 32
    var raw = default(array[32, byte])
    for index in 0..<32: raw[index] = byte(key[index])
    current[1].ed25519 = StateEdKey(raw)
  let base = topologyCaptured([topologyRecords(0, 6), current, topologyRecords(2, 12)])
  assert base.error == GenesisError.None
  var entries: seq[StateEntry] = @[]
  for index in 0..<base.value.keyCount:
    let key = base.value.keyAt(StateKeyIndex(index))
    entries.add(StateEntry(key: key, value: base.value.lookup(key).value.bytes))
  if account:
    let metadata = serviceMetadataEntry(ServiceIndex(42), default(ServiceMetadata), ByteLimit(105))
    assert metadata.error == ServiceMetadataError.None
    entries.add(metadata.value)
  let config = RequestEntryConfig(keyBytes: ByteLimit(36),
      history: RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))
  let request = serviceRequestEntry(ServiceIndex(42), hash, length, history, config)
  assert request.error == RequestError.None
  var requestEntry = request.value
  if malformed: requestEntry.value.add(0) # A present history suffix must never become a valid outstanding request.
  entries.add(requestEntry)
  for entry in extra: entries.add(entry)
  var wire = newSeq[byte](base.value.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(base.value.header, wire).error == HeaderError.None
  captureBlockSnapshot(wire, entries, topologySettings())
