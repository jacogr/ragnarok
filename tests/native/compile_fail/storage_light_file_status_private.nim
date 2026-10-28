# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private light-file ownership/result storage cannot be forged by callers.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/storage/light_file_cache as storage_light_file_cache
var selected = default(LightFileResult[int])
discard selected.status
