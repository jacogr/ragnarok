# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_checkpoint_wrap_load_arc_release"}

## Genuine wrapping load uses the PolkaVM-aligned fault to select checkpoint deletion after a real checkpoint and regular restoration.

import std/syncio
import ../../support/pvm_assured_checkpoint
import ../../support/pvm_computed_storage_program

verifyCheckpointDeletion(ComputedStorageMode.ReadCheckpointWrapLoad, "pvm_assured_checkpoint_wrap_load")
echo "PVM assured checkpoint wrapping load passed"
echo "ARC_RELEASE cycles=1000 unchanged"
