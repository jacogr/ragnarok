# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit report/admission policies select one economic profile without manufacturing prepared owners.
import ./[account_audit_plan_context, service_directory_context]
import ../../src/state/account/review/plan as account_review_plan
import ../../src/state/[supervision_table, economics_table]
import ../../src/codec/bounded
const reviewPlanTestLimits* = AccountReviewPlanLimits(audit: accountAuditTestLimits,
  directory: directoryTestLimits,
  supervision: SupervisionTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)),
  economics: EconomicsTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)))
