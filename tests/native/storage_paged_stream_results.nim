# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic stream-result/metadata guard probes share real successful admission and lookup controls.
import std/assertions
import std/cmdline
import std/syncio
import ../support/storage_paged_reference
import ../../src/storage/paged_stream as storage_paged_stream
import ../../src/storage/paged_codec as storage_paged_codec
import ../../src/storage/database_identity as storage_database_identity
import ../../src/storage/state_proof as storage_state_proof
import ../../src/storage/light_state_cache as storage_light_state_cache
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
proc policy(): PagedStreamLimits =
  ## Small positive limits keep every control on the actual admission path.
  let maximum = ElementLimit(100000)
  let bytes = ByteLimit(1000000)
  PagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(2), bytes: bytes),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(100)),
    workingBytes: ByteLimit(100000), cachePages: ElementLimit(1),
    work: PagedWorkLimits(ioCalls: maximum, producerCalls: maximum, pageHashes: maximum,
      proofs: maximum, nodes: maximum, readBytes: bytes, writeBytes: bytes, valueBytes: bytes))
proc source(bytes: seq[byte]): PagedInput =
  ## Borrow a complete immutable test artifact; no result retains these synchronous closures.
  proc read(offset: PagedOffset, output: var openArray[byte]): bool {.closure.} =
    let start = uint64(offset)
    if start > uint64(bytes.len) or uint64(output.len) > uint64(bytes.len)-start: return false
    for index in 0..<output.len: output[index] = bytes[int(start)+index]
    true
  proc extent(output: var uint64): bool {.closure.} =
    output = uint64(bytes.len)
    true
  PagedInput(read: read, extent: extent)
proc main() =
  ## Dynamic CLI origins force actual runtime guards rather than constant-folded compile-time failures.
  let member = paramStr(1)
  let origin = paramStr(2)
  let reference = pagedReference(default(StorageChainId), default(StateRoot),
    @[LightStateProof(key: default(StateKey), proof: StateProof())])
  let selected = decodePagedManifest(reference.manifest, default(StorageChainId), default(
      StateRoot),
    policy().dataset, ByteLimit(193)).value
  let io = source(reference.bytes)
  let complete = validatePagedArtifact(io, selected, policy())
  assert complete.error == PagedStreamError.None
  case member
  of "result":
    # Default/refused results carry no checked artifact payload.
    let outcome = if origin == "default": default(PagedStreamResult[CheckedPagedArtifact])
      elif origin == "failed": validatePagedArtifact(default(PagedInput), selected, policy())
      else: complete
    discard outcome.value
  of "artifact":
    # Default metadata cannot manufacture a captured tree selection.
    let artifact = if origin == "default": default(CheckedPagedArtifact) else: complete.value
    discard artifact.manifest
  of "lookup":
    # Successful owned lookups require completed source-backed proof verification.
    let valid = lookupPaged(complete.value, io, default(StateKey), policy().work).value
    let lookup = if origin == "default": default(PagedLookup) else: valid
    discard lookup.verified
  of "counts":
    # No default or failed operation fabricates success statistics.
    let counts = if origin == "default": default(PagedStreamCounts) else: complete.value.counts
    discard counts.ioCalls
  of "proof":
    # Only a selected proof refusal exposes its cause, with a rehashed false proof as the positive control.
    let bad = pagedReference(default(StorageChainId), default(StateRoot),
      @[LightStateProof(key: default(StateKey), proof: StateProof(value: @[1'u8]))])
    let badSelection = decodePagedManifest(bad.manifest, default(StorageChainId), default(
        StateRoot),
      policy().dataset, ByteLimit(193)).value
    let valid = validatePagedArtifact(source(bad.bytes), badSelection, policy())
    assert valid.error == PagedStreamError.ProofFailure
    let outcome = if origin == "default": default(PagedStreamResult[CheckedPagedArtifact])
      elif origin == "failed": complete
      else: valid
    discard outcome.proofError
  else: assert false, "unknown paged stream probe"
  echo "0"
main()
