# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted-root refusal and narrower policies precede reconstruction crypto; backend refusal is typed.
# @@Verification={"arc": "storage_restoration_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[node_repository, node_records, full_state_trie]
import ../../../src/codec/[state_trie, bounded]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse only after the original repository and complete graph are valid.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe that trust and policy refusal never reconstruct a root.
proc cycle() =
  ## Restored tries and retained views survive source close and failed reconstruction attempts.
  fail(0)
  let limits = storageLimits()
  var repository = newNodeRepository(limits)
  let original = storageTrie()
  let view = repository.publish(repository.snapshot.value,
    exportFullTrie(original, limits.codec.records).value).value
  let root = view.commitment.root
  let policy = FullStateTrieLimits(trie: limits.codec.trie)
  fail(1)
  assert restoreFullTrie(view, default(StateRoot), policy).error == RepositoryError.RootMismatch
  assert calls() == 0
  var short = policy
  short.trie.perValue = ByteLimit(0)
  assert restoreFullTrie(view, root, short).error == RepositoryError.LimitExceeded and calls() == 0
  let refused = restoreFullTrie(view, root, policy)
  assert refused.error == RepositoryError.TrieFailure and refused.trieError ==
      TrieError.BackendFailure
  assert calls() == 1
  fail(0)
  let restored = restoreFullTrie(view, root, policy).value
  assert repository.close == RepositoryError.None
  assert restored.lookup(storageKey(0)).value.bytes == @[7'u8]
  assert restored.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Delete)]).error ==
      TrieError.LimitExceeded
  assert restoreFullTrie(view, root, policy).value.lookup(storageKey(128)).value.bytes == @[9'u8]
for i in 0..<25: cycle() # Warm reconstruction and typed refusal paths.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # All accepted and partially reconstructed owners retire independently.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_restoration_failure", 1000, before, after)
echo "PASS storage restoration failures: trusted roots, narrower ceilings, backend refusal and ARC"
