# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit block selection is required before complete-state proof operations can establish lookup authority.
import std/[assertions, syncio, envvars]
import ../../../src/chain/[genesis, provider, state_proof]
import ../../../src/app/chain
import ../../../src/codec/[report_owned, header]
import ../../support/application_download_chain
import ../../../src/state/store
import ../../support/application_candidate_context
import ../../../src/state/[trie_proof, store]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc main() {.raises.} =
  ## Defaults and invalid captures must refuse without interpreting a zero root as authenticated emptiness.
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(100))
  let key = chapterKey(StateChapter(1))
  # Keep the tagged default opaque at the call boundary, as documented in Nimony compatibility.
  let defaultSelection = default(GenesisResult)
  assert generateBlockStateProof(defaultSelection, key, StateTrieLimits(),
      limits).error == StateProofError.Uninitialized
  assert generateBlockStateProof(invalidGenesis(), key, StateTrieLimits(), limits).error ==
      StateProofError.Uninitialized
  let empty = captureStateProof([], [], limits).value
  assert verifyBlockStateProof(defaultSelection, empty, key, limits).error ==
      StateProofError.Uninitialized
  assert verifyBlockStateProof(unavailableGenesis(), empty, key, limits).error ==
      StateProofError.Uninitialized
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i, octet in raw: wire[i] = byte(octet) # Decode the pinned report once under its explicit profile.
  let base = decodeOwnedReport(wire, 2).value
  let context = fixture(base)
  let chain = initialized(context)
  let selected = chain.chainView.bestBlock
  let source = chain.stateSnapshot.value
  let query = chapterKey(StateChapter(11))
  let proof = generateBlockStateProof(selected, query, policy().trie,
    StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))).value
  let checked = verifyBlockStateProof(selected, proof, query,
    StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))).value
  assert checked.present and checked.bytes == source.lookup(query).value.bytes
  let sequence = chainFixture(base, 3)
  for index, head in sequence.heads:
    # Recapture the exact original sealed header and posterior map, without fabricating a result tag.
    var headerBytes = newSeq[byte](head.header.headerInfo.value.consumed)
    assert encodeOwnedHeader(head.header, headerBytes).error == HeaderError.None
    let selectedHead = captureBlockSnapshot(headerBytes, head.stateSnapshot, head.chainParameters)
    assert selectedHead.error == GenesisError.None
    let proof = generateBlockStateProof(selectedHead, query, policy().trie,
      StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))).value
    let verified = verifyBlockStateProof(selectedHead, proof, query,
      StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))).value
    assert verified.bytes == head.stateSnapshot.lookup(query).value.bytes
    if index > 0:
      # A child's header commits its parent's state; that root must not authenticate the child's posterior proof.
      assert verifyStateProof(proof, head.priorStateRoot, query,
        StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))).error ==
            StateProofError.RootMismatch
      assert verifyBlockStateProof(selected, proof, query,
        StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(1000000))).error ==
            StateProofError.RootMismatch
  echo "chain-state-proof: ok"
try:
  main()
except:
  quit(2) # Missing/malformed signed fixture input is a test failure.
