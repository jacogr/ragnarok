# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently resealed complete physical graphs distinguish graph authority from page/record integrity.
# @@Verification={"arc":"storage_full_paged_graph_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/state_full_paged_reference
import ../../../src/storage/full_paged_codec as storage_full_paged_codec
import ../../../src/storage/full_paged_stream as storage_full_paged_stream
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/paged_stream as storage_paged_stream
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/crypto/primitives as crypto_primitives

let left = leaf(0, @[1'u8, 2, 3])
let right = leaf(128, @[])
let parent = branch(left, right)
let ordinary = fixture(@[left, right, parent], parent, @[claim(parent, 2, 3, 3)])

block positive:
  # Both page policies establish complete-root authority and distinguish empty presence from absence.
  for cache in 0..1:
    let admitted = ordinary.check(policy(cache))
    assert admitted.error == FullPagedStreamError.None
    let checked = admitted.value
    let root = StateRoot(array[32, byte](parent.digest))
    let found = lookupFullPaged(ordinary.io.input, checked, root, key(0))
    assert found.error == FullPagedStreamError.None and found.value.present
    assert found.value.bytes == @[1'u8, 2, 3]
    let empty = lookupFullPaged(ordinary.io.input, checked, root, key(128))
    assert empty.error == FullPagedStreamError.None and empty.value.present and
        empty.value.bytes.len == 0
    let absent = lookupFullPaged(ordinary.io.input, checked, root, key(64))
    assert absent.error == FullPagedStreamError.None and not absent.value.present
    assert lookupFullPaged(ordinary.io.input, checked, StateRoot(default(array[32, byte])),
      key(0)).error == FullPagedStreamError.UnknownRoot
    var detached = found.value.bytes
    detached[0] = 99
    assert lookupFullPaged(ordinary.io.input, checked, root, key(0)).value.bytes[0] == 1

block emptyRoot:
  # A complete empty graph has no records, no values and a genuinely empty disk scratch extent.
  let empty = fixture(@[], default(TrieRecord), @[FullPagedRoot()])
  let admitted = empty.check(policy())
  assert admitted.error == FullPagedStreamError.None
  let absent = lookupFullPaged(empty.io.input, admitted.value, default(StateRoot), key(0))
  assert absent.error == FullPagedStreamError.None and not absent.value.present

block longValue:
  # One bounded long leaf crosses physical pages without retaining any whole-dataset record table.
  var payload = newSeq[byte](4097)
  for index in 0..<payload.len: payload[index] = byte(index mod 251)
  let record = leaf(0, payload)
  let full = fixture(@[record], record, @[claim(record, 1, 1, 4097)])
  let admitted = full.check(policy())
  assert admitted.error == FullPagedStreamError.None
  assert lookupFullPaged(full.io.input, admitted.value, full.header.root, key(0)).value.bytes == payload
  var short = policy()
  short.trie.perValue = ByteLimit(4096)
  assert full.check(short).error == FullPagedStreamError.LimitExceeded

block graphAuthority:
  # Every hostile graph below has valid record hashes and a fully rebuilt local digest tree.
  let reversed = branch(right, left)
  assert fixture(@[left, right, reversed], reversed, @[claim(reversed, 2, 3, 3)]).
    check(policy()).error == FullPagedStreamError.InvalidGraph
  let repeated = branch(left, left)
  assert fixture(@[left, repeated], repeated, @[claim(repeated, 2, 2, 6)]).
    check(policy()).error == FullPagedStreamError.InvalidGraph
  assert fixture(@[parent, right], parent, @[claim(parent, 1, 2, 0)]).
    check(policy()).error == FullPagedStreamError.MissingNode
  let extra = leaf(64, @[9'u8])
  assert fixture(@[left, right, parent, extra], parent, @[claim(parent, 2, 3, 3)]).
    check(policy()).error == FullPagedStreamError.UnreachableRecord
  assert fixture(@[left, right, parent], parent, @[claim(parent, 1, 3, 3)]).
    check(policy()).error == FullPagedStreamError.CountMismatch
  let shared = fixture(@[left, right, parent], parent, @[claim(parent, 2, 3, 3), claim(left, 1, 1, 3)])
  assert shared.check(policy()).error == FullPagedStreamError.None
  let sharedChecked = shared.check(policy()).value
  assert lookupFullPaged(shared.io.input, sharedChecked, StateRoot(array[32, byte](left.digest)),
    key(0)).value.bytes == @[1'u8, 2, 3]
  var aliasLeft = array[32, byte](left.digest)
  aliasLeft[0] = aliasLeft[0] xor 128
  var alias = parent
  alias.left = StateNodeHash(aliasLeft)
  assert fixture(@[left, right, alias], alias, @[claim(alias, 2, 3, 3)]).
    check(policy()).error == FullPagedStreamError.MissingNode

block quotas:
  # Exact observed work succeeds; lowering each independently exercised counter refuses before dispatch.
  let observed = ordinary.check(policy()).value.counts
  var exact = policy()
  exact.work.ioCalls = ElementLimit(observed.ioCalls)
  exact.work.hashes = ElementLimit(observed.hashes)
  exact.work.visits = ElementLimit(observed.visits)
  exact.work.readBytes = ByteLimit(observed.readBytes)
  exact.work.writeBytes = ByteLimit(observed.writeBytes)
  assert ordinary.check(exact).error == FullPagedStreamError.None
  for channel in 0..4:
    # Every operation channel is independently finite, including scratch reads and resets.
    var short = exact
    case channel
    of 0: short.work.ioCalls = ElementLimit(observed.ioCalls-1)
    of 1: short.work.hashes = ElementLimit(observed.hashes-1)
    of 2: short.work.visits = ElementLimit(observed.visits-1)
    of 3: short.work.readBytes = ByteLimit(observed.readBytes-1)
    else: short.work.writeBytes = ByteLimit(observed.writeBytes-1)
    assert ordinary.check(short).error == FullPagedStreamError.LimitExceeded
  var exactScratch = policy()
  exactScratch.scratchBytes = ByteLimit(ordinary.header.geometry.entries*2)
  assert ordinary.check(exactScratch).error == FullPagedStreamError.None, "exact2N scratch allowance"
  var shortScratch = policy()
  shortScratch.scratchBytes = ByteLimit(5)
  assert ordinary.check(shortScratch).error == FullPagedStreamError.LimitExceeded
  var cache = policy(2)
  assert ordinary.check(cache).error == FullPagedStreamError.UnsupportedPolicy

block ioFailures:
  # Enumerate every actual callback boundary in independent source and scratch owners.
  let source = FullPagedTestIO(bytes: clone(ordinary.io.bytes))
  let temporary = FullPagedTestIO(bytes: newSeq[byte](6))
  assert validateFullPaged(source.input, temporary.scratch, ordinary.header, ordinary.manifest,
    policy()).error == FullPagedStreamError.None
  let sourceCalls = source.calls
  let scratchCalls = temporary.calls
  for index in 1..sourceCalls:
    # Exact reads and pre/post EOF checks cannot fail open.
    let failed = FullPagedTestIO(bytes: clone(ordinary.io.bytes), failAt: index)
    assert validateFullPaged(failed.input, FullPagedTestIO(bytes: newSeq[byte](6)).scratch,
        ordinary.header,
      ordinary.manifest, policy()).error == FullPagedStreamError.IOFailure
  for index in 1..scratchCalls:
    # Scratch is a resource with its own real failure channel, including reset and final EOF.
    let failed = FullPagedTestIO(bytes: newSeq[byte](6), failAt: index)
    assert validateFullPaged(FullPagedTestIO(bytes: clone(ordinary.io.bytes)).input, failed.scratch,
      ordinary.header, ordinary.manifest, policy()).error == FullPagedStreamError.IOFailure
  let grown = FullPagedTestIO(bytes: clone(ordinary.io.bytes), growAt: sourceCalls)
  assert validateFullPaged(grown.input, FullPagedTestIO(bytes: newSeq[byte](6)).scratch,
      ordinary.header,
    ordinary.manifest, policy()).error == FullPagedStreamError.ChangedInput

block retirement:
  # Repeated complete admission and owned lookup values leave no retained graph/index or callback cycles.
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let checked = ordinary.check(policy())
    assert checked.error == FullPagedStreamError.None
    assert lookupFullPaged(ordinary.io.input, checked.value, ordinary.header.root,
      key(0)).value.bytes.len == 3
  let after = getOccupiedMem()
  assert after == before
  recordArcRelease("storage_full_paged_graph", 1000, before, after)
echo "storage full paged graph PASS"
