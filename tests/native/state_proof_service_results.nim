# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime failures forbid typed reads, plans and responses from yielding failed/default payloads.
import std/[assertions, cmdline]
import ../support/proof_service_helpers
import ../../src/state/[proof_service, proof_view, trie_proof]
import ../../src/codec/[bounded, state_accounts, state_layout, state_trie, state_service_values, state_requests]
proc extract[T](outcome: ServiceProofResult[T]) =
  ## Runtime result selection is mandatory even for default and failed generic payloads.
  discard outcome.value
proc reason[T](outcome: ServiceProofResult[T]) =
  ## Only an actual proof-failure alternative owns a nested proof reason.
  discard outcome.proofError
proc main() =
  ## Genuine verified sources provide positive controls before a dynamic negative case is selected.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let view = serviceView(@[account], [account.key])
  let plan = planProofAccount(service, ElementLimit(1)).value
  let queries = exportProofQueries(view, viewLimits).value
  let wire = encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(4096)).value
  let absent = serviceView(@[], [account.key])
  let unknown = serviceView(@[account], [chapterKey(StateChapter(11))])
  let malformed = serviceView(@[StateEntry(key: account.key, value: @[])], [account.key])
  case paramStr(1)
  of "default": extract(default(ServiceProofResult[ServiceMetadata])) # No initialized account payload.
  of "missing": extract(unknown.readProofAccount(service)) # Unknown is never a default account.
  of "absent": extract(absent.readProofAccount(service)) # Proven absence still owns no metadata.
  of "malformed": extract(malformed.readProofAccount(service)) # Authenticated malformed state remains failed.
  of "length": extract(view.readProofRequest(service, default(ServicePreimageHash), RequestLength(
      high(uint32)))) # Reserved domain.
  of "plan": extract(planProofAccount(service, ElementLimit(0))) # No successful plan after count refusal.
  of "index": extract(plan.keyAt(-1)) # No fabricated key from an invalid ordinal.
  of "verify": extract(verifyServiceProofs(plan, queries, default(StateRoot), proofLimits,
      batchLimits, viewLimits)) # Foreign root.
  of "encode": extract(encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(
      1))) # No partial envelope.
  of "decode": extract(decodeServiceProofs([], plan, view.root, viewLimits, proofLimits,
      batchLimits, ByteLimit(4096))) # No decoded prefix.
  of "reason": reason(view.readProofAccount(service)) # Successful reads own no nested failure payload.
  else:
    # Positive extraction, nested failure reason and encoding/decoding share the same guarded accessors.
    extract(view.readProofAccount(service))
    extract(planProofAccount(service, ElementLimit(1)))
    extract(decodeServiceProofs(wire, plan, view.root, viewLimits, proofLimits, batchLimits,
        ByteLimit(4096)))
    reason(verifyServiceProofs(plan, queries, default(StateRoot), proofLimits, batchLimits, viewLimits))
main()
