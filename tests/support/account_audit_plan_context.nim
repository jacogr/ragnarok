# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent explicit policies support immutable whole-account audit planning and execution fixtures.
import ./account_invariant_context
import ../../src/state/account_audit_plan
import ../../src/codec/bounded
const accountAuditTestLimits* = AccountAuditLimits(planning: ElementLimit(5),
  footprints: invariantFootprintLimits, content: invariantContentLimits,
      linkage: invariantLinkageLimits)
