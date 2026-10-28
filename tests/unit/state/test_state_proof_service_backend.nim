# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every actual primitive prefix fails without fabricated typed values or partial verified views.
import std/assertions
import std/syncio
import ../../support/state_proof_service_helpers
import ../../../src/state/proof_service as state_proof_service
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/crypto/primitives as crypto_primitives
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the maintained primitive observer and optionally refuse every hash attempt.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse the next primitive after exactly this many successful calls.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Measure actual backend attempts rather than predicting them from loop shapes.
proc read(view: ProofView, hash: ServicePreimageHash, kind: int): ServiceProofResult[
    VerifiedStateLookup] =
  ## Exercise each public composed content read with stable immutable input evidence.
  case kind
  of 0: view.readProofStorage(ServiceIndex(7), [byte 1], ServiceEntryLimits(keyBytes: ByteLimit(1),
      valueBytes: ByteLimit(3)))
  of 1: view.readProofPreimage(ServiceIndex(7), hash, ByteLimit(3))
  of 2: view.readProofHistoricalPreimage(ServiceIndex(7), hash, RequestSlot(4), ByteLimit(3))
  else: view.readProofCode(ServiceIndex(7), RequestSlot(4), ByteLimit(3))
proc main() =
  ## Prepare all authentic state before injecting real primitive failures.
  let service = ServiceIndex(7)
  let bytes = @[byte 1, 2, 3]
  let digest = array[32, byte](blake2b256(bytes).value)
  let hash = ServicePreimageHash(digest)
  let account = serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(digest)),
      ByteLimit(105)).value
  let blob = servicePreimageEntry(service, hash, bytes, ServiceEntryLimits(keyBytes: ByteLimit(32),
      valueBytes: ByteLimit(3))).value
  let storage = serviceStorageEntry(service, [byte 1], bytes, ServiceEntryLimits(
      keyBytes: ByteLimit(1), valueBytes: ByteLimit(3))).value
  let history = serviceRequestEntry(service, hash, RequestLength(3), availableHistory(RequestSlot(
      4)), RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))).value
  let view = serviceView(@[account, blob, storage, history], [account.key, blob.key, storage.key, history.key])
  let a = planProofStorage(service, [byte 1], ByteLimit(1), ElementLimit(2)).value
  let b = planProofHistorical(service, hash, RequestLength(3), ElementLimit(3)).value
  let plan = mergeProofPlans(a, b, ElementLimit(4)).value
  let queries = exportProofQueries(view, viewLimits).value
  let wire = encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(4096)).value
  for kind in 0..<4:
    # Fail after each successful primitive prefix, including content hashing and final request-key derivation.
    fail(0)
    assert read(view, hash, kind).error == ServiceProofError.None
    let count = calls()
    assert count == (if kind == 0: 1 else: (if kind == 1: 2 else: 3))
    for prefix in 0..<int(count):
      failAfter(cint(prefix))
      assert read(view, hash, kind).error == ServiceProofError.BackendFailure
      assert calls() == cint(prefix+1)
  fail(0)
  assert verifyServiceProofs(plan, queries, view.root, proofLimits, batchLimits,
      viewLimits).error == ServiceProofError.None
  let verificationCalls = calls()
  assert verificationCalls > 4
  for prefix in 0..<int(verificationCalls):
    # A later proof failure returns no earlier verified subset.
    failAfter(cint(prefix))
    let refused = verifyServiceProofs(plan, queries, view.root, proofLimits, batchLimits, viewLimits)
    assert refused.error == ServiceProofError.ProofFailure and refused.proofError ==
        StateProofError.BackendFailure
    assert calls() == cint(prefix+1)
  fail(1)
  assert view.readProofAccount(service).error == ServiceProofError.None
  assert planProofAccount(service, ElementLimit(1)).error == ServiceProofError.None
  assert mergeProofPlans(a, b, ElementLimit(4)).error == ServiceProofError.None
  assert view.matchesProofPlan(plan).value
  assert encodeServiceProofs(view, plan, viewLimits, proofLimits, ByteLimit(4096)).error ==
      ServiceProofError.None
  assert calls() == 0
  assert planProofStorage(service, [byte 1], ByteLimit(0), ElementLimit(2)).error ==
      ServiceProofError.LimitExceeded
  assert planProofHistorical(service, hash, RequestLength(3), ElementLimit(2)).error ==
      ServiceProofError.LimitExceeded
  assert view.readProofRequest(service, hash, RequestLength(high(uint32))).error ==
      ServiceProofError.InvalidInput
  assert calls() == 0
  var short = batchLimits
  short.valueBytes = ByteLimit(0)
  let refused = decodeServiceProofs(wire, plan, view.root, viewLimits, proofLimits, short,
      ByteLimit(4096))
  assert refused.error == ServiceProofError.ProofFailure and refused.proofError ==
      StateProofError.LimitExceeded
  assert calls() == 0
  fail(0)
  assert read(view, hash, 3).value.bytes == bytes
  echo "state-proof-service-backend: ok"
main()
