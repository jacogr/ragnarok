# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Callers cannot forge complete lookup provenance or mutate directory storage.
import ../../../src/state/service_directory as state_service_directory
var value = default(ServiceDirectoryResult[StateServiceDirectory])
discard value.status
