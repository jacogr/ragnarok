# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## End-to-end service transport uses genuine successive executed posterior heads rather than header parent roots.
import std/[assertions, syncio, envvars]
import ../../../src/chain/[genesis, state_proof]
import ../../../src/codec/[report_owned, header, bounded]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    accounts as state_accounts]
import ../../../src/state/[store, trie_proof]
import ../../../src/state/proof/[view as proof_view, service as proof_service]
import ../../support/[application_candidate_context, application_download_chain]
proc main() {.raises.} =
  ## Every child is signed and executed from its actual predecessor by the maintained independent fixture.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i, octet in raw: wire[i] = byte(octet)
  let sequence = chainFixture(decodeOwnedReport(wire, 2).value, 3)
  let perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))
  let aggregate = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(3984),
      valueBytes: ByteLimit(16000000))
  let budget = ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(16000000))
  for index, head in sequence.heads:
    # Capture each exact original sealed header and its retained posterior complete map.
    var headerBytes = newSeq[byte](head.header.headerInfo.value.consumed)
    assert encodeOwnedHeader(head.header, headerBytes).error == HeaderError.None
    let selected = captureBlockSnapshot(headerBytes, head.stateSnapshot, head.chainParameters)
    assert selected.error == GenesisError.None and head.serviceCount > 0
    let service = head.serviceAt(ServiceListIndex(0))
    let plan = planProofAccount(service, ElementLimit(1)).value
    let proofs = generateBlockServiceProofs(selected, plan, policy().trie, perProof,
        aggregate).value
    var queries: seq[StateProofQuery] = @[]
    for i in 0..<proofs.len: queries.add(proofs.queryAt(i).value)
    let verified = verifyServiceProofs(plan, queries, head.stateRoot, perProof, aggregate, budget).value
    let encoded = encodeServiceProofs(verified, plan, budget, perProof, ByteLimit(1000000)).value
    let received = decodeServiceProofs(encoded, plan, selected.value.stateRoot, budget, perProof,
        aggregate, ByteLimit(1000000)).value
    let expected = decodeServiceMetadata(head.stateSnapshot.lookup(plan.keyAt(0).value).value.bytes,
        ByteLimit(105)).value.metadata
    assert uint64(received.readProofAccount(service).value.balance) == uint64(expected.balance)
    assert uint32(received.readProofAccount(service).value.supervisor) == uint32(
        expected.supervisor)
    if index > 0:
      # Neither a parent's root in the child's header nor the original seed root authenticates posterior evidence.
      let parent = decodeServiceProofs(encoded, plan, head.priorStateRoot, budget, perProof,
          aggregate, ByteLimit(1000000))
      assert parent.error == ServiceProofError.ProofFailure and parent.proofError ==
          StateProofError.RootMismatch
      let seed = decodeServiceProofs(encoded, plan, sequence.heads[0].stateRoot, budget, perProof,
          aggregate, ByteLimit(1000000))
      assert seed.error == ServiceProofError.ProofFailure and seed.proofError ==
          StateProofError.RootMismatch
  echo "chain-state-service-successive: ok"
try:
  main()
except:
  quit(2) # Signed-fixture preparation or transport failures must not become skipped execution evidence.
