# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic proof-result/lookup misuse probes share a real successful empty-root control.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/storage/state_proof as storage_state_proof
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded
proc main() =
  ## Arguments select runtime invalid/default objects; compiler success is not a runtime verdict.
  let member = paramStr(1)
  let origin = paramStr(2)
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(256))
  let completed = verifyStateProof(default(StateRoot), default(StateKey), StateProof(), limits)
  assert completed.error == StateProofError.None
  if member == "result":
    var raw = default(array[32, byte])
    raw[0] = 1
    let selected = if origin == "default": default(StateProofResult[VerifiedStateLookup])
      elif origin == "failed": verifyStateProof(StateRoot(raw), default(StateKey), StateProof(), limits)
      else: completed
    echo selected.value.kind
  else:
    let lookup = if origin == "default": default(VerifiedStateLookup) else: completed.value
    case member
    of "root": echo array[32, byte](lookup.root)[0]
    of "key": echo array[31, byte](lookup.key)[0]
    of "kind": echo lookup.kind
    of "bytes": echo lookup.bytes.len
    else: assert false, "unknown proof result probe"
main()
