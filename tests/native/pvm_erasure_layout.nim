# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked optimized erasure result guards with a genuine completed layout control.

import std/assertions
import std/cmdline
import ../../src/state/erasure_layout as state_erasure_layout
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/work_report as codec_work_report
import ../support/pvm_auditable_bundle
import ../support/pvm_bundle_vectors

proc check[T](outcome: ErasureLayoutResult[T], reason: ErasureLayoutError) =
  ## Inspect reasons before deliberately attempting refused extraction selected at runtime.
  assert outcome.error == reason, "erasure guard control"
let source = prepareAuditableBundle(bundleExecution(), ByteLimit(OrdinaryLength)).value
let done = prepareErasureLayout(source, ErasureShards(1023), ByteLimit(8892))
check(done, ErasureLayoutError.None)
assert done.value.originalChunk(OriginalShardIndex(341)).value.len == 26
let missing = default(ErasureLayoutResult[ErasureLayout])
let invalid = prepareErasureLayout(default(AuditableBundle), ErasureShards(6), ByteLimit(0))
check(invalid, ErasureLayoutError.InvalidSource)
let shards = erasureGeometry(BundleLength(0), ErasureShards(7))
check(shards, ErasureLayoutError.InvalidShards)
let limited = prepareErasureLayout(source, ErasureShards(1023), ByteLimit(8891))
check(limited, ErasureLayoutError.LimitExceeded)
let index = done.value.originalChunk(OriginalShardIndex(342))
check(index, ErasureLayoutError.InvalidIndex)
case paramStr(1)
of "default": discard missing.value # Defaults have no initialized owner.
of "source": discard invalid.value # Missing bundles cannot establish provenance.
of "shards": discard shards.value # Invalid validator domains have no geometry.
of "limit": discard limited.value # Refused buffers have no successful prefix.
of "index": discard index.value # Parity ordinals cannot manufacture original chunks.
of "info": discard default(ErasureLayout).layoutInfo.value # Missing owners have no geometry.
of "owner": discard default(ErasureLayout).layoutSource.value # Missing owners have no source.
else: discard default(ErasureLayout).originalChunk(OriginalShardIndex(0)).value # No default empty chunk.
