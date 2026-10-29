# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/proof/[service as proof_service, view as proof_view]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie]
proc main() =
  ## Transport selectors and witnesses never grant authority without the independently chosen root.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(balance: AccountBalance(99)),
      ByteLimit(105)).value
  let plan = planProofAccount(service, ElementLimit(1)).value
  let view = serviceView(@[account], [account.key])
  let root = view.root
  let queries = exportProofQueries(view, viewLimits).value
  let verified = verifyServiceProofs(plan, queries, root, proofLimits, batchLimits, viewLimits)
  assert verified.error == ServiceProofError.None and verified.value.matchesProofPlan(plan).value
  assert uint64(verified.value.readProofAccount(service).value.balance) == 99
  assert verifyServiceProofs(plan, [], root, proofLimits, batchLimits, viewLimits).error ==
      ServiceProofError.InvalidInput
  var wrong = queries
  wrong[0].key = chapterKey(StateChapter(11))
  assert verifyServiceProofs(plan, wrong, root, proofLimits, batchLimits, viewLimits).error ==
      ServiceProofError.InvalidInput
  let foreign = verifyServiceProofs(plan, queries, default(StateRoot), proofLimits, batchLimits, viewLimits)
  assert foreign.error == ServiceProofError.ProofFailure and foreign.proofError ==
      StateProofError.RootMismatch
  let missing = default(ServiceProofPlan)
  assert verifyServiceProofs(missing, queries, root, proofLimits, batchLimits, viewLimits).error ==
      ServiceProofError.Uninitialized
  assert not serviceView(@[account], [account.key, chapterKey(StateChapter(11))]).matchesProofPlan(plan).value
  assert not serviceView(@[account], [chapterKey(StateChapter(11))]).matchesProofPlan(plan).value
  echo "state-proof-service-verification: ok"
main()
