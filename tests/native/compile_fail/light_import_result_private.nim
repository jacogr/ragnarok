# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/failed authentication cannot expose or forge a successful imported batch.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/app/light/proof_import as light_proof_import
let outcome = default(LightImportResult[ImportedLightProofs])
discard outcome.completed
