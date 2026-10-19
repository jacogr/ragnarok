# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AdmittedReports", "early": ["prepareCoreActivity(", "[1] expected: AdmittedReports but got: CoreActivityProjection"]}

## A raw projection cannot replace genuine report admission and original block provenance.

import ../../../src/state/[core_activity]
var source: CoreActivityProjection
var config: CoreActivityConfig
discard prepareCoreActivity(source, config)
