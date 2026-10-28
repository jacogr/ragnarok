# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current 105-byte accounts retain supervisor fields and distinguish every refusal category.
import std/assertions
import std/syncio
import ../../support/state_proof_service_helpers
import ../../../src/state/proof_service as state_proof_service
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc main() =
  ## Fixed literal fields cover full-width values and the current supervisor account schema.
  let service = ServiceIndex(7)
  let key = chapterServiceKey(StateChapter(255), service)
  var bytes = newSeq[byte](105)
  for i in 1..<105:
    # Distinct source octets make field-offset or field-order errors observable.
    bytes[i] = byte(i)
  let source = @[StateEntry(key: key, value: bytes)]
  let view = serviceView(source, [key])
  let account = view.readProofAccount(service)
  assert account.error == ServiceProofError.None
  assert uint32(account.value.supervisor) == 0x24232221'u32
  assert uint32(account.value.supervisorCreated) == 0x28272625'u32
  assert uint64(account.value.balance) == 0x302f2e2d2c2b2a29'u64
  assert uint64(account.value.supervisorBalance) == 0x3837363534333231'u64
  assert uint32(account.value.parent) == 0x68676665'u32
  assert default(ProofView).readProofAccount(service).error == ServiceProofError.Uninitialized
  assert serviceView(@[], [key]).readProofAccount(service).error == ServiceProofError.AbsentValue
  assert serviceView(source, [chapterKey(StateChapter(11))]).readProofAccount(service).error ==
    ServiceProofError.MissingWitness
  assert view.readProofAccount(ServiceIndex(8)).error == ServiceProofError.MissingWitness
  for size in [0, 1, 104, 106]:
    # A valid root authenticates bytes, including malformed account extents; it does not repair them.
    let malformed = serviceView(@[StateEntry(key: key, value: newSeq[byte](size))], [key])
    assert malformed.readProofAccount(service).error == ServiceProofError.InvalidValue
  bytes[0] = 1
  assert serviceView(@[StateEntry(key: key, value: bytes)], [key]).readProofAccount(
      service).error ==
    ServiceProofError.InvalidValue
  echo "state-proof-service-account: ok"
main()
