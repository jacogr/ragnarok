# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Storage reads require both same-root account and storage evidence, including present-empty bytes.
import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/proof/[service as proof_service, view as proof_view]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie, service_values as state_service_values]
proc main() =
  ## Empty logical keys and values remain distinct from missing witnesses and proven absence.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let limits = ServiceEntryLimits(keyBytes: ByteLimit(3), valueBytes: ByteLimit(3))
  for raw in [@[byte 1, 2, 3], newSeq[byte](0)]:
    for payload in [@[byte 9, 8, 7], newSeq[byte](0)]:
      # Each result retains its authenticated identity while callers mutate their copied bytes.
      let row = serviceStorageEntry(service, raw, payload, limits).value
      let view = serviceView(@[account, row], [account.key, row.key])
      let found = view.readProofStorage(service, raw, limits)
      assert found.error == ServiceProofError.None
      assert found.value.bytes == payload
      assert array[32, byte](found.value.root) == array[32, byte](view.root)
      assert serviceView(@[account, row], [account.key]).readProofStorage(service, raw,
          limits).error == ServiceProofError.MissingWitness
      assert serviceView(@[account], [account.key, row.key]).readProofStorage(service, raw,
          limits).error == ServiceProofError.AbsentValue
      assert serviceView(@[row], [account.key, row.key]).readProofStorage(service, raw,
          limits).error == ServiceProofError.AbsentValue
      if payload.len != 0:
        # Caller output policy is enforced on retained length before exposing the immutable lookup.
        assert view.readProofStorage(service, raw, ServiceEntryLimits(keyBytes: ByteLimit(3),
            valueBytes: ByteLimit(2))).error == ServiceProofError.LimitExceeded
  assert default(ProofView).readProofStorage(service, [], limits).error ==
      ServiceProofError.Uninitialized
  assert default(ProofView).readProofStorage(service, [byte 1, 2, 3, 4], limits).error ==
      ServiceProofError.LimitExceeded
  echo "state-proof-service-storage: ok"
main()
