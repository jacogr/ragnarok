# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default reconstruction reasons cannot bypass selected-failure guards.
import std/[assertions, cmdline, syncio]
import ../support/storage_samples
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/full/state_trie as full_state_trie
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## The valid diagnostic control creates a real native backend refusal.
proc main() =
  ## Select default or actual refused restoration dynamically under one native profile.
  fail(0)
  let limits = storageLimits()
  var repository = newNodeRepository(limits)
  let view = repository.publish(repository.snapshot.value,
    exportFullTrie(storageTrie(), limits.codec.records).value).value
  fail(1)
  let empty = default(RepositoryResult[FullStateTrie])
  let selected = if paramStr(2) == "default": empty
    else: restoreFullTrie(view, view.commitment.root, FullStateTrieLimits(trie: limits.codec.trie))
  echo ord(selected.trieError)
  fail(0)
  discard repository.close
main()
