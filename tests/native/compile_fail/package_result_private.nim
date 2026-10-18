# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass private package/import state through completed.
import ../../../src/codec/[work_package, work_report]
var value = default(PackageResult[PackageRead])
discard value.completed
