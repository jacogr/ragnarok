# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Finite light runtime retention, request, native IO and header policies remain independent.
import ./[head as light_head, store as light_store]
import ../proof/query as proof_query
import ./proof_import as light_proof_import
import ../../state/trie_proof
import ../../state/proof/view as proof_view
import ../../state/paged/proof_view as paged_proof_view
import ../../storage/paged/[stream as paged_stream, codec as paged_codec]
import ../../storage/database_identity
import ../../codec/[bounded, header]
import ../../codec/state/trie as state_trie
from ../../rpc/protocol import MaxRpcProofBytes
from ../../rpc/proof_requests import MaxRpcProofKeys, MaxRpcProofImportBytes

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
