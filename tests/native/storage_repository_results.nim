# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic default/refused repository accesses require exact optimized public contracts.
import std/[assertions, cmdline, syncio]
import ../support/storage_samples
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/codec/state/[layout as state_layout, trie as state_trie]

proc main() =
  ## Genuine active read controls run through the same native profile as refused accesses.
  let member = paramStr(1)
  let origin = paramStr(2)
  let limits = storageLimits()
  var repository = newNodeRepository(limits)
  var batch = exportFullTrie(storageTrie(), limits.codec.records).value
  let active = repository.publish(repository.snapshot.value, batch).value
  if member == "result":
    let empty = default(RepositoryResult[RepositoryView])
    discard repository.close
    let selected = if origin == "default": empty
      elif origin == "failed": repository.snapshot
      else: RepositoryResult[RepositoryView]() # Valid result control comes from a separate active owner below.
    if origin == "valid":
      var fresh = newNodeRepository(limits)
      echo fresh.snapshot.value.storedNodes
      discard fresh.close
    else: echo selected.value.storedNodes
  elif member == "take":
    var selected = if origin == "default": default(RepositoryResult[TrieRecord])
      elif origin == "failed": active.lookupNode(default(StateNodeHash))
      else: active.lookupNode(StateNodeHash(array[32, byte](active.commitment.root)))
    if origin == "moved": discard selected.takeValue # Consumption must revoke authority before a second transfer.
    echo selected.takeValue.payload.len # Default, failed and consumed results require the same checked success guard.
  elif member == "record":
    let empty = default(RepositoryResult[TrieRecord])
    let selected = if origin == "default": empty
      elif origin == "failed": active.lookupNode(default(StateNodeHash))
      else: active.lookupNode(StateNodeHash(array[32, byte](active.commitment.root)))
    echo selected.value.payload.len
  elif member == "reason":
    batch.base = active.commitment.root
    batch.records[0].payload[0] = 99
    let empty = default(RepositoryResult[RepositoryView])
    let selected = if origin == "default": empty else: repository.publish(active, batch)
    echo ord(selected.recordError)
  else:
    let selected = if origin == "default": default(RepositoryView) else: active
    if member == "metadata": echo selected.commitment.entries
    elif member == "generation": echo uint64(selected.generation)
    else: echo selected.storedNodes
  discard repository.close
main()
