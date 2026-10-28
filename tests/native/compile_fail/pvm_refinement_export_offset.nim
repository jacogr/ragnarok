# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Package export counts cannot silently replace the invocation's package offset.

# @@Verification={"group": "nominal", "expected": "ExportOffset", "early": ["captureRefinementExports(", "[1] expected: ExportOffset but got: ExportCount"]}

import ../../../src/pvm/refinement_exports as pvm_refinement_exports
import ../../../src/codec/work_digest as codec_work_digest
discard captureRefinementExports(ExportCount(0))
