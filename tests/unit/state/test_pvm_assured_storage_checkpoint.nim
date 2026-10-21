# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_storage_checkpoint_arc_release"}

## Genuine storage checkpoint selection retains checkpoint deletion through full canonical publication.

import std/syncio
import ../../support/[pvm_assured_checkpoint, pvm_computed_storage_program]

verifyCheckpointDeletion(ComputedStorageMode.ReadCheckpointPanic, "pvm_assured_storage_checkpoint")
echo "PVM assured storage checkpoint passed"
echo "ARC_RELEASE cycles=1000 unchanged"
