# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Structurally captured linked histories exercise durable retention without fabricating execution certificates.
import std/assertions
import ./application_checkpoint_context
import ../../src/app/chain
import ../../src/chain/[genesis, provider]
import ../../src/state/store
import ../../src/codec/[header, bounded, state_trie, state_layout]

type DiskHistoryFixture* = object ## Every authored header has its exact complete slot-bearing mapping.
  view*: ChainView
  blocks*: seq[BlockSnapshotResult]
  policy*: StateStoreLimits
proc diskHistoryFixture*(children = 12, withFinality = true): DiskHistoryFixture {.raises.} =
  ## Only local history/capture contracts are tested; these modified seals are never execution certificates.
  assert children >= 0 and children <= 16
  let original = checkpointFixture().chainView.bestBlock.value
  var policy = genesisStoreLimits()
  policy.writes = ElementLimit(1)
  policy.writeValueBytes = ByteLimit(4)
  var entries: seq[StateEntry] = @[]
  let source = original.stateSnapshot
  for index in 0..<source.commitment.entries:
    let key = source.keyAt(StateEntryIndex(index)).value
    entries.add(StateEntry(key: key, value: source.lookup(key).value.bytes))
  var state = newStateStore(entries, policy).value
  var wire = newSeq[byte](original.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(original.header, wire).error == HeaderError.None
  let first = captureBlockSnapshot(wire, state.snapshot.value, original.chainParameters)
  assert first.error == GenesisError.None
  var view = genesisView(first)
  if withFinality: view = view.finalizeView(first.value.blockHash).value
  var blocks = @[first]
  assert original.slot <= high(uint32)-uint32(children)
  for index in 1..children:
    let parent = view.bestBlock.value
    let identity = array[32, byte](parent.blockHash)
    let root = array[32, byte](parent.stateRoot)
    for octet in 0..<32:
      wire[octet] = identity[octet]
      wire[32+octet] = root[octet] # Child prior root always names the exact parent's posterior map.
    let slot = original.slot+uint32(index)
    var clock = newSeq[byte](4)
    for octet in 0..<4:
      clock[octet] = byte((slot shr (octet*8)) and 255)
      wire[96+octet] = clock[octet]
    let changed = state.apply([StateWrite(key: chapterKey(StateChapter(11)),
      kind: StateWriteKind.Put, value: clock)]).value
    let child = captureBlockSnapshot(wire, changed, original.chainParameters)
    assert child.error == GenesisError.None
    view = view.advanceView(child).value
    blocks.add(child)
  DiskHistoryFixture(view: view, blocks: blocks, policy: policy)
