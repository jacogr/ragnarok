# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Query admission binds exact selected identity and refuses each policy before proof work.
import std/[assertions, syncio]
import ../../support/proof_query_context
import ../../../src/app/proof/query as proof_query
import ../../../src/chain/genesis
import ../../../src/state/proof/service as proof_service
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc main() {.raises.} =
  ## The real source has current metadata and a complete immutable commitment.
  let selected = querySelection(queryContext())
  let service = selected.value.serviceAt(ServiceListIndex(0))
  let plan = planProofAccount(service, ElementLimit(1)).value
  let limits = queryLimits()
  let query = captureProofQuery(selected, plan, limits).value
  assert query.valid
  assert array[32, byte](query.blockHash) == array[32, byte](selected.value.blockHash)
  assert array[32, byte](query.stateRoot) == array[32, byte](selected.value.stateRoot)
  let expected = selected.value.stateSnapshot.commitment.nodes + uint64(
      selected.value.stateSnapshot.commitment.entries)+250
  assert uint64(query.estimatedHashes) == expected
  var exact = limits
  exact.hashes = ProofHashLimit(expected)
  assert captureProofQuery(selected, plan, exact).error == ProofQueryError.None
  exact.hashes = ProofHashLimit(expected-1)
  assert captureProofQuery(selected, plan, exact).error == ProofQueryError.LimitExceeded
  for mode in 0..<4:
    # Each short dimension refuses independently, without changing the prior valid owner.
    var short = limits
    case mode
    of 0: short.aggregate.items = ElementLimit(0)
    of 1: short.view.items = ElementLimit(0)
    of 2: short.map.items = ElementLimit(0)
    else: short.wireBytes = ByteLimit(52)
    assert captureProofQuery(selected, plan, short).error == ProofQueryError.LimitExceeded
  let invalid = default(GenesisResult)
  assert captureProofQuery(invalid, plan, limits).error == ProofQueryError.InvalidSelection
  let missing = default(ServiceProofPlan)
  assert captureProofQuery(selected, missing, limits).error == ProofQueryError.InvalidPlan
  assert not default(ProofQuery).valid
  echo "application-proof-query-capture: ok"
try:
  main()
except:
  quit(2) # Genuine fixture/selection failures are failed native verification.
