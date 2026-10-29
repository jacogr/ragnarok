# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retirement completion payloads remain inaccessible without their selected guarded accessor.
# @@Verification={"group":"privacy","expected":"retirementOutcome"}
import ../../../src/app/disk/worker as disk_worker
let completion = default(DiskPublicationCompletion)
discard completion.retirementOutcome
