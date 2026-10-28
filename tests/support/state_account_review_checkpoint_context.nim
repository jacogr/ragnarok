# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit restoration/review policies support complete same-source checkpoint review consumers.
import ./state_planned_account_checkpoint_context
import ./state_service_directory_context
import ./codec_account_invariant_context
import ../../src/state/account_review_checkpoint as state_account_review_checkpoint
import ../../src/state/supervision_table as state_supervision_table
import ../../src/state/economics_table as state_economics_table
import ../../src/codec/bounded as codec_bounded
const accountReviewCheckpointTestLimits* = AccountReviewCheckpointLimits(
  checkpoint: plannedCheckpointTestLimits, directory: directoryTestLimits,
  footprints: invariantFootprintLimits,
  supervision: SupervisionTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)),
  economics: EconomicsTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096)))
