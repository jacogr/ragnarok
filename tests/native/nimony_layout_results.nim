# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated failure/default result and inactive metadata reads must reject with their supported
## contracts.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import std/syncio
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
# Native refusals exist only in the test observer, never the production primitive library.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
let useDefault = paramStr(2) == "default"
let key = default(StateKey)
var invalid = default(array[64, byte])
invalid[0] = 255
fail(1)
case paramStr(1)
of "key-limit":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[StateKey]) else: hashedServiceKey(
      ServiceIndex(0), [1'u8], ByteLimit(0))
  echo array[31, byte](parsed.value)[0]
of "leaf-limit":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[EncodedStateNode]) else: encodeStateLeaf(
      key, [1'u8], ByteLimit(0))
  echo array[64, byte](parsed.value)[0]
of "node-info":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[StateNodeRead]) else: decodeStateNode([])
  echo ord(parsed.value.node.kind)
of "node-consumed":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[StateNodeRead]) else: decodeStateNode([])
  echo parsed.value.consumed
of "metadata-invalid":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[EncodedStateNode]) else: encodeStateNode(
      embeddedNodeInfo(key, EmbeddedLength(33), default(array[32, byte])))
  echo array[64, byte](parsed.value)[0]
of "hash-invalid":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[StateNodeHash]) else: hashStateNode(
      EncodedStateNode(invalid))
  echo array[32, byte](parsed.value)[0]
of "key-backend":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[StateKey]) else: hashedServiceKey(
      ServiceIndex(0), [], ByteLimit(0))
  echo array[31, byte](parsed.value)[0]
of "leaf-backend":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[EncodedStateNode]) else: encodeStateLeaf(
      key, newSeq[byte](33), ByteLimit(33))
  echo array[64, byte](parsed.value)[0]
of "hash-backend":
  # A failed/default operation cannot authorize a fixed value, metadata or consumed progress.
  let parsed = if useDefault: default(StateLayoutResult[StateNodeHash]) else: hashStateNode(default(EncodedStateNode))
  echo array[32, byte](parsed.value)[0]
of "Branch-embeddedKey":
  # This selected Branch alternative must not expose its inactive embeddedKey field.
  let node = branchNodeInfo(default(LeftChildCommitment), default(StateNodeHash))
  echo array[31, byte](node.embeddedKey)[0]
of "Branch-length":
  # This selected Branch alternative must not expose its inactive length field.
  let node = branchNodeInfo(default(LeftChildCommitment), default(StateNodeHash))
  echo uint8(node.length)
of "Branch-embedded":
  # This selected Branch alternative must not expose its inactive embedded field.
  let node = branchNodeInfo(default(LeftChildCommitment), default(StateNodeHash))
  echo node.embedded[0]
of "Branch-hashedKey":
  # This selected Branch alternative must not expose its inactive hashedKey field.
  let node = branchNodeInfo(default(LeftChildCommitment), default(StateNodeHash))
  echo array[31, byte](node.hashedKey)[0]
of "Branch-valueHash":
  # This selected Branch alternative must not expose its inactive valueHash field.
  let node = branchNodeInfo(default(LeftChildCommitment), default(StateNodeHash))
  echo array[32, byte](node.valueHash)[0]
of "EmbeddedLeaf-left":
  # This selected EmbeddedLeaf alternative must not expose its inactive left field.
  let node = embeddedNodeInfo(key, EmbeddedLength(0), default(array[32, byte]))
  echo array[32, byte](node.left)[0]
of "EmbeddedLeaf-right":
  # This selected EmbeddedLeaf alternative must not expose its inactive right field.
  let node = embeddedNodeInfo(key, EmbeddedLength(0), default(array[32, byte]))
  echo array[32, byte](node.right)[0]
of "EmbeddedLeaf-hashedKey":
  # This selected EmbeddedLeaf alternative must not expose its inactive hashedKey field.
  let node = embeddedNodeInfo(key, EmbeddedLength(0), default(array[32, byte]))
  echo array[31, byte](node.hashedKey)[0]
of "EmbeddedLeaf-valueHash":
  # This selected EmbeddedLeaf alternative must not expose its inactive valueHash field.
  let node = embeddedNodeInfo(key, EmbeddedLength(0), default(array[32, byte]))
  echo array[32, byte](node.valueHash)[0]
of "HashedLeaf-left":
  # This selected HashedLeaf alternative must not expose its inactive left field.
  let node = hashedNodeInfo(key, default(StateValueHash))
  echo array[32, byte](node.left)[0]
of "HashedLeaf-right":
  # This selected HashedLeaf alternative must not expose its inactive right field.
  let node = hashedNodeInfo(key, default(StateValueHash))
  echo array[32, byte](node.right)[0]
of "HashedLeaf-embeddedKey":
  # This selected HashedLeaf alternative must not expose its inactive embeddedKey field.
  let node = hashedNodeInfo(key, default(StateValueHash))
  echo array[31, byte](node.embeddedKey)[0]
of "HashedLeaf-length":
  # This selected HashedLeaf alternative must not expose its inactive length field.
  let node = hashedNodeInfo(key, default(StateValueHash))
  echo uint8(node.length)
of "HashedLeaf-embedded":
  # This selected HashedLeaf alternative must not expose its inactive embedded field.
  let node = hashedNodeInfo(key, default(StateValueHash))
  echo node.embedded[0]
else:
  # Unknown selectors are harness mistakes, never successful safety evidence.
  quit(2)
