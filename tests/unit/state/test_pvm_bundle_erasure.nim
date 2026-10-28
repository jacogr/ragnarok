# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_bundle_erasure_arc_release"}

## Complete independent erasure bytes, exact aggregate caps and original executed-bundle provenance.

import std/assertions
import std/syncio
import ../../../src/state/auditable_bundle as state_auditable_bundle
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/state/erasure_words as state_erasure_words
import ../../../src/state/bundle_erasure as state_bundle_erasure
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
import ../../../src/crypto/primitives as crypto_primitives
import ../../support/pvm_auditable_bundle
import ../../support/pvm_bundle_vectors
import ../../support/pvm_bundle_erasure_vectors
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after original execution to demonstrate pure erasure preparation.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Inspect actual primitive calls without substituting successful hash results.
proc generous(): BundleErasureLimits =
  ## Bound selected real-fixture work and storage explicitly.
  BundleErasureLimits(bytes: ByteLimit(1000000), products: FieldProductLimit(10000000))
proc expect[T](outcome: BundleErasureResult[T], reason: BundleErasureError) =
  ## Check exact alternatives without reading refused encoded prefixes.
  assert outcome.error == reason, "bundle erasure reason"
proc layout(rich = false, small = false, shards = 1023'u16): ErasureLayout =
  ## Execute genuine original inputs and retain only their completed auditable layout.
  let bundle = prepareAuditableBundle(bundleExecution(rich = rich, exports = small), ByteLimit(20000)).value
  prepareErasureLayout(bundle, ErasureShards(shards), ByteLimit(20000)).value
proc verify(source: ErasureLayout, expected: array[32, byte]): BundleErasure =
  ## Compare every encoded chunk in validator order to an independently frozen full-buffer witness.
  let code = prepareBundleErasure(source, generous()).value
  let info = code.bundleErasureInfo.value
  let geometry = source.layoutInfo.value
  let bytes = source.layoutSource.value.bundleBytes.value
  var joined: seq[byte] = @[]
  # The hash commits every systematic/parity byte, including transpose direction and each LE word pair.
  for index in 0..<int(uint16(geometry.shards)):
    let chunk = code.bundleErasureChunk(ErasureShardIndex(uint64(index))).value
    assert chunk.len == int(geometry.bundleChunkBytes), "complete chunk extent"
    for octet in chunk: joined.add(octet)
  assert array[32, byte](blake2b256(joined).value) == expected, "independent complete encoded-buffer hash"
  assert uint64(joined.len) == geometry.encodedBytes, "complete encoded length"
  assert info.retainedBytes == geometry.encodedBytes, "retained output policy"
  assert uint32(info.length) == uint32(bytes.len), "original E4 length"
  assert info.packageHash.bytes == source.layoutSource.value.bundleInfo.value.packageHash.bytes, "original package identity"
  # The first d complete chunks reconstruct the padded source exactly, including a partial last word.
  for position in 0..<int(geometry.paddedBytes):
    if position < bytes.len:
      assert joined[position] == bytes[position], "systematic original bytes"
    else:
      assert joined[position] == 0, "explicit zero padding"
  var exact = BundleErasureLimits(bytes: ByteLimit(info.retainedBytes+info.workspaceBytes),
      products: FieldProductLimit(info.products))
  expect(prepareBundleErasure(source, exact), BundleErasureError.None)
  exact.bytes = ByteLimit(uint64(exact.bytes)-1)
  expect(prepareBundleErasure(source, exact), BundleErasureError.LimitExceeded)
  exact.bytes = ByteLimit(uint64(exact.bytes)+1)
  exact.products = FieldProductLimit(info.products-1)
  expect(prepareBundleErasure(source, exact), BundleErasureError.LimitExceeded)
  expect(code.bundleErasureChunk(ErasureShardIndex(uint64(uint16(geometry.shards)))),
      BundleErasureError.InvalidIndex)
  expect(code.bundleErasureChunk(ErasureShardIndex(high(uint64))), BundleErasureError.InvalidIndex)
  assert code.bundleErasureSource.value.layoutSource.value.bundleBytes.value == bytes, "exact original bundle source"
  code
let ordinary = layout()
let code = verify(ordinary, Ordinary1023Hash)
assert code.bundleErasureChunk(ErasureShardIndex(342)).value == @Ordinary1023First, "independent first parity LE bytes"
assert code.bundleErasureChunk(ErasureShardIndex(1022)).value == @Ordinary1023Last, "independent final parity LE bytes"
let info = code.bundleErasureInfo.value
assert info.products == 3982849, "independent complete column work"
assert info.workspaceBytes == 13251, "independent aggregate workspace"
assert info.retainedBytes == 26598, "independent encoded output extent"
let six = verify(layout(shards = 6), Ordinary6Hash)
assert six.bundleErasureInfo.value.products == 149838, "independent six-validator work"
let rich = verify(layout(rich = true), Rich1023Hash)
assert rich.bundleErasureChunk(ErasureShardIndex(342)).value == @Rich1023First, "rich first parity bytes"
assert rich.bundleErasureChunk(ErasureShardIndex(1022)).value == @Rich1023Last, "rich last parity bytes"
# Copies cannot modify retained chunk bytes or mutate original execution/geometry metadata.
var copied = code.bundleErasureChunk(ErasureShardIndex(342)).value
copied[0] = copied[0] xor 1
assert code.bundleErasureChunk(ErasureShardIndex(342)).value == @Ordinary1023First, "chunk copy isolation"
var copiedInfo = code.bundleErasureInfo.value
copiedInfo.geometry.originalShards = 0
copiedInfo.packageHash.bytes[0] = copiedInfo.packageHash.bytes[0] xor 1
assert code.bundleErasureInfo.value.geometry.originalShards == 342, "geometry copy isolation"
assert code.bundleErasureInfo.value.packageHash.bytes == info.packageHash.bytes, "identity copy isolation"
expect(default(BundleErasure).bundleErasureInfo, BundleErasureError.Uninitialized)
expect(default(BundleErasure).bundleErasureSource, BundleErasureError.Uninitialized)
expect(default(BundleErasure).bundleErasureChunk(ErasureShardIndex(0)),
    BundleErasureError.Uninitialized)
expect(prepareBundleErasure(default(ErasureLayout), BundleErasureLimits()),
    BundleErasureError.InvalidSource)
expect(default(BundleErasureResult[BundleErasure]), BundleErasureError.Uninitialized)
# No hashes are part of encoding; all original state/crypto-dependent construction precedes the backend refusal.
let small = layout(small = true, shards = 6)
reset(1)
expect(prepareBundleErasure(small, generous()), BundleErasureError.None)
expect(prepareBundleErasure(small, BundleErasureLimits()), BundleErasureError.LimitExceeded)
assert hashes() == 0, "bundle encoding performs no hashes"
reset(0)
proc detached(): BundleErasure =
  ## Retain encoded bytes and original execution after all construction temporaries retire.
  prepareBundleErasure(layout(small = true, shards = 6), generous()).value
assert detached().bundleErasureSource.value.layoutSource.value.bundleBytes.value ==
    small.layoutSource.value.bundleBytes.value, "detached source lifetime"
proc cycle() =
  ## Release complete encoded buffers, scalar code owners, input/workspace and refused candidates.
  let done = prepareBundleErasure(small, generous()).value
  assert done.bundleErasureChunk(ErasureShardIndex(5)).value.len > 0, "completed ARC parity control"
  expect(prepareBundleErasure(small, BundleErasureLimits()), BundleErasureError.LimitExceeded)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "bundle erasure ARC release"
recordArcRelease("pvm_bundle_erasure", 1000, before, after)
echo "PVM bundle erasure passed"
echo "ARC_RELEASE cycles=1000 unchanged"
