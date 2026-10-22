# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed configured state supplies immutable selected heads for proof-query integration tests.
import std/[assertions, envvars, syncio]
import ../../src/codec/[report_owned, bounded]
import ../../src/chain/[genesis, provider]
import ../../src/app/[proof_query, chain]
import ../../src/state/[trie_proof, proof_view]
import ./application_candidate_context
proc queryContext*(): SeedFixture {.raises.} =
  ## Missing or malformed pinned input must fail, never fabricate a selected empty root.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i, octet in raw: wire[i] = byte(octet)
  fixture(decodeOwnedReport(wire, 2).value)
proc querySelection*(context: SeedFixture): BlockSnapshotResult {.raises.} =
  ## Retain the real complete head after temporary application initialization has retired.
  let chain = initialized(context)
  chain.chainView.bestBlock
proc queryLimits*(): ProofQueryLimits =
  ## Test policies are explicit, including conservative complete-map hash work.
  ProofQueryLimits(map: policy().trie,
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000)),
    aggregate: StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(3984),
        valueBytes: ByteLimit(16000000)),
    view: ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(16000000)),
    wireBytes: ByteLimit(20000000), hashes: ProofHashLimit(10000000))
