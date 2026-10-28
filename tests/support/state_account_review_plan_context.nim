# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit report/admission policies select one economic profile without manufacturing prepared owners.
import ./state_account_audit_plan_context
import ./state_service_directory_context
import ../../src/state/account_review_plan as state_account_review_plan
import ../../src/state/supervision_table as state_supervision_table
import ../../src/state/economics_table as state_economics_table
import ../../src/codec/bounded as codec_bounded
const reviewPlanTestLimits* = AccountReviewPlanLimits(audit: accountAuditTestLimits,
  directory: directoryTestLimits,
  supervision: SupervisionTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)),
  economics: EconomicsTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)))
