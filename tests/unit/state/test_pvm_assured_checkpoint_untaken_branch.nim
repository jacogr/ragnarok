# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_checkpoint_untaken_branch_arc_release"}

## A false branch condition still panics on its negative destination and selects the real saved deletion.

import std/syncio
import ../../support/pvm_assured_checkpoint
import ../../support/pvm_computed_storage_program

verifyCheckpointDeletion(ComputedStorageMode.ReadCheckpointUntakenBranch,
  "pvm_assured_checkpoint_untaken_branch")
echo "PVM assured checkpoint untaken branch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
