# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Finite light runtime retention, request, native IO and header policies remain independent.
import ./light_head as app_light_head
import ./light_store as app_light_store
import ./proof_query as app_proof_query
import ./light_proof_import as app_light_proof_import
import ../state/trie_proof as state_trie_proof
import ../state/proof_view as state_proof_view
import ../state/paged_proof_view as state_paged_proof_view
import ../storage/paged_stream as storage_paged_stream
import ../storage/paged_codec as storage_paged_codec
import ../storage/database_identity as storage_database_identity
import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ../codec/state_trie as codec_state_trie
from ../rpc/protocol as rpc_protocol import MaxRpcProofBytes
from ../rpc/proof_requests as rpc_proof_requests import MaxRpcProofKeys, MaxRpcProofImportBytes

type LightRuntimePolicy* = object ## Resident retained knowledge and each incoming/outgoing request use separate finite budgets.
  head*: LightHeadLimits
  store*: LightPagedLimits
  query*: ProofQueryLimits
  ingestion*: LightProofImportLimits
proc lightRuntimePolicy*(chain: StorageChainId, root: StateRoot,
    profile: HeaderConfig): LightRuntimePolicy =
  ## Caller-selected configured C/V/E geometry and independently trusted root never come from a partial mapping or native directory.
  let valueBytes = ByteLimit(4194304)
  let calls = ElementLimit(1000000)
  let ioBytes = ByteLimit(1073741824)
  let work = PagedWorkLimits(ioCalls: calls, producerCalls: calls, pageHashes: calls,
    proofs: calls, nodes: calls, readBytes: ioBytes, writeBytes: ioBytes, valueBytes: ioBytes)
  result = default(LightRuntimePolicy)
  result.head = LightHeadLimits(header: profile, headers: ElementLimit(3), headerBytes: ByteLimit(1048576),
    view: ProofViewLimits(items: ElementLimit(256), valueBytes: valueBytes))
  result.store.head = result.head
  result.store.native.chain = chain
  result.store.native.root = root
  result.store.native.limits = PagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(256),
      bytes: ByteLimit(268435456)),
    workingBytes: ByteLimit(33554432), cachePages: ElementLimit(1), contextBytes: ByteLimit(
        4194304), work: work)
  result.store.native.limits.proof.nodes = ElementLimit(249)
  result.store.native.limits.proof.valueBytes = valueBytes
  result.store.proofs = PagedProofViewLimits(proof: StateProofLimits(nodes: ElementLimit(249),
      valueBytes: valueBytes),
    batch: StateProofBatchLimits(items: ElementLimit(256), nodes: ElementLimit(63744),
        valueBytes: valueBytes),
    view: result.head.view, work: work)
  result.store.inventory = work
  result.store.contextBytes = ByteLimit(1048576)
  result.query = ProofQueryLimits(proof: result.store.proofs.proof,
    aggregate: StateProofBatchLimits(items: ElementLimit(MaxRpcProofKeys), nodes: ElementLimit(
        3984), valueBytes: valueBytes),
    view: ProofViewLimits(items: ElementLimit(MaxRpcProofKeys), valueBytes: valueBytes),
    wireBytes: ByteLimit(MaxRpcProofBytes), hashes: ProofHashLimit(0))
  result.ingestion = LightProofImportLimits(proof: result.query.proof,
    aggregate: result.query.aggregate,
    view: result.query.view, wireBytes: ByteLimit(MaxRpcProofImportBytes), hashes: ElementLimit(8192))
