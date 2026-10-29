# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit restoration/review policies support complete same-source checkpoint review consumers.
import ./[planned_account_checkpoint_context, service_directory_context, account_invariant_context]
import ../../src/state/account/review/checkpoint as account_review_checkpoint
import ../../src/state/[supervision_table, economics_table]
import ../../src/codec/bounded
const accountReviewCheckpointTestLimits* = AccountReviewCheckpointLimits(
  checkpoint: plannedCheckpointTestLimits, directory: directoryTestLimits,
  footprints: invariantFootprintLimits,
  supervision: SupervisionTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)),
  economics: EconomicsTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)))
