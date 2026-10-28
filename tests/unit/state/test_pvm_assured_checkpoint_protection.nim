# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_checkpoint_protection_arc_release"}

## Genuine checkpoint protection selection retains checkpoint deletion through full canonical publication.

import std/syncio
import ../../support/pvm_assured_checkpoint
import ../../support/pvm_computed_storage_program

verifyCheckpointDeletion(ComputedStorageMode.ReadCheckpointProtection, "pvm_assured_checkpoint_protection")
echo "PVM assured checkpoint protection passed"
echo "ARC_RELEASE cycles=1000 unchanged"
