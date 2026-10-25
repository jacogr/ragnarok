# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Verified imported facts expose no mutable batch or selected-identity backing.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/app/light_proof_import
let imported = default(ImportedLightProofs)
discard imported.data
