# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import std/assertions
import std/syncio
import std/envvars
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/state_proof as chain_state_proof
import ../../../src/app/chain as app_chain
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/header as codec_header
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/state/store as state_store
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/proof_service as state_proof_service
import ../../support/app_candidate_context
proc run() {.raises.} =
  ## Use the actual signed fixture's immutable selected posterior state.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i, octet in raw: wire[i] = byte(octet)
  let chain = initialized(fixture(decodeOwnedReport(wire, 2).value))
  let selected = chain.chainView.bestBlock
  let perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))
  let aggregate = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(3984),
      valueBytes: ByteLimit(16000000))
  let keys = [chapterKey(StateChapter(11)), chapterKey(StateChapter(42))]
  let proofs = generateBlockStateProofs(selected, keys, policy().trie, perProof, aggregate).value
  var queries: seq[StateProofQuery] = @[]
  for i in 0..<proofs.len:
    # Preserve exact selected query order through the block adapter.
    queries.add(proofs.queryAt(i).value)
  let verified = verifyBlockStateProofs(selected, queries, perProof, aggregate).value
  assert verified.len == 2
  for i in 0..<verified.len:
    let lookup = verified.lookupAt(i).value
    let expected = selected.value.stateSnapshot.lookup(keys[i])
    assert lookup.present == (expected.error == StateStoreError.None)
    if lookup.present: assert lookup.bytes == expected.value.bytes
  let invalid = default(GenesisResult)
  assert generateBlockStateProofs(invalid, keys, policy().trie, perProof, aggregate).error ==
      StateProofError.Uninitialized
  assert verifyBlockStateProofs(invalid, queries, perProof, aggregate).error ==
      StateProofError.Uninitialized
  assert verifyBlockStateProofs(unavailableGenesis(), queries, perProof, aggregate).error ==
      StateProofError.Uninitialized
  echo "chain-state-proof-batch: ok"
try:
  run()
except:
  quit(2) # Missing or malformed signed fixture data must fail the suite.
