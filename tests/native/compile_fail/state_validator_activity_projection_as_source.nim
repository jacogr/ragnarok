# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AdmittedReports", "early": ["prepareValidatorActivity(", "[1] expected: AdmittedReports but got: ValidatorActivityProjection"]}

## A raw projection cannot replace genuine report admission and original block provenance.

import ../../../src/state/validator_activity as state_validator_activity
var source: ValidatorActivityProjection
var config: ValidatorActivityConfig
discard prepareValidatorActivity(source, config)
