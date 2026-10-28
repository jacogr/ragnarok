# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject digest result forgery, writable retained storage and detached source substitution.

# @@Verification={"group": "nominal", "expected": "RefinedPackage", "early": ["prepareRefinementDigests(", "[1] expected: RefinedPackage but got: WorkDigest"]}

import ../../../src/state/refinement_digest as state_refinement_digest
import ../../../src/codec/work_digest as codec_work_digest
discard prepareRefinementDigests(default(WorkDigest), default(RefinementDigestLimits))
