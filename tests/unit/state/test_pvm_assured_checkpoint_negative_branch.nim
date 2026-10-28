# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_checkpoint_negative_branch_arc_release"}

## A genuinely charged negative branch selects checkpoint deletion after actual regular restoration.

import std/syncio
import ../../support/pvm_assured_checkpoint
import ../../support/pvm_computed_storage_program

verifyCheckpointDeletion(ComputedStorageMode.ReadCheckpointNegativeBranch,
  "pvm_assured_checkpoint_negative_branch")
echo "PVM assured checkpoint negative branch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
