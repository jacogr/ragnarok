# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default worker receipts/admission cannot be mistaken for completed current disk IO or valid retirement authority.
import std/cmdline
import ../../src/app/disk/worker as disk_worker
let completion = default(DiskPublicationCompletion)
let admission = default(DiskPublicationAdmission)
case paramStr(1)
of "admission": discard admission.value # Only admitted submission grants a ticket.
of "maintenance": discard completion.maintenanceValue # Current publication never grants a maintenance receipt.
else: discard completion.value # Default completion is not a completed durable publication.
