# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic codec guard probes share independently successful controls for every accessed representation.
import std/[assertions, cmdline, syncio]
import ../../src/storage/[paged_codec, database_identity, managed_manifest, light_delta]
import ../../src/codec/[bounded, state_trie]
proc main() =
  ## Runtime arguments select failed/default metadata without turning negative probes into compile-only evidence.
  let member = paramStr(1)
  let origin = paramStr(2)
  let limits = PagedLimits(entries: ElementLimit(2), bytes: ByteLimit(12512))
  let complete = initPagedHeader(default(StorageChainId), default(StateRoot), ManagedEpoch(1),
    LightDeltaSequence(0), 2, 82, limits)
  let checked = complete.value
  let shape = checked.geometry
  case member
  of "result":
    # A refused/default result must never expose its inactive header payload.
    let outcome = if origin == "default": default(PagedCodecResult[PagedHeader])
      elif origin == "failed": initPagedHeader(default(StorageChainId), default(StateRoot),
        ManagedEpoch(0), LightDeltaSequence(0), 2, 82, limits)
      else: complete
    discard outcome.value
  of "geometry":
    # Geometry scalars require prior complete arithmetic preflight.
    let selected = if origin == "default": default(PagedGeometry) else: shape
    discard selected.byteLength
  of "header":
    # Uninitialized headers cannot export plausible zero metadata or bytes.
    let selected = if origin == "default": default(PagedHeader) else: checked
    discard selected.bytes
  of "manifest":
    # A default manifest carries no initialized local digest selection.
    let valid = encodePagedManifest(checked, default(PagedDigest), ByteLimit(193)).value
    let selected = if origin == "default": default(PagedManifest) else: valid
    discard selected.pageRoot
  of "descriptor":
    # Payload offsets are available only after span validation.
    let valid = decodePagedDescriptor([0'u8, 0, 0], shape)
    var bytes = newSeq[byte](64)
    bytes[39] = 41
    let row = decodePagedDescriptor(bytes, shape).value
    let selected = if origin == "default": default(PagedDescriptor) else: row
    assert valid.error == PagedCodecError.InvalidFormat
    discard selected.offset
  of "path", "path-bound":
    # Both initialization and each variable step index are guarded.
    let valid = pagedPath(shape, PageOrdinal(0)).value
    let selected = if origin == "default": default(PagedPath) else: valid
    if member == "path": discard selected.len
    else:
      let index = if origin == "failed": 2 else: 0
      discard selected.step(index)
  of "step":
    # A fabricated default step cannot grant a disk location.
    let valid = pagedPath(shape, PageOrdinal(0)).value.step(0)
    let selected = if origin == "default": default(PagedPathStep) else: valid
    discard selected.offset
  of "proof":
    # One-record framing is not readable from default metadata.
    var bytes = newSeq[byte](64)
    bytes[39] = 41
    let row = decodePagedDescriptor(bytes, shape).value
    let valid = decodePagedProofShape(newSeq[byte](41), row, ElementLimit(249), ByteLimit(0)).value
    let selected = if origin == "default": default(PagedProofShape) else: valid
    discard selected.nodes
  else: assert false, "unknown paged codec guard"
  echo "0"
main()
