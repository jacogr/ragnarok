# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A package identity cannot construct the direct segment-root import alternative.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal","expected": "[1] expected: ReportHash[2] but got: ReportHash[0]"}

import ../../../src/codec/[work_package, work_report]
let wrong = rootImport(PackageHash(), ImportIndex(0))
discard wrong
