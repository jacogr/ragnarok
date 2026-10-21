# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_checkpoint_wrap_store_arc_release"}

## Genuine wrapping store uses the PolkaVM-aligned fault to select checkpoint deletion after a real checkpoint and regular restoration.

import std/syncio
import ../../support/[pvm_assured_checkpoint, pvm_computed_storage_program]

verifyCheckpointDeletion(ComputedStorageMode.ReadCheckpointWrapStore, "pvm_assured_checkpoint_wrap_store")
echo "PVM assured checkpoint wrapping store passed"
echo "ARC_RELEASE cycles=1000 unchanged"
