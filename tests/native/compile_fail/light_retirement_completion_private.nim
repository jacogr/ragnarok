# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Light retirement receipts remain private behind their distinct completion selector.
# @@Verification={"group":"privacy","expected":"lightRetirementOutcome"}
import ../../../src/app/disk_worker
let completion = default(DiskPublicationCompletion)
discard completion.lightRetirementOutcome
