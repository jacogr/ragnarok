# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent explicit policies support immutable whole-account audit planning and execution fixtures.
import ./codec_account_invariant_context
import ../../src/state/account_audit_plan as state_account_audit_plan
import ../../src/codec/bounded as codec_bounded
const accountAuditTestLimits* = AccountAuditLimits(planning: ElementLimit(5),
  footprints: invariantFootprintLimits, content: invariantContentLimits,
      linkage: invariantLinkageLimits)
