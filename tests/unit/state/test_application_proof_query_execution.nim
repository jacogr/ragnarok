# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Request execution emits independently authenticated bounded bytes with explicit selected identity.
import std/[assertions, syncio]
import ../../support/proof_query_context
import ../../../src/app/proof/query as proof_query
import ../../../src/chain/genesis
import ../../../src/state/proof/[service as proof_service, view as proof_view]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc main() {.raises.} =
  ## The receiving plan/root are retained independently of the produced response.
  let selected = querySelection(queryContext())
  let service = selected.value.serviceAt(ServiceListIndex(0))
  let plan = planProofAccount(service, ElementLimit(1)).value
  let limits = queryLimits()
  let query = captureProofQuery(selected, plan, limits).value
  let response = executeProofQuery(query).value
  assert response.valid and response.byteLength > 53
  assert array[32, byte](response.blockHash) == array[32, byte](selected.value.blockHash)
  assert array[32, byte](response.stateRoot) == array[32, byte](selected.value.stateRoot)
  let wire = response.bytes(limits.wireBytes).value
  let received = decodeServiceProofs(wire, plan, selected.value.stateRoot, limits.view,
      limits.proof, limits.aggregate, limits.wireBytes)
  assert received.error == ServiceProofError.None
  assert received.value.readProofAccount(service).error == ServiceProofError.None
  assert response.bytes(ByteLimit(response.byteLength-1)).error == ProofQueryError.LimitExceeded
  var copied = response.bytes(limits.wireBytes).value
  copied[0] = 0
  assert response.bytes(limits.wireBytes).value == wire
  var short = limits
  short.wireBytes = ByteLimit(53)
  let encoded = executeProofQuery(captureProofQuery(selected, plan, short).value)
  assert encoded.error == ProofQueryError.ServiceFailure and encoded.serviceError ==
      ServiceProofError.LimitExceeded
  short = limits
  short.map.perValue = ByteLimit(0)
  let generated = executeProofQuery(captureProofQuery(selected, plan, short).value)
  assert generated.error == ProofQueryError.ProofFailure and generated.proofError ==
      StateProofError.LimitExceeded
  let invalid = default(ProofQuery)
  assert executeProofQuery(invalid).error == ProofQueryError.Uninitialized
  assert default(ProofResponse).bytes(ByteLimit(0)).error == ProofQueryError.Uninitialized
  echo "application-proof-query-execution: ok"
try:
  main()
except:
  quit(2) # Missing genuine fixture or refused selection cannot become a passing zero-work test.
