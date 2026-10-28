# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_local_ancestors_arc_release"}

## Retained canonical parent capture excludes the selected head and separated finality, with atomic exact quotas.
import std/assertions
import std/syncio
import std/envvars
import ../../../src/app/ancestor_inputs as app_ancestor_inputs
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../support/app_download_chain
import ../../support/app_candidate_context
import ../../support/testing_arc_evidence

proc captured(head: BlockSnapshot): BlockSnapshotResult =
  ## Rebuild a structural snapshot owner from the exact independently composed map and sealed bytes.
  var wire = newSeq[byte](head.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(head.header, wire).error == HeaderError.None
  captureBlockSnapshot(wire, head.stateSnapshot, head.chainParameters)

proc cycle(view: ChainView, config: HeaderConfig, bytes: uint64) =
  ## Exact and refused captures release copied sequence containers and immutable header owners.
  let loaded = prependLocalAncestors(view, @[], config, ElementLimit(7), ByteLimit(bytes))
  assert loaded.error == AncestorInputError.None and loaded.headers.len == 7
  var changed = loaded.headers
  changed[0] = default(OwnedHeader)
  assert loaded.headers[0].headerInfo.error == HeaderError.None
  assert prependLocalAncestors(view, @[], config, ElementLimit(6), ByteLimit(bytes)).error ==
      AncestorInputError.LimitExceeded
  assert prependLocalAncestors(view, @[], config, ElementLimit(7), ByteLimit(bytes - 1)).error ==
      AncestorInputError.LimitExceeded

proc main() {.raises.} =
  ## Genuine composed heads supply independent expected identity/order and a window with an evicted finalized anchor.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(wire, 2).value, 8)
  var view = genesisView(captured(context.heads[0]))
  let finalized = view.finalizeView(context.heads[0].blockHash)
  assert finalized.error == ViewFinalizeError.None
  view = finalized.value
  for index in 1..<context.heads.len:
    let next = view.advanceView(captured(context.heads[index]))
    assert next.error == ViewAdvanceError.None
    view = next.value
  let config = preparationLimits().reporting.reports.ancestors.header
  var bytes = 0'u64
  for index in 1..7: bytes += uint64(context.heads[index].header.headerInfo.value.consumed)
  let loaded = prependLocalAncestors(view, @[], config, ElementLimit(7), ByteLimit(bytes))
  assert loaded.error == AncestorInputError.None and loaded.headers.len == 7
  for index, owner in loaded.headers:
    assert array[32, byte](owner.headerInfo.value.unsigned.parent) == array[32, byte](context.heads[
        7 - index].header.headerInfo.value.unsigned.parent)
  let suffix = @[context.heads[0].header]
  let extended = prependLocalAncestors(view, suffix, config, ElementLimit(8), ByteLimit(high(uint64)))
  assert extended.error == AncestorInputError.None and extended.headers.len == 8
  let empty = default(ChainView)
  assert prependLocalAncestors(empty, @[], config, ElementLimit(8), ByteLimit(bytes)).error ==
      AncestorInputError.InvalidHistory
  assert prependLocalAncestors(genesisView(captured(context.heads[0])), @[], config, ElementLimit(
      0), ByteLimit(0)).headers.len == 0
  assert prependLocalAncestors(view, @[default(OwnedHeader)], config, ElementLimit(8), ByteLimit(
      high(uint64))).error == AncestorInputError.HeaderFailure
  var small = config
  small.maxBytes = ByteLimit(1)
  assert prependLocalAncestors(view, @[], small, ElementLimit(7), ByteLimit(bytes)).error ==
      AncestorInputError.LimitExceeded
  cycle(view, config, bytes)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(view, config, bytes) # Repeated success/refusal retains no capture owners.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_local_ancestors", 1000, before, after)
  echo "PASS application local ancestors: exact rolling order, suffix bounds, excluded finality and ARC release"
try:
  main() # Every fixture or assertion failure remains a failed native verdict.
except:
  quit(2)
