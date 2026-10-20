# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/failed identity payloads and uninitialized scalar access require public contracts.
import std/[assertions, cmdline, syncio]
import ../../src/storage/database_identity
import ../../src/codec/bounded
proc main() =
  ## Dynamic origins retain genuine valid controls under identical checked native flags.
  let member = paramStr(1)
  let origin = paramStr(2)
  let chain = default(StorageChainId)
  let limit = ByteLimit(StorageIdentityBytes)
  if member == "bytes":
    let empty = default(IdentityResult[seq[byte]])
    let selected = if origin == "default": empty
      elif origin == "failed": encodeDatabaseIdentity(default(DatabaseIdentity), limit)
      else: encodeDatabaseIdentity(fullStateIdentity(chain), limit)
    echo selected.value.len
  elif member == "identity":
    let empty = default(IdentityResult[DatabaseIdentity])
    let wire = encodeDatabaseIdentity(fullStateIdentity(chain), limit).value
    let selected = if origin == "default": empty
      elif origin == "failed": decodeDatabaseIdentity([], chain, limit)
      else: decodeDatabaseIdentity(wire, chain, limit)
    discard selected.value.chainId
  else:
    let selected = if origin == "default": default(DatabaseIdentity) else: fullStateIdentity(chain)
    discard selected.chainId
main()
