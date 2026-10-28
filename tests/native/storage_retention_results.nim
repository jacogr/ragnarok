# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic result/count misuse requires optimized guards alongside genuine public controls.
import std/assertions
import std/cmdline
import std/syncio
import ../support/storage_samples
import ../../src/storage/revision_retention as storage_revision_retention
import ../../src/storage/node_repository as storage_node_repository
import ../../src/codec/bounded as codec_bounded
proc main() =
  ## Select dynamic valid/default/refused accesses so constant folding cannot replace contracts.
  let member = paramStr(1)
  let origin = paramStr(2)
  var repository = newNodeRepository(storageLimits())
  let view = repository.snapshot.value
  var catalog = newRevisionRetention(ElementLimit(1))
  if member == "result":
    let empty = default(RetentionResult[RetentionToken])
    let selected = if origin == "default": empty
      elif origin == "failed": catalog.retain(default(RepositoryView))
      else: catalog.retain(view)
    echo ord(catalog.lookup(selected.value).error)
  elif member == "lookup":
    let pin = catalog.retain(view).value
    let empty = default(RetentionResult[RepositoryView])
    let selected = if origin == "default": empty
      elif origin == "failed": catalog.lookup(default(RetentionToken))
      else: catalog.lookup(pin)
    echo selected.value.storedNodes
  else:
    let selected = if origin == "default": default(RevisionRetention) else: catalog
    echo selected.len
  discard catalog.close
  discard repository.close
main()
