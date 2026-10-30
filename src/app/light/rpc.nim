# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The application copies already trusted light metadata into an acyclic RPC transport without exporting proof/state ownership.
import ./head as light_head
import ../checkpoint/identity as checkpoint_identity
import ../../rpc/light_source
import ../../codec/header
import ../../state/proof/view as proof_view

proc captureLightRpcHead*(head: LightApplicationHead): RpcLightSourceResult =
  ## Preflight the entire trusted header window before copying bounded wire; RPC capture grants no new root/chain authority.
  var records: seq[RpcLightHeaderInput] = @[]
  if head.valid and head.len <= MaxRpcLightHeaders and head.proofView.len <= MaxRpcLightFacts:
    # The application owner has already checked trust, hashes, profile and links; this boundary only detaches transport ownership.
    var total = 0
    var fits = true
    for index in 0..<head.len:
      let record = head.headerAt(LightHeaderIndex(uint32(index))).value
      if record.byteLength > MaxRpcLightHeaderBytes-total: fits = false # Subtraction retains bounded addition on every accepted record.
      else: total += record.byteLength # At most eight bounded headers fit the independent transport budget.
    if fits:
      records = newSeq[RpcLightHeaderInput](head.len)
      for index in 0..<head.len:
        # Exact copied seals retain no canonical application or proof graph alias in the RPC owner.
        let record = head.headerAt(LightHeaderIndex(uint32(index))).value
        var wire = newSeq[byte](record.byteLength)
        if not record.copyHeader(wire): return captureRpcLightHead(newSeq[RpcLightHeaderInput](0),
            head.headerProfile, 0) # Refusal returns no metadata prefix.
        records[index] = RpcLightHeaderInput(blockHash: record.identity.blockHash,
          stateRoot: record.identity.stateRoot, slot: uint32(record.identity.slot), wire: wire)
  if not head.valid: return captureRpcLightHead(records, default(HeaderConfig),
      0) # Default owners cannot supply profile/root metadata.
  captureRpcLightHead(records, head.headerProfile, head.proofView.len)
