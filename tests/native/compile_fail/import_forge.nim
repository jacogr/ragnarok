# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass private package/import state through referenceKind.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "referenceKind"}

import ../../../src/codec/work/[package as work_package, report as work_report]
var value = default(ImportReference)
discard ImportReference(referenceKind: ImportKind.Root)
