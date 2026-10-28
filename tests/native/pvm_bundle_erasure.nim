# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized result guards with genuine complete executed-bundle encoding controls.

import std/assertions
import std/cmdline
import ../../src/state/bundle_erasure as state_bundle_erasure
import ../../src/state/erasure_layout as state_erasure_layout
import ../../src/state/erasure_words as state_erasure_words
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/work_report as codec_work_report
import ../support/pvm_auditable_bundle

proc check[T](outcome: BundleErasureResult[T], reason: BundleErasureError) =
  ## Inspect runtime alternatives before deliberately selecting refused payloads.
  assert outcome.error == reason, "bundle erasure guard control"
let bundle = prepareAuditableBundle(bundleExecution(exports = true), ByteLimit(4096)).value
let source = prepareErasureLayout(bundle, ErasureShards(6), ByteLimit(4096)).value
let limits = BundleErasureLimits(bytes: ByteLimit(20000), products: FieldProductLimit(100000))
let done = prepareBundleErasure(source, limits)
check(done, BundleErasureError.None)
assert done.value.bundleErasureChunk(ErasureShardIndex(0)).value == source.originalChunk(
    OriginalShardIndex(0)).value
assert done.value.bundleErasureChunk(ErasureShardIndex(5)).value.len == int(
    source.layoutInfo.value.bundleChunkBytes)
let missing = default(BundleErasureResult[BundleErasure])
let invalid = prepareBundleErasure(default(ErasureLayout), limits)
check(invalid, BundleErasureError.InvalidSource)
let limited = prepareBundleErasure(source, BundleErasureLimits())
check(limited, BundleErasureError.LimitExceeded)
let index = done.value.bundleErasureChunk(ErasureShardIndex(6))
check(index, BundleErasureError.InvalidIndex)
case paramStr(1)
of "default": discard missing.value # Defaults have no successful encoding.
of "source": discard invalid.value # Missing layouts have no original executed bundle.
of "limit": discard limited.value # No partial encoded prefix escapes a local refusal.
of "index": discard index.value # Out-of-range ordinals cannot invent a chunk.
of "info": discard default(BundleErasure).bundleErasureInfo.value # Defaults have no work or identity facts.
of "owner": discard default(BundleErasure).bundleErasureSource.value # Defaults have no retained source.
else: discard default(BundleErasure).bundleErasureChunk(ErasureShardIndex(
    0)).value # Defaults have no empty chunk.
