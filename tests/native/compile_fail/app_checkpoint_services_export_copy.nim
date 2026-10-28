# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Services independently rejects implicit duplication of its native worker children during actual ARC lowering.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <Services>", "build_name": "application-checkpoint-services-export-copy"}
import ../../../src/app/services as app_services
var original = default(Services)
var duplicate = original
original.close()
duplicate.close()
