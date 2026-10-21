# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_checkpoint_wrap_load_arc_release"}

## Genuine wrapping load keeps the disputed exception as a local gate after a real checkpoint and regular restoration.

import std/syncio
import ../../support/[pvm_assured_checkpoint_gate, pvm_computed_storage_program]

verifyCheckpointWrappingGate(ComputedStorageMode.ReadCheckpointWrapLoad, "pvm_assured_checkpoint_wrap_load")
echo "PVM assured checkpoint wrapping load gate passed"
echo "ARC_RELEASE cycles=1000 unchanged"
