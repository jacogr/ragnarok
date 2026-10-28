# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_erasure_layout_arc_release"}

## Exhaustive validator geometry, systematic contiguous bytes and immutable executed-source ownership.

import std/assertions
import std/syncio
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/state/auditable_bundle as state_auditable_bundle
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
import ../../support/pvm_auditable_bundle
import ../../support/pvm_bundle_vectors
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse crypto after source execution to demonstrate pure layout preparation.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual primitive calls in the selected native observer.
proc expect[T](outcome: ErasureLayoutResult[T], reason: ErasureLayoutError) =
  ## Inspect exact reasons without extracting a refused value.
  assert outcome.error == reason, "erasure layout reason"

# Exhaust the entire nominal wire domain, including invalid gaps and values above the protocol maximum.
for shards in 0..65535:
  let computed = erasureGeometry(BundleLength(high(uint32)), ErasureShards(uint16(shards)))
  if shards >= 6 and shards <= 1023 and shards mod 3 == 0:
    expect(computed, ErasureLayoutError.None)
    let info = computed.value
    assert 2052 mod info.originalShards == 0, "original divisor"
    assert info.originalShards <= uint64(shards div 3+1), "reconstruction threshold"
    # Independently reject every larger possible candidate rather than duplicating the descending search.
    for candidate in int(info.originalShards)+1..shards div 3+1:
      assert 2052 mod candidate != 0, "maximal original divisor"
    assert info.paddedBytes == info.bundleChunkBytes*info.originalShards, "systematic extents"
    assert info.paddedBytes == uint64(high(uint32))+info.paddingBytes, "E4 arithmetic"
    assert info.paddingBytes < info.stripeBytes, "minimum padding"
    assert info.paddedBytes mod info.stripeBytes == 0, "word aligned stripes"
    assert info.encodedBytes == info.bundleChunkBytes*uint64(shards), "prospective encoded bytes"
    assert info.segmentChunkBytes*info.originalShards == 4104, "segments need no padding"
  else:
    expect(computed, ErasureLayoutError.InvalidShards) # Invalid validator counts never reach arithmetic or allocation.
let small = erasureGeometry(BundleLength(7), ErasureShards(6)).value
assert small.originalShards == 3, "six validators use three originals"
assert small.paddedBytes == 12, "seven bytes pad to twelve"
assert small.bundleChunkBytes == 4, "three contiguous four-byte chunks"
let large = erasureGeometry(BundleLength(8813), ErasureShards(1023)).value
assert large.originalShards == 342, "1023 validators use 342 originals"
assert large.stripeBytes == 684, "1023 stripe"
assert large.paddedBytes == 8892, "independent ordinary padding"
assert large.paddingBytes == 79, "independent ordinary suffix"
assert large.bundleChunkBytes == 26, "independent ordinary chunk"
assert large.segmentChunkBytes == 12, "independent segment chunk"
assert large.encodedBytes == 26598, "independent prospective encoding"
# Empty and aligned lengths add no block; both sides of each stripe boundary exercise minimum padding.
for shards in [6'u16, 1023]:
  let stripe = erasureGeometry(BundleLength(0), ErasureShards(shards)).value.stripeBytes
  for length in [0'u64, 1, stripe-1, stripe, stripe+1, stripe*2]:
    let info = erasureGeometry(BundleLength(uint32(length)), ErasureShards(shards)).value
    assert info.paddedBytes >= length, "padding covers input"
    assert info.paddingBytes < stripe, "padding shorter than stripe"
    if length mod stripe == 0:
      assert info.paddingBytes == 0, "aligned input has no extra block"
let bundle = prepareAuditableBundle(bundleExecution(), ByteLimit(OrdinaryLength)).value
let wire = bundle.bundleBytes.value
proc verify(source: AuditableBundle, shards: uint16) =
  ## Reconstruct contiguous original chunks and inspect every original and padded byte independently.
  let bytes = source.bundleBytes.value
  let info = erasureGeometry(source.bundleInfo.value.length, ErasureShards(shards)).value
  let layout = prepareErasureLayout(source, ErasureShards(shards), ByteLimit(
      info.paddedBytes)).value
  var cursor = 0
  # Concatenation is the formal systematic inverse, unlike stride-interleaving input pairs.
  for index in 0..<int(info.originalShards):
    let chunk = layout.originalChunk(OriginalShardIndex(uint64(index))).value
    assert chunk.len == int(info.bundleChunkBytes), "complete systematic chunk"
    for octet in chunk:
      if cursor < bytes.len:
        assert octet == bytes[cursor], "contiguous systematic byte order"
      else:
        assert octet == 0, "explicit padding byte"
      inc cursor
  assert cursor == int(info.paddedBytes), "all padded bytes reconstructed"
  expect(layout.originalChunk(OriginalShardIndex(info.originalShards)),
      ErasureLayoutError.InvalidIndex)
  expect(layout.originalChunk(OriginalShardIndex(high(uint64))), ErasureLayoutError.InvalidIndex)
  expect(prepareErasureLayout(source, ErasureShards(shards), ByteLimit(info.paddedBytes-1)),
      ErasureLayoutError.LimitExceeded)
verify(bundle, 6)
verify(bundle, 1023)
verify(prepareAuditableBundle(bundleExecution(rich = true), ByteLimit(RichLength)).value, 1023)
let layout = prepareErasureLayout(bundle, ErasureShards(1023), ByteLimit(8892)).value
var copied = layout.originalChunk(OriginalShardIndex(0)).value
copied[0] = copied[0] xor 1
assert layout.originalChunk(OriginalShardIndex(0)).value[0] == wire[0], "chunk copy isolation"
var copiedInfo = layout.layoutInfo.value
copiedInfo.originalShards = 0
assert layout.layoutInfo.value.originalShards == 342, "geometry copy isolation"
assert layout.layoutSource.value.bundleBytes.value == wire, "exact original source"
expect(default(ErasureLayout).layoutInfo, ErasureLayoutError.Uninitialized)
expect(default(ErasureLayout).layoutSource, ErasureLayoutError.Uninitialized)
expect(default(ErasureLayout).originalChunk(OriginalShardIndex(0)),
    ErasureLayoutError.Uninitialized)
expect(default(ErasureLayoutResult[ErasureLayout]), ErasureLayoutError.Uninitialized)
expect(prepareErasureLayout(default(AuditableBundle), ErasureShards(0), ByteLimit(0)),
    ErasureLayoutError.InvalidSource)
expect(prepareErasureLayout(bundle, ErasureShards(7), ByteLimit(0)),
    ErasureLayoutError.InvalidShards)
reset(1)
expect(prepareErasureLayout(bundle, ErasureShards(1023), ByteLimit(8892)), ErasureLayoutError.None)
assert hashes() == 0, "layout performs no hashes"
reset(0)
proc detached(): ErasureLayout =
  ## Retain original execution and bundle after all local construction temporaries retire.
  prepareErasureLayout(prepareAuditableBundle(bundleExecution(), ByteLimit(OrdinaryLength)).value,
    ErasureShards(1023), ByteLimit(8892)).value
assert detached().layoutSource.value.bundleBytes.value == wire, "detached source lifetime"
proc cycle() =
  ## Release retained padded bytes, copied chunks and failed candidates every iteration.
  let done = prepareErasureLayout(bundle, ErasureShards(1023), ByteLimit(8892)).value
  assert done.originalChunk(OriginalShardIndex(341)).value.len == 26, "last original chunk"
  expect(prepareErasureLayout(bundle, ErasureShards(1023), ByteLimit(8891)),
      ErasureLayoutError.LimitExceeded)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "erasure layout ARC release"
recordArcRelease("pvm_erasure_layout", 1000, before, after)
echo "PVM erasure layout passed"
echo "ARC_RELEASE cycles=1000 unchanged"
