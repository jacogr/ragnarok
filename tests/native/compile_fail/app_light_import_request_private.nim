# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot mutate admitted untrusted wire or replace its independently selected identity.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/app/light_proof_import as app_light_proof_import
let request = default(LightProofImport)
discard request.data
