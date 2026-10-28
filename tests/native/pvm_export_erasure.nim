# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized export/page result guards include genuine source-derived completed parity controls.

import std/assertions
import std/cmdline
import ../../src/state/export_erasure as state_export_erasure
import ../../src/state/bundle_erasure as state_bundle_erasure
import ../../src/state/erasure_words as state_erasure_words
import ../support/pvm_export_erasure

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse actual hashing only after the genuine original bundle and a successful export encoding exist.
proc check[T](outcome: ExportErasureResult[T], reason: ExportErasureError) =
  ## Observe exact runtime reasons before attempting deliberately refused extraction.
  assert outcome.error == reason, "export erasure guard control"
let source = exportBundle(1, 6)
let done = prepareExportErasure(source, exportErasureLimits())
check(done, ExportErasureError.None)
assert done.value.exportErasureChunk(ErasureShardIndex(5), ExportErasureIndex(1)).value.len == 1368
let missing = default(ExportErasureResult[ExportErasure])
let invalid = prepareExportErasure(default(BundleErasure), exportErasureLimits())
check(invalid, ExportErasureError.InvalidSource)
let limited = prepareExportErasure(source, ExportErasureLimits())
check(limited, ExportErasureError.LimitExceeded)
let index = done.value.exportErasureChunk(ErasureShardIndex(6), ExportErasureIndex(0))
check(index, ExportErasureError.InvalidIndex)
reset(1)
let failed = prepareExportErasure(source, exportErasureLimits())
check(failed, ExportErasureError.CommitmentFailure)
reset(0)
case paramStr(1)
of "default": discard missing.value # Defaults have no completed export encoding.
of "source": discard invalid.value # Detached/missing bundles have no original identity.
of "limit": discard limited.value # Refused coding limits expose no data prefix.
of "commitment": discard failed.value # Failed tree hashes cannot expose partial coding authority.
of "index": discard index.value # Out-of-range coordinates cannot invent a chunk.
of "info": discard default(ExportErasure).exportErasureInfo.value # Defaults have no root/work facts.
of "owner": discard default(ExportErasure).exportErasureSource.value # Defaults have no original bundle.
of "tree": discard default(ExportErasure).exportErasureCommitment.value # Defaults have no derived commitment.
else: discard default(ExportErasure).exportErasureChunk(ErasureShardIndex(0), ExportErasureIndex(
    0)).value # No default empty chunk.
