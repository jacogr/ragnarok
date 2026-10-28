# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded predicate policies support join and consumer tests without manufacturing certificates.
import ../../src/state/footprint_audit as state_footprint_audit
import ../../src/state/preimage_content as state_preimage_content
import ../../src/state/preimage_linkage as state_preimage_linkage
import ../../src/codec/bounded as codec_bounded
const
  invariantFootprintLimits* = FootprintAuditLimits(services: ElementLimit(2), checks: ElementLimit(4))
  invariantContentLimits* = PreimageContentLimits(services: ElementLimit(2),
      preimages: ElementLimit(1), perValue: ByteLimit(3), totalBytes: ByteLimit(3))
  invariantLinkageLimits* = PreimageLinkageLimits(services: ElementLimit(2),
      preimages: ElementLimit(1), comparisons: ElementLimit(1))
